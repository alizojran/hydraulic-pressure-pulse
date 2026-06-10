FUNCTION_BLOCK FB_WaveformGen
VAR_INPUT
	bEnable : BOOL; // 使能
	rPMin : REAL; // 最低压力 (MPa)
	rPMax : REAL; // 最高压力 (MPa)
	rFrequency : REAL; // 脉冲频率 (Hz)
	iWaveType : INT; // 波形类型 0=正弦 1=梯形 2=ARP1383水锤波
	rRisePct : REAL; // 梯形/水锤波上升段占比，默认0.1
	rHoldPct : REAL; // 梯形/水锤波保持段占比，默认0.3
	rFallPct : REAL; // 梯形/水锤波下降段占比，默认0.1
	rOvershoot : REAL; // 水锤波过冲幅值占比 = (Pos-Pmax)/(Pmax-Pmin)，默认0.10
	rRingPct : REAL; // 水锤波过冲后稳定段占比 (指令直接给PMax)，默认0.07
	rLowDwellPct : REAL; // 水锤波低保持段占比，默认0.48 (5段相对权重，内部归一化)
	rDt : REAL; // 控制周期 (s)
	bReset : BOOL; // 复位相位
	nMffLeadSteps : INT; // MFF超前步数: 提前N步计算目标值给MFF使用
	rEnvPctP : REAL := 0.05; // ARP1383C 包络压力容差 ×PMax，默认 5%
END_VAR
VAR_OUTPUT
	rTarget : REAL; // 当前目标压力 (MPa)
	rTargetPrev : REAL; // 上一步目标压力 (用于MFF计算dP/dt)
	rTargetLead : REAL; // 超前目标压力 (MPa) — 给MFF使用
	rTargetLeadPrev : REAL; // 超前目标上一步值 — 给MFF计算dP/dt
	rTargetUpper : REAL; // ARP1383C 上包络 (MPa) — 实际压力允许上限
	rTargetLower : REAL; // ARP1383C 下包络 (MPa) — 实际压力允许下限
	rPhase : REAL; // 当前相位 (0~1)
	bNewCycle : BOOL; // 新周期开始脉冲 (相位过零)
	iPointIndex : INT; // 当前周期内采样点索引
	iPointsPerCycle : INT; // 每周期总采样点数
	// 归一化段宽 (供下游 FB_ILC 水锤波 5 段学习使用; 与内部计算同步)
	rSegRise : REAL; // 上升/过冲段归一化相位宽
	rSegRing : REAL; // (仅水锤) ring 衰减段归一化相位宽; 其他波形为 0
	rSegHold : REAL; // 保压段归一化相位宽
	rSegFall : REAL; // 下降段归一化相位宽
	rPeakOSOut : REAL; // (仅水锤) 过冲峰目标压力 (MPa); 其他波形 = rPMax
END_VAR
VAR
	rPhaseAcc : REAL; // 相位累加器 (0~1)
	rTargetLast : REAL; // 上一步计算值暂存
	rTargetLeadLast : REAL; // 超前目标上一步暂存
	bFirstRun : BOOL := TRUE;
	iIdxCounter : INT; // 采样点计数器
	rR : REAL; // 上升段占比 (归一化后)
	rH : REAL; // 保持段占比
	rF : REAL; // 下降段占比
	rL : REAL; // 梯形低保持段占比
	rRing : REAL; // 水锤波过冲后稳定段占比 (归一化后)
	rLow : REAL; // 水锤波低保持段占比 (归一化后)
	rOS : REAL; // 水锤波过冲幅值占比 (保护后)
	rSum : REAL; // 水锤波 5 段占比和 (用于归一化)
	rPeakOS : REAL; // 水锤波过冲峰压力 = Pmax + rOS*(Pmax-Pmin)
	rPhaseLead : REAL; // 超前相位
	rEnvDP : REAL; // 包络压力半带宽 (MPa)
END_VAR


// ============================================================
// 复位 / 失能
// ============================================================
IF bReset OR NOT bEnable THEN
    rPhaseAcc := 0.0;
    rTarget := rPMin;
    rTargetPrev := rPMin;
    rTargetLast := rPMin;
    rTargetLead := rPMin;
    rTargetLeadPrev := rPMin;
    rTargetLeadLast := rPMin;
    rTargetUpper := rPMin;
    rTargetLower := rPMin;
    bNewCycle := FALSE;
    bFirstRun := TRUE;
    iIdxCounter := 0;
    RETURN;
END_IF

// 频率保护
IF rFrequency < 0.01 THEN
    rTarget := rPMin;
    rTargetPrev := rPMin;
    rTargetUpper := rPMin;
    rTargetLower := rPMin;
    RETURN;
END_IF

// 每周期采样点数
iPointsPerCycle := REAL_TO_INT(1.0 / (rFrequency * rDt));
IF iPointsPerCycle < 10 THEN
    iPointsPerCycle := 10;
END_IF

// 保存上一步值
rTargetPrev := rTargetLast;

