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
	rActual : REAL; // 实际反馈压力 (MPa) — 仅用于估计命令→实际相位滞后, 使包络与实际曲线对齐; 不接(=0)则滞后保持 0
	bEnvFollowActual : BOOL := TRUE; // 包络跟随实际相位: TRUE=按实际(滞后补偿)画包络; FALSE=按指令相位画(旧行为)
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
	rEnvLagPhase : REAL; // 估计的命令→实际相位滞后 (周期占比, 0~0.5) — 包络平移量, 诊断用
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
	rEnvRng : REAL; // 正弦包络: PMax-PMin (三角走廊斜率用)
	rPhaseEnv : REAL; // 包络评估相位 = rPhase - 滞后 (使包络对齐实际曲线)
	rEnvMean : REAL; // PMean = (PMax+PMin)/2 (滞后估计的过零电平)
	rEnvLagFilt : REAL; // EMA 平滑后的滞后估计 (周期占比)
	rLagRaw : REAL; // 本周期原始滞后 (实际过零相位 - 指令过零相位)
	rCmdCrossPhase : REAL; // 本周期指令上升过 PMean 的相位
	rCmdPrevX : REAL; // 上一步指令值 (过零检测)
	rActPrevX : REAL; // 上一步实际值 (过零检测)
	bCmdCrossed : BOOL; // 本周期指令已过 PMean (上升)
	bActCrossed : BOOL; // 本周期实际已过 PMean (上升)
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
	ENV_WH_RINGLO : REAL := 0.8;   // Fig.2 保压段起始下限 ×PMax (0.8·P_Oper)
	ENV_WH_HOLDLO : REAL := 0.95;  // Fig.2 保压段末端下限 ×PMax (0.95·P_Oper)
	ENV_LAG_LP    : REAL := 0.15;  // 滞后估计 EMA 系数 (每周期更新一次, 0.15 ≈ 7 周期收敛)
	ENV_LAG_MAX   : REAL := 0.5;   // 滞后估计限幅 (周期占比) — 防异常过零导致包络大幅错位
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
    // 滞后估计过零状态复位 (rEnvLagFilt 保留: 系统传输滞后跨测试不变)
    bCmdCrossed := FALSE;
    bActCrossed := FALSE;
    rCmdPrevX := rPMin;
    rActPrevX := rPMin;
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
// 正弦  (Fig.3): 直线走廊 (与标准图一致): 三角近似 ±0.05C 时移
//               ±ΔP (默认 2%·PMax)。上包络仅峰区平顶 0.1C (最大
//               驻留)、谷处 V 形; 下包络仅谷区平底 0.1C、峰处 Λ 形;
//               PMean 处水平带宽 ≈ 0.1C (最大畸变)
// 梯形  (Fig.1): 保压带 [0.96, 1.04]·PMax; 低压段上限 1.1·PMin
//               (不低于 0.345 MPa); 升沿: 上包络提前 ENV_SLACK 到顶/
//               下包络滞后 ENV_SLACK 到 0.96; 降沿: 下包络立即落 0,
//               上包络自下降结束后缓降至周期末 (允许实际压力长拖尾)
// 水锤  (Fig.2): 过冲峰+ring 段 (标准 0~15%C) 为全幅自由窗: 上包络
//               平直 1.04·P_OS (峰容差 ±4%)、下包络 0; 保压段上限
//               1.1·PMax / 下限 0.8→0.95·PMax 线性收紧; 下降段
//               (标准 5%C 窗口) 上包络保持到段尾; 低压段上限 1.1·PMin
// 注: Fig.1 标注的保压带驻留 10%~37% 周期为参数约束 (设 rHoldPct
//     时遵守), 不在包络内强制; 高 PMin 工况按标准 NOTE 可收紧为
//     [0.9, 1.1]·PMin, 当前未实现。
//
// 相位对齐: 实际压力相对指令有传输滞后, 若包络按指令相位画, 边沿处
//   实际会被误判出界。故用 PMean 上升过零估计 命令→实际 滞后, 平移
//   包络评估相位 (rPhaseEnv = rPhase - 滞后), 使容差带对齐实际曲线。
// ============================================================
rBaseUp := ENV_BASE_K * rPMin;
IF rBaseUp < ENV_BASE_MIN THEN rBaseUp := ENV_BASE_MIN; END_IF

