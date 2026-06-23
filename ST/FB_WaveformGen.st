FUNCTION_BLOCK FB_WaveformGen
VAR_INPUT
	bEnable : BOOL; // 使能
	rPMin : REAL; // 最低压力 (MPa)
	rPMax : REAL; // 最高压力 (MPa)
	rFrequency : REAL; // 脉冲频率 (Hz)
	iWaveType : INT; // 波形类型 0=正弦 1=梯形 2=ARP1383水锤波
	rRisePct : REAL; // 梯形/水锤波上升段占比，默认0.1
	rHoldPct : REAL; // 梯形/水锤波保持段占比，默认0.3
	rFallPct : REAL; // 梯形下降段占比(默认0.1); 水锤波=阶跃下降的包络自由窗宽(指令无斜率, 默认0.05)
	rOvershoot : REAL; // 水锤波过冲峰倍数: P_OS = rOvershoot×PMax (rPMax 即 P_Oper); 写 <1 视为无效, 按 ARP1383C 3.1 取 1.5
	rRingPct : REAL; // 水锤波过冲后稳定段占比 (指令直接给PMax)，默认0.07
	rLowDwellPct : REAL; // 水锤波低保持段占比，默认0.48 (5段相对权重，内部归一化)
	rRiseRate : REAL := 0.0; // 水锤上升速率 (MPa/s); >0 时上升段按此速率生成斜坡(段宽=ΔP/速率×频率); ≤0 用 rRisePct 占比
	rDt : REAL; // 控制周期 (s)
	bReset : BOOL; // 复位相位
	nMffLeadSteps : INT; // MFF超前步数: 提前N步计算目标值给MFF使用
	rEnvPctP : REAL := 0.02; // 正弦(Fig.3)包络压力容差 ×PMax; 标准值 0.02 (写 ≤0 亦按 0.02); 梯形/水锤包络比例由 ARP1383C 固定
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
	rOS : REAL; // 水锤波过冲峰倍数 (保护后)
	rSum : REAL; // 水锤波 5 段占比和 (用于归一化)
	rPeakOS : REAL; // 水锤波过冲峰压力 = rOS×PMax (标准: 1.5×P_Oper)
	rPhaseLead : REAL; // 超前相位
	rEnvDP : REAL; // 正弦包络压力半带宽 (MPa)
	rET1 : REAL; // 包络段边界 1 (累积相位)
	rET2 : REAL; // 包络段边界 2
	rET3 : REAL; // 包络段边界 3
	rET4 : REAL; // 包络段边界 4 (仅水锤)
	rBaseUp : REAL; // 低压段包络上限 = max(1.1·PMin, 0.345MPa)
	rEnvPhU : REAL; // 正弦上包络相位: 向峰时移 W 后 (钳在峰)
	rEnvPhL : REAL; // 正弦下包络相位: 向谷时移 W 后 (钳在谷)
END_VAR
VAR CONSTANT
	// ===== ARP1383C 容差包络常数 (Fig.1 / Fig.2 / Fig.3) =====
	ENV_SINE_DP   : REAL := 0.02;  // Fig.3 正弦压力容差 ×PMax (TOLERANCE = .02 x PMax)
	ENV_SINE_W    : REAL := 0.05;  // Fig.3 ±时移 = 0.1C 驻留/畸变的一半 (MAX DWELL/DISTORTION = 0.1C)
	ENV_TRAP_UP   : REAL := 1.04;  // Fig.1 保压带上限 ×PMax
	ENV_TRAP_LO   : REAL := 0.96;  // Fig.1 保压带下限 ×PMax (带内驻留应为 10%~37% 周期)
	ENV_SLACK     : REAL := 0.05;  // Fig.1 升/降沿包络张开宽度 (周期占比)
	SHIFT_FALL_TO_HOLD : REAL := 0.2;  // 梯形: 内部把下降段前 20% 并入保持段 (外部输入不变), 下降起点拐点右移防 actual 滞后撞下限
	ENV_BASE_K    : REAL := 1.1;   // 低压段包络上限 ×PMin (Fig.1/2 公用)
	ENV_BASE_MIN  : REAL := 0.345; // 低压段包络上限下钳 (MPa, = 50 psi "BUT NOT LESS THAN")
	ENV_WH_PKTOL  : REAL := 0.04;  // Fig.2 过冲峰容差 ×P_OS (PEAK PRESSURE TOLERANCE ±4%)
	ENV_WH_UP     : REAL := 1.1;   // Fig.2 保压带上限 ×PMax (1.1·P_Oper)
	ENV_WH_RINGLO : REAL := 0.8;   // Fig.2 保压段起始下限 ×PMax (0.8·P_Oper)
	ENV_WH_HOLDLO : REAL := 0.95;  // Fig.2 保压段末端下限 ×PMax (0.95·P_Oper)
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
    // 内部把下降段前 SHIFT_FALL_TO_HOLD 比例并入保持段 (外部 rHoldPct/rFallPct 输入不变):
    //   保持平顶 +SHIFT×rF, 下降段缩为 (1-SHIFT)×rF; 下降终点与低保持 rL(缓降拖尾)不变。
    //   → 下降起点(及下包络拐点 rET2=rR+rH)右移, actual 滞后不再在下降起始拐点处撞下限。
    //   指令(FN_PulseWave)与包络(下方 CASE)都用此处 rH/rF, 故两者同步右移、带形与指令一致。
    rH := rH + SHIFT_FALL_TO_HOLD * rF;
    rF := (1.0 - SHIFT_FALL_TO_HOLD) * rF;
    rL := 1.0 - rR - rH - rF;
    IF rL < 0.0 THEN rL := 0.0; END_IF
    // 梯形不用 rRing/rPeakOS，置零以防函数访问无效值
    rRing := 0.0;
    rPeakOS := rPMax;