// 相位推进 (使用累加器避免长时间漂移)
rPhaseAcc := rPhaseAcc + rFrequency * rDt;
IF rPhaseAcc >= 1.0 THEN
    rPhaseAcc := rPhaseAcc - 1.0;
    bNewCycle := TRUE;
    iIdxCounter := 0;
ELSE
    bNewCycle := FALSE;
END_IF

rPhase := rPhaseAcc;
iPointIndex := iIdxCounter;


// ============================================================
// 段宽参数归一化 (每周期算一次即可，每步算无害)
// ============================================================
CASE iWaveType OF

1:  // 梯形：4 段 (rR + rH + rF + rL = 1)
    rR := rRisePct;
    rH := rHoldPct;
    rF := rFallPct;
    IF rR < 0.01 THEN rR := 0.1; END_IF
    IF rH < 0.01 THEN rH := 0.3; END_IF
    IF rF < 0.01 THEN rF := 0.1; END_IF
    rL := 1.0 - rR - rH - rF;
    IF rL < 0.0 THEN rL := 0.0; END_IF
    // 梯形不用 rRing/rPeakOS，置零以防函数访问无效值
    rRing := 0.0;
    rPeakOS := rPMax;

2:  // 水锤：5 段相对权重，强制 sum = 1
    rR := rRisePct;
    rRing := rRingPct;
    rH := rHoldPct;
    rF := rFallPct;
    rLow := rLowDwellPct;
    IF rR < 0.01 THEN rR := 0.05; END_IF
    IF rRing < 0.01 THEN rRing := 0.07; END_IF
    IF rH < 0.01 THEN rH := 0.35; END_IF
    IF rF < 0.01 THEN rF := 0.05; END_IF
    IF rLow < 0.01 THEN rLow := 0.48; END_IF
    rSum := rR + rRing + rH + rF + rLow;
    IF rSum > 0.01 THEN
        rR := rR / rSum;
        rRing := rRing / rSum;
        rH := rH / rSum;
        rF := rF / rSum;
        rLow := rLow / rSum;
    END_IF
    rOS := rOvershoot;
    IF rOS <= 0.0 THEN rOS := 0.10; END_IF
    rPeakOS := rPMax + rOS * (rPMax - rPMin);

ELSE
    // 正弦无段：把变量清成无害默认值
    rR := 0.0;
    rH := 0.0;
    rF := 0.0;
    rRing := 0.0;
    rPeakOS := rPMax;
END_CASE

// 段宽输出 (供下游 FB_ILC)
rSegRise   := rR;
rSegRing   := rRing;
rSegHold   := rH;
rSegFall   := rF;
rPeakOSOut := rPeakOS;


// ============================================================
// 主波形计算
// ============================================================
rTarget := FN_PulseWave(
    rPhaseIn := rPhase,
    rPMin := rPMin, rPMax := rPMax, iWaveType := iWaveType,
    rR := rR, rH := rH, rF := rF, rRing := rRing, rPeakOS := rPeakOS);


// ============================================================
// MFF 超前目标
// 用超前相位 (φ + N·Δφ) 计算未来 N 步的目标，给前馈控制器提前响应
// ============================================================
rTargetLeadPrev := rTargetLeadLast;

IF nMffLeadSteps > 0 THEN
    rPhaseLead := rPhaseAcc + INT_TO_REAL(nMffLeadSteps) * rFrequency * rDt;
    IF rPhaseLead >= 1.0 THEN rPhaseLead := rPhaseLead - 1.0; END_IF

    rTargetLead := FN_PulseWave(
        rPhaseIn := rPhaseLead,
        rPMin := rPMin, rPMax := rPMax, iWaveType := iWaveType,
        rR := rR, rH := rH, rF := rF, rRing := rRing, rPeakOS := rPeakOS);
ELSE
    rTargetLead := rTarget;
END_IF


// ============================================================
// ARP1383C 误差包络 (纯压力容差贴身带)
//
//   P_upper(φ) = P_nom(φ) + ΔP
//   P_lower(φ) = P_nom(φ) - ΔP，其中 ΔP = rEnvPctP × PMax (默认 5%)
//
// 注: 已取消时间容差功能 (原 φ±Δt 三相位采样)，包络在任意相位
// 都是标称波形上下各 ΔP 的等宽带。
// ============================================================
rEnvDP := rEnvPctP * rPMax;

rTargetUpper := rTarget + rEnvDP;
rTargetLower := rTarget - rEnvDP;
IF rTargetLower < 0.0 THEN rTargetLower := 0.0; END_IF
IF rTargetUpper > 50.0 THEN rTargetUpper := 50.0; END_IF


// ============================================================
// 首次运行初始化 (避免起步瞬间 dP/dt 出现伪大值)
// ============================================================
IF bFirstRun THEN
    rTargetPrev := rTarget;
    rTargetLeadPrev := rTargetLead;
    bFirstRun := FALSE;
END_IF

rTargetLast := rTarget;
rTargetLeadLast := rTargetLead;

iIdxCounter := iIdxCounter + 1;

END_FUNCTION_BLOCK