// ---- 命令→实际 相位滞后估计 (PMean 上升过零, 每周期一次, EMA 平滑) ----
rEnvMean := (rPMax + rPMin) / 2.0;
IF bNewCycle THEN
    bCmdCrossed := FALSE;
    bActCrossed := FALSE;
END_IF
IF bEnvFollowActual THEN
    // 指令上升过 PMean → 记录指令过零相位
    IF (NOT bCmdCrossed) AND (rCmdPrevX < rEnvMean) AND (rTarget >= rEnvMean) THEN
        rCmdCrossPhase := rPhase;
        bCmdCrossed := TRUE;
    END_IF
    // 实际上升过 PMean (在指令过零之后) → 滞后 = 相位差, EMA 更新
    IF (NOT bActCrossed) AND bCmdCrossed AND (rActPrevX < rEnvMean) AND (rActual >= rEnvMean) THEN
        rLagRaw := rPhase - rCmdCrossPhase;
        IF rLagRaw < -0.5 THEN rLagRaw := rLagRaw + 1.0; END_IF
        IF rLagRaw >  0.5 THEN rLagRaw := rLagRaw - 1.0; END_IF
        rEnvLagFilt := rEnvLagFilt + ENV_LAG_LP * (rLagRaw - rEnvLagFilt);
        IF rEnvLagFilt >  ENV_LAG_MAX THEN rEnvLagFilt :=  ENV_LAG_MAX; END_IF
        IF rEnvLagFilt < -ENV_LAG_MAX THEN rEnvLagFilt := -ENV_LAG_MAX; END_IF
        bActCrossed := TRUE;
    END_IF
ELSE
    rEnvLagFilt := 0.0;
END_IF
rCmdPrevX := rTarget;
rActPrevX := rActual;
rEnvLagPhase := rEnvLagFilt;

// 包络评估相位 = 指令相位 - 滞后 (包络特征延后, 对齐滞后的实际)
rPhaseEnv := rPhase - rEnvLagFilt;
IF rPhaseEnv < 0.0  THEN rPhaseEnv := rPhaseEnv + 1.0; END_IF
IF rPhaseEnv >= 1.0 THEN rPhaseEnv := rPhaseEnv - 1.0; END_IF

CASE iWaveType OF

1:  // ---- 梯形 (Fig.1) ----
    rET1 := rR;             // 升沿结束
    rET2 := rR + rH;        // 保压结束 / 降沿开始
    rET3 := rR + rH + rF;   // 降沿结束

    // 上包络: (0, 1.1·PMin) → (T1-slack, 1.04·PMax) → 平 → (T3) → 缓降 → (1, 1.1·PMin)
    IF rPhaseEnv < rET1 - ENV_SLACK THEN
        rTargetUpper := rBaseUp + (ENV_TRAP_UP * rPMax - rBaseUp) * rPhaseEnv / (rET1 - ENV_SLACK);
    ELSIF rPhaseEnv < rET3 THEN
        rTargetUpper := ENV_TRAP_UP * rPMax;
    ELSIF rET3 < 0.999 THEN
        rTargetUpper := ENV_TRAP_UP * rPMax
                      + (rBaseUp - ENV_TRAP_UP * rPMax) * (rPhaseEnv - rET3) / (1.0 - rET3);
    ELSE
        rTargetUpper := rBaseUp;
    END_IF

    // 下包络: (0, 0) → (T1+slack, 0.96·PMax) → 平 → (T2) → (T2+slack, 0) → 0
    IF rPhaseEnv < rET1 + ENV_SLACK THEN
        rTargetLower := ENV_TRAP_LO * rPMax * rPhaseEnv / (rET1 + ENV_SLACK);
    ELSIF rPhaseEnv < rET2 THEN
        rTargetLower := ENV_TRAP_LO * rPMax;
    ELSIF rPhaseEnv < rET2 + ENV_SLACK THEN
        rTargetLower := ENV_TRAP_LO * rPMax * (1.0 - (rPhaseEnv - rET2) / ENV_SLACK);
    ELSE
        rTargetLower := 0.0;
    END_IF