2:  // 水锤：上升段斜坡到 P_OS, 段宽可由"上升速率"定; 其余 4 段相对权重填满
    // 过冲峰 P_OS 先算 (上升速率换算相位宽时要用):
    // ARP1383C 3.1: P_OS = 1.5×P_Oper (rPMax 即 P_Oper); 倍数可调, 写 <1 按 1.5
    rOS := rOvershoot;
    IF rOS < 1.0 THEN rOS := 1.5; END_IF
    rPeakOS := rOS * rPMax;

    rRing := rRingPct;
    rH := rHoldPct;
    rF := rFallPct;
    rLow := rLowDwellPct;
    IF rRing < 0.01 THEN rRing := 0.07; END_IF
    IF rH < 0.01 THEN rH := 0.35; END_IF
    IF rF < 0.01 THEN rF := 0.05; END_IF
    IF rLow < 0.01 THEN rLow := 0.48; END_IF

    IF rRiseRate > 0.0 THEN
        // 上升段按速率定宽: t_rise = (P_OS - PMin)/速率[MPa/s]; 相位宽 = t_rise × 频率
        rR := (rPeakOS - rPMin) / rRiseRate * rFrequency;
        IF rR < 0.002 THEN rR := 0.002; END_IF   // 速率过快 → 近似阶跃 (下限保护避免除零)
        IF rR > 0.5   THEN rR := 0.5;   END_IF   // 速率过慢 → 上限钳到半周期
        // 其余 4 段按相对权重填满剩余 (1 - rR)
        rSum := rRing + rH + rF + rLow;
        IF rSum > 0.01 THEN
            rRing := rRing / rSum * (1.0 - rR);
            rH    := rH    / rSum * (1.0 - rR);
            rF    := rF    / rSum * (1.0 - rR);
            rLow  := rLow  / rSum * (1.0 - rR);
        END_IF
    ELSE
        // 速率未给 (≤0): 退回 5 段相对权重归一化 (上升段仍为斜坡, 宽度由 rRisePct 定)
        rR := rRisePct;
        IF rR < 0.01 THEN rR := 0.05; END_IF
        rSum := rR + rRing + rH + rF + rLow;
        IF rSum > 0.01 THEN
            rR    := rR    / rSum;
            rRing := rRing / rSum;
            rH    := rH    / rSum;
            rF    := rF    / rSum;
            rLow  := rLow  / rSum;
        END_IF
    END_IF

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
// ARP1383C 容差包络 — 按标准 Fig.1 / Fig.2 / Fig.3 阴影带生成
//
// 正弦  (Fig.3): 包络 = 真正弦整条曲线时移 ±0.05C + 压移 ±ΔP,
//               上下边界亦为正弦形、沿整条曲线等宽包裹标称 (非三角
//               近似)。峰/谷处时移钳到极值 → 平段 0.1C (最大驻留);
//               峰/谷垂直容差 ±ΔP (标准 0.02·PMax); PMean 处水平带宽
//               2·0.05C = 0.1C (最大畸变)。时移恒向极值 → 标称必在带内
// 梯形  (Fig.1 上图/供油腔): 保压带 [0.96, 1.04]·PMax; 低压段上限
//               1.1·PMin (不低于 0.345 MPa = 50 psi); 升/降沿包络边沿与
//               指令同斜率 (平行, 由指令仿射/相位平移生成 → 实际不撞沿):
//               上包络升沿=指令仿射到 1.04·PMax; 下包络=0.96·PMax×指令
//               归一(取 φ±ENV_SLACK 较小者 → 升沿滞后 slack/降沿提前 slack);
//               上包络下降段保持满量程 1.04·PMax 后自降沿结束缓降回
//               1.1·PMin (长拖尾, 允许实际慢泄压)
// 水锤  (Fig.2): 过冲峰+ring 段 (标准 0~15%C) 为全幅自由窗: 上包络
//               平直 1.04·P_OS (峰容差 ±4%, 峰值下限 0.96·P_OS 需另
//               行峰值检测)、下包络 0; 保压段上限 1.1·PMax / 下限
//               0.8→0.95·PMax 线性收紧; 下降窗 (标准 5%C) 亦为全幅
//               自由窗: 上包络保持 1.1·PMax 到窗尾、下包络立即落 0;
//               低压段 [0, 1.1·PMin]
// 注: Fig.1 保压带驻留 10%~37% 周期、Fig.3 试验条件 PMin=0.2·PMax
//     均为参数约束 (设参数时遵守), 不在包络内强制; Fig.1 下图回油
//     腔包络 (保压带 [0.9, 1.1]·PRMax, 低压上限 1.5·PMin) 本 FB 未
//     实现, 当前仅覆盖供油腔。
// ============================================================
rBaseUp := ENV_BASE_K * rPMin;
IF rBaseUp < ENV_BASE_MIN THEN rBaseUp := ENV_BASE_MIN; END_IF

