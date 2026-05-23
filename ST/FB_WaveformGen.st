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
	rEnvPctT : REAL := 0.10; // ARP1383C 包络时间容差 ×周期，默认 10%
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
	rPhaseEarly : REAL; // 包络采样：早相位 (φ + Δt)
	rPhaseLate : REAL; // 包络采样：晚相位 (φ - Δt)
	rTargetEarly : REAL; // 早相位目标
	rTargetLate : REAL; // 晚相位目标
	rEnvDP : REAL; // 包络压力半带宽 (MPa)
	rEnvMax : REAL; // 三相位采样最大值
	rEnvMin : REAL; // 三相位采样最小值
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
// ARP1383C 误差包络 (三相位采样 + 压力容差带)
//
// 包络生成原理:
//   设当前相位 φ，时间容差 Δt = rEnvPctT × 周期 (归一化即 rEnvPctT)
//   在 φ-Δt, φ, φ+Δt 三个相位采样目标值，取 max/min:
//     P_upper(φ) = max{P_nom(φ'), φ' ∈ {φ-Δt, φ, φ+Δt}} + ΔP
//     P_lower(φ) = min{P_nom(φ'), φ' ∈ {φ-Δt, φ, φ+Δt}} - ΔP
//   其中压力容差 ΔP = rEnvPctP × PMax
//
//   这样:
//     正弦波 — 三点采样近似相等，包络 ≈ 主波形 ± ΔP
//     梯形波 — 上升/下降沿处三点跨越平台，包络自动张开 (上沿提前+晚段)
//     水锤波 — 过冲峰区采样到 P_OS，包络上沿包住尖峰
//
// ARP1383C 默认: ΔP = 5%·PMax, Δt = 10% 周期
// ============================================================
rEnvDP := rEnvPctP * rPMax;

// 三相位的早相 / 晚相，循环回卷到 [0, 1)
rPhaseEarly := rPhase + rEnvPctT;
IF rPhaseEarly >= 1.0 THEN rPhaseEarly := rPhaseEarly - 1.0; END_IF
rPhaseLate := rPhase - rEnvPctT;
IF rPhaseLate < 0.0 THEN rPhaseLate := rPhaseLate + 1.0; END_IF

rTargetEarly := FN_PulseWave(
    rPhaseIn := rPhaseEarly,
    rPMin := rPMin, rPMax := rPMax, iWaveType := iWaveType,
    rR := rR, rH := rH, rF := rF, rRing := rRing, rPeakOS := rPeakOS);
rTargetLate := FN_PulseWave(
    rPhaseIn := rPhaseLate,
    rPMin := rPMin, rPMax := rPMax, iWaveType := iWaveType,
    rR := rR, rH := rH, rF := rF, rRing := rRing, rPeakOS := rPeakOS);

// max / min over the three samples
rEnvMax := rTarget;
IF rTargetEarly > rEnvMax THEN rEnvMax := rTargetEarly; END_IF
IF rTargetLate > rEnvMax THEN rEnvMax := rTargetLate; END_IF
rEnvMin := rTarget;
IF rTargetEarly < rEnvMin THEN rEnvMin := rTargetEarly; END_IF
IF rTargetLate < rEnvMin THEN rEnvMin := rTargetLate; END_IF

rTargetUpper := rEnvMax + rEnvDP;
rTargetLower := rEnvMin - rEnvDP;
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