2:  // ---- 水锤 (Fig.2) ----
    rET1 := rR;                      // 过冲峰段结束
    rET2 := rR + rRing;              // ring 段结束
    rET3 := rR + rRing + rH;         // 保压结束 / 下降开始
    rET4 := rR + rRing + rH + rF;    // 下降结束

    // 上包络: 峰+ring 整窗平直 1.04·P_OS (标准 0~15%C 全幅自由窗)
    //         → 保压/下降 1.1·PMax (上包络保持到下降段尾 = 标准 5%C 窗口)
    //         → 低压 1.1·PMin
    IF rPhaseEnv < rET2 THEN
        rTargetUpper := (1.0 + ENV_WH_PKTOL) * rPeakOS;
    ELSIF rPhaseEnv < rET4 THEN
        rTargetUpper := ENV_WH_UP * rPMax;
    ELSE
        rTargetUpper := rBaseUp;
    END_IF

    // 下包络: 峰+ring 整窗 0 (上升/振荡稳定自由窗)
    //         → 保压 0.8→0.95·PMax 线性收紧 → 下降段线性落 0 → 低压 0
    IF rPhaseEnv < rET2 THEN
        rTargetLower := 0.0;
    ELSIF rPhaseEnv < rET3 THEN
        rTargetLower := ENV_WH_RINGLO * rPMax
                      + (ENV_WH_HOLDLO - ENV_WH_RINGLO) * rPMax * (rPhaseEnv - rET2) / (rET3 - rET2);
    ELSIF rPhaseEnv < rET4 THEN
        rTargetLower := ENV_WH_HOLDLO * rPMax * (1.0 - (rPhaseEnv - rET3) / (rET4 - rET3));
    ELSE
        rTargetLower := 0.0;
    END_IF

ELSE  // ---- 正弦 (Fig.3), 含未知类型兜底 ----
    // 直线走廊 (与标准图样式一致): 把标称近似为三角波, ±ENV_SINE_W
    // 时移并 ±ΔP 压移。真正弦在走廊内 (ΔP ≥ 0.3%·PMax 时恒成立)。
    rEnvDP := rEnvPctP;
    IF rEnvDP <= 0.0 THEN rEnvDP := ENV_SINE_DP; END_IF
    rEnvDP := rEnvDP * rPMax;
    rEnvRng := rPMax - rPMin;

    // 上包络: 峰区平顶 0.1C (最大驻留), 其余为时移三角直线, 谷处 V 形
    IF ABS(rPhaseEnv - 0.5) <= ENV_SINE_W THEN
        rTargetUpper := rPMax + rEnvDP;
    ELSIF rPhaseEnv < 0.5 THEN
        rTargetUpper := rPMin + 2.0 * rEnvRng * (rPhaseEnv + ENV_SINE_W) + rEnvDP;
    ELSE
        rTargetUpper := rPMin + 2.0 * rEnvRng * (1.0 - rPhaseEnv + ENV_SINE_W) + rEnvDP;
    END_IF

    // 下包络: 谷区平底 0.1C (最大驻留), 其余为时移三角直线, 峰处 Λ 形
    IF rPhaseEnv <= ENV_SINE_W OR rPhaseEnv >= 1.0 - ENV_SINE_W THEN
        rTargetLower := rPMin - rEnvDP;
    ELSIF rPhaseEnv < 0.5 THEN
        rTargetLower := rPMin + 2.0 * rEnvRng * (rPhaseEnv - ENV_SINE_W) - rEnvDP;
    ELSE
        rTargetLower := rPMin + 2.0 * rEnvRng * (1.0 - rPhaseEnv - ENV_SINE_W) - rEnvDP;
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