CASE iWaveType OF

1:  // ---- 梯形 (Fig.1): 包络边沿与指令同斜率 (平行), 防实际撞沿 ----
    rET2 := rR + rH;        // 保压结束 / 降沿开始
    rET3 := rR + rH + rF;   // 降沿结束

    IF rPMax - rPMin > 0.001 THEN
        // 上包络: 升沿+保压 = 指令仿射映射 [PMin,PMax]→[1.1·PMin, 1.04·PMax] (升沿与指令同斜率,
        //   保压平直 1.04·PMax); 下降段保持满量程 1.04·PMax (给实际泄压留全幅余量), 自降沿结束
        //   缓降回 1.1·PMin (长拖尾, 允许实际慢泄压)。
        IF rPhase < rET2 THEN
            rTargetUpper := rBaseUp + (ENV_TRAP_UP * rPMax - rBaseUp) * (rTarget - rPMin) / (rPMax - rPMin);
        ELSIF rPhase < rET3 THEN
            rTargetUpper := ENV_TRAP_UP * rPMax;
        ELSIF rET3 < 0.999 THEN
            rTargetUpper := ENV_TRAP_UP * rPMax
                          + (rBaseUp - ENV_TRAP_UP * rPMax) * (rPhase - rET3) / (1.0 - rET3);
        ELSE
            rTargetUpper := rBaseUp;
        END_IF

        // 下包络: 0.96·PMax × 指令归一化(取 φ±ENV_SLACK 两相位中较小者) → 升沿滞后 slack、
        //   降沿提前 slack, 边沿与指令同斜率。降沿提前下落 → 下降中实际仍在其上方, 不撞下包络拐点。
        rEnvPhL := rPhase - ENV_SLACK; IF rEnvPhL < 0.0  THEN rEnvPhL := rEnvPhL + 1.0; END_IF
        rEnvPhU := rPhase + ENV_SLACK; IF rEnvPhU >= 1.0 THEN rEnvPhU := rEnvPhU - 1.0; END_IF
        rET1   := (FN_PulseWave(rPhaseIn := rEnvPhL, rPMin := rPMin, rPMax := rPMax, iWaveType := 1,
                                rR := rR, rH := rH, rF := rF, rRing := 0.0, rPeakOS := rPMax) - rPMin) / (rPMax - rPMin);
        rEnvDP := (FN_PulseWave(rPhaseIn := rEnvPhU, rPMin := rPMin, rPMax := rPMax, iWaveType := 1,
                                rR := rR, rH := rH, rF := rF, rRing := 0.0, rPeakOS := rPMax) - rPMin) / (rPMax - rPMin);
        IF rEnvDP < rET1 THEN rET1 := rEnvDP; END_IF        // 取较小归一化 (升沿滞后/降沿提前)
        rTargetLower := ENV_TRAP_LO * rPMax * rET1;
    ELSE
        rTargetUpper := rPMax;
        rTargetLower := rPMin;
    END_IF

