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
	rEnvPctP : REAL := 0.05; // 正弦(Fig.3)包络压力容差 ×PMax; 写 ≤0 用标准值 0.02; 梯形/水锤包络比例由 ARP1383C 固定
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
	rEnvDP : REAL; // 正弦包络压力半带宽 (MPa)
	rET1 : REAL; // 包络段边界 1 (累积相位)
	rET2 : REAL; // 包络段边界 2
	rET3 : REAL; // 包络段边界 3
	rET4 : REAL; // 包络段边界 4 (仅水锤)
	rBaseUp : REAL; // 低压段包络上限 = max(1.1·PMin, 0.345MPa)
	rPhiSh : REAL; // 正弦包络时移相位
END_VAR
VAR CONSTANT
	// ===== ARP1383C 容差包络常数 (Fig.1 / Fig.2 / Fig.3) =====
	ENV_SINE_DP   : REAL := 0.02;  // Fig.3 正弦压力容差 ×PMax (TOLERANCE = .02 x PMax)
	ENV_SINE_W    : REAL := 0.05;  // Fig.3 ±时移 = 0.1C 驻留/畸变的一半 (MAX DWELL/DISTORTION = 0.1C)
	ENV_TRAP_UP   : REAL := 1.04;  // Fig.1 保压带上限 ×PMax
	ENV_TRAP_LO   : REAL := 0.96;  // Fig.1 保压带下限 ×PMax (带内驻留应为 10%~37% 周期)
	ENV_SLACK     : REAL := 0.05;  // Fig.1 升/降沿包络张开宽度 (周期占比)
	ENV_BASE_K    : REAL := 1.1;   // 低压段包络上限 ×PMin (Fig.1/2 公用)
	ENV_BASE_MIN  : REAL := 0.345; // 低压段包络上限下钳 (MPa, = 50 psi "BUT NOT LESS THAN")
	ENV_WH_PKTOL  : REAL := 0.04;  // Fig.2 过冲峰容差 ×P_OS (PEAK PRESSURE TOLERANCE ±4%)
	ENV_WH_UP     : REAL := 1.1;   // Fig.2 保压带上限 ×PMax (1.1·P_Oper)
	ENV_WH_RINGLO : REAL := 0.8;   // Fig.2 ring 段允许回落下限 ×PMax (0.8·P_Oper)
	ENV_WH_HOLDLO : REAL := 0.95;  // Fig.2 保压末端下限 ×PMax (0.95·P_Oper)
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
// ARP1383C 容差包络 — 按标准 Fig.1 / Fig.2 / Fig.3 分波形生成
//
// 正弦  (Fig.3): 标称 ±ΔP (默认 2%·PMax); 峰/谷允许 0.1C 驻留,
//               PMean 处允许 0.1C 时间畸变 → 实现为 ±0.05C 时移包络:
//               上包络取向峰时移、下包络取向谷时移的标称值 ±ΔP
// 梯形  (Fig.1): 保压带 [0.96, 1.04]·PMax; 低压段上限 1.1·PMin
//               (不低于 0.345 MPa); 升沿: 上包络提前 ENV_SLACK 到顶/
//               下包络滞后 ENV_SLACK 到 0.96; 降沿: 下包络立即落 0,
//               上包络自下降结束后缓降至周期末 (允许实际压力长拖尾)
// 水锤  (Fig.2): 过冲峰段 ±4%·P_OS; ring 段上包络线性收至 1.1·PMax,
//               下限 0.8·PMax; 保压带上限 1.1·PMax / 下限 0.8→0.95
//               线性收紧; 下降段 (标准为 5%C 窗口) 上包络保持到段尾;
//               低压段上限 1.1·PMin
// 注: Fig.1 标注的保压带驻留 10%~37% 周期为参数约束 (设 rHoldPct
//     时遵守), 不在包络内强制; 高 PMin 工况按标准 NOTE 可收紧为
//     [0.9, 1.1]·PMin, 当前未实现。
// ============================================================
rBaseUp := ENV_BASE_K * rPMin;
IF rBaseUp < ENV_BASE_MIN THEN rBaseUp := ENV_BASE_MIN; END_IF

CASE iWaveType OF