2:  // ---- 水锤 (Fig.2) ----
    rET1 := rR;                      // 过冲峰段结束
    rET2 := rR + rRing;              // ring 段结束
    rET3 := rR + rRing + rH;         // 保压结束 / 下降开始
    rET4 := rR + rRing + rH + rF;    // 下降结束

    // 上包络: 峰+ring 整窗平直 1.04·P_OS (标准 0~15%C 全幅自由窗)
    //         → 保压/下降 1.1·PMax (上包络保持到下降段尾 = 标准 5%C 窗口)
    //         → 低压 1.1·PMin
    IF rPhase < rET2 THEN
        rTargetUpper := (1.0 + ENV_WH_PKTOL) * rPeakOS;
    ELSIF rPhase < rET4 THEN
        rTargetUpper := ENV_WH_UP * rPMax;
    ELSE
        rTargetUpper := rBaseUp;
    END_IF

    // 下包络: 峰+ring 整窗 0 (上升/振荡稳定自由窗)
    //         → 保压 0.8→0.95·PMax 线性收紧 (下降沿处达 0.95)
    //         → 下降窗起即落 0 (Fig.2 下降窗为全幅自由窗) → 低压 0
    IF rPhase < rET2 THEN
        rTargetLower := 0.0;
    ELSIF rPhase < rET3 THEN
        rTargetLower := ENV_WH_RINGLO * rPMax
                      + (ENV_WH_HOLDLO - ENV_WH_RINGLO) * rPMax * (rPhase - rET2) / (rET3 - rET2);
    ELSE
        rTargetLower := 0.0;
    END_IF

ELSE  // ---- 正弦 (Fig.3), 含未知类型兜底 ----
    // 包络 = 真正弦整条曲线时移 ±ENV_SINE_W (0.05C) 再 ±ΔP 压移:
    // 上下边界本身也是正弦形, 沿整条曲线等宽包裹标称 (非三角近似)。
    // 时移在峰/谷被钳到极值 → 峰/谷平段 0.1C (最大驻留); 峰/谷垂直
    // 容差 ±ΔP (标准 0.02·PMax); PMean (斜率最大) 处水平带宽 = 2·W
    // = 0.1C (最大畸变)。时移恒向极值方向 → 标称必在带内, 无需钳位。
    rEnvDP := rEnvPctP;
    IF rEnvDP <= 0.0 THEN rEnvDP := ENV_SINE_DP; END_IF
    rEnvDP := rEnvDP * rPMax;

    // 上包络: 标称正弦相位向峰 (0.5) 超前 W, 钳在峰; 整条 +ΔP
    IF rPhase <= 0.5 THEN
        rEnvPhU := rPhase + ENV_SINE_W;
        IF rEnvPhU > 0.5 THEN rEnvPhU := 0.5; END_IF
    ELSE
        rEnvPhU := rPhase - ENV_SINE_W;
        IF rEnvPhU < 0.5 THEN rEnvPhU := 0.5; END_IF
    END_IF
    rTargetUpper := FN_PulseWave(
        rPhaseIn := rEnvPhU, rPMin := rPMin, rPMax := rPMax, iWaveType := 0,
        rR := 0.0, rH := 0.0, rF := 0.0, rRing := 0.0, rPeakOS := rPMax) + rEnvDP;

    // 下包络: 标称正弦相位向谷 (0/1) 滞后 W, 钳在谷; 整条 -ΔP
    IF rPhase <= 0.5 THEN
        rEnvPhL := rPhase - ENV_SINE_W;
        IF rEnvPhL < 0.0 THEN rEnvPhL := 0.0; END_IF
    ELSE
        rEnvPhL := rPhase + ENV_SINE_W;
        IF rEnvPhL > 1.0 THEN rEnvPhL := 1.0; END_IF
    END_IF
    rTargetLower := FN_PulseWave(
        rPhaseIn := rEnvPhL, rPMin := rPMin, rPMax := rPMax, iWaveType := 0,
        rR := 0.0, rH := 0.0, rF := 0.0, rRing := 0.0, rPeakOS := rPMax) - rEnvDP;
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