1:  // ---- 梯形 (Fig.1) ----
    rET1 := rR;             // 升沿结束
    rET2 := rR + rH;        // 保压结束 / 降沿开始
    rET3 := rR + rH + rF;   // 降沿结束

    // 上包络: (0, 1.1·PMin) → (T1-slack, 1.04·PMax) → 平 → (T3) → 缓降 → (1, 1.1·PMin)
    IF rPhase < rET1 - ENV_SLACK THEN
        rTargetUpper := rBaseUp + (ENV_TRAP_UP * rPMax - rBaseUp) * rPhase / (rET1 - ENV_SLACK);
    ELSIF rPhase < rET3 THEN
        rTargetUpper := ENV_TRAP_UP * rPMax;
    ELSIF rET3 < 0.999 THEN
        rTargetUpper := ENV_TRAP_UP * rPMax
                      + (rBaseUp - ENV_TRAP_UP * rPMax) * (rPhase - rET3) / (1.0 - rET3);
    ELSE
        rTargetUpper := rBaseUp;
    END_IF

    // 下包络: (0, 0) → (T1+slack, 0.96·PMax) → 平 → (T2) → (T2+slack, 0) → 0
    IF rPhase < rET1 + ENV_SLACK THEN
        rTargetLower := ENV_TRAP_LO * rPMax * rPhase / (rET1 + ENV_SLACK);
    ELSIF rPhase < rET2 THEN
        rTargetLower := ENV_TRAP_LO * rPMax;
    ELSIF rPhase < rET2 + ENV_SLACK THEN
        rTargetLower := ENV_TRAP_LO * rPMax * (1.0 - (rPhase - rET2) / ENV_SLACK);
    ELSE
        rTargetLower := 0.0;
    END_IF

2:  // ---- 水锤 (Fig.2) ----
    rET1 := rR;                      // 过冲峰段结束
    rET2 := rR + rRing;              // ring 段结束
    rET3 := rR + rRing + rH;         // 保压结束 / 下降开始
    rET4 := rR + rRing + rH + rF;    // 下降结束

    // 上包络: 峰段 1.04·P_OS → ring 线性收至 1.1·PMax → 保压/下降平 1.1·PMax → 低压 1.1·PMin
    IF rPhase < rET1 THEN
        rTargetUpper := (1.0 + ENV_WH_PKTOL) * rPeakOS;
    ELSIF rPhase < rET2 THEN
        rTargetUpper := (1.0 + ENV_WH_PKTOL) * rPeakOS
                      + (ENV_WH_UP * rPMax - (1.0 + ENV_WH_PKTOL) * rPeakOS)
                        * (rPhase - rET1) / (rET2 - rET1);
    ELSIF rPhase < rET4 THEN
        rTargetUpper := ENV_WH_UP * rPMax;
    ELSE
        rTargetUpper := rBaseUp;
    END_IF

    // 下包络: 峰段 0 (上升中) → ring 0.8·PMax → 保压 0.8→0.95 线性 → 下降段线性落 0 → 低压 0
    IF rPhase < rET1 THEN
        rTargetLower := 0.0;
    ELSIF rPhase < rET2 THEN
        rTargetLower := ENV_WH_RINGLO * rPMax;
    ELSIF rPhase < rET3 THEN
        rTargetLower := ENV_WH_RINGLO * rPMax
                      + (ENV_WH_HOLDLO - ENV_WH_RINGLO) * rPMax * (rPhase - rET2) / (rET3 - rET2);
    ELSIF rPhase < rET4 THEN
        rTargetLower := ENV_WH_HOLDLO * rPMax * (1.0 - (rPhase - rET3) / (rET4 - rET3));
    ELSE
        rTargetLower := 0.0;
    END_IF

ELSE  // ---- 正弦 (Fig.3), 含未知类型兜底 ----
    rEnvDP := rEnvPctP;
    IF rEnvDP <= 0.0 THEN rEnvDP := ENV_SINE_DP; END_IF
    rEnvDP := rEnvDP * rPMax;

    // 上包络: 向峰 (φ=0.5) 时移 ENV_SINE_W; 峰区平顶 = 0.1C 最大驻留
    IF ABS(rPhase - 0.5) <= ENV_SINE_W THEN
        rTargetUpper := rPMax + rEnvDP;
    ELSE
        IF rPhase < 0.5 THEN rPhiSh := rPhase + ENV_SINE_W; ELSE rPhiSh := rPhase - ENV_SINE_W; END_IF
        rTargetUpper := FN_PulseWave(
            rPhaseIn := rPhiSh,
            rPMin := rPMin, rPMax := rPMax, iWaveType := 0,
            rR := 0.0, rH := 0.0, rF := 0.0, rRing := 0.0, rPeakOS := rPMax) + rEnvDP;
    END_IF

    // 下包络: 向谷 (φ=0/1) 时移 ENV_SINE_W; 谷区平底 = 0.1C 最大驻留
    IF rPhase <= ENV_SINE_W OR rPhase >= 1.0 - ENV_SINE_W THEN
        rTargetLower := rPMin - rEnvDP;
    ELSE
        IF rPhase < 0.5 THEN rPhiSh := rPhase - ENV_SINE_W; ELSE rPhiSh := rPhase + ENV_SINE_W; END_IF
        rTargetLower := FN_PulseWave(
            rPhaseIn := rPhiSh,
            rPMin := rPMin, rPMax := rPMax, iWaveType := 0,
            rR := 0.0, rH := 0.0, rF := 0.0, rRing := 0.0, rPeakOS := rPMax) - rEnvDP;
    END_IF
END_CASE

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
