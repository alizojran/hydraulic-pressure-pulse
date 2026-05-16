FUNCTION_BLOCK FB_ILC
VAR_INPUT
	bEnable : BOOL;
	rTargetRaw : REAL; // 原始目标值 (MPa)
	rActual : REAL; // 当前反馈值 (MPa)
	iPointIndex : INT; // 周期内采样点序号 (0 ~ iPointsPerCycle-1)
	iPointsPerCycle : INT;
	bNewCycle : BOOL;
	bReset : BOOL;
	iMaxIterations : INT;
	rLearningRate : REAL := 0.3; // 幅值 scale 学习率
	rAlphaLR : REAL := 0.4; // α 学习率
	bAlphaEnable : BOOL := TRUE; // α 自学习使能（FALSE = 4象限参数锁定不更新）
	nWarmupCycles : INT := 3; // 暖机周期数：前N个周期透传不修正，避免初始大误差超压
END_VAR
VAR_OUTPUT
	rOutput : REAL; // 修正量 = rVirtualTarget - rTargetRaw (MPa)
	rVirtualTarget : REAL; // 预畸变指令实时值 (MPa)
	iIteration : INT;
	rRmsError : REAL;
	bConverged : BOOL;
	rPeakError : REAL;
	rValleyError : REAL;
	rScalePos : REAL := 1.0; // 上半幅值放大系数
	rScaleNeg : REAL := 1.0; // 下半幅值放大系数
	rAlpha1Cmd : REAL := 0.25; // Q1 指令时长占比：上升 + 低于均值
	rAlpha2Cmd : REAL := 0.25; // Q2 指令时长占比：上升 + 高于均值
	rAlpha3Cmd : REAL := 0.25; // Q3 指令时长占比：下降 + 高于均值
	rAlpha4Cmd : REAL := 0.25; // Q4 指令时长占比：下降 + 低于均值
	rAlphaFb : REAL := 0.5; // 反馈过均值时长占比 = α2_fb+α3_fb（诊断）
END_VAR
VAR
	rMidpoint : REAL;
	rHalfRange : REAL;
	rTargetMax : REAL;
	rTargetMin : REAL;
	rActualMax : REAL;
	rActualMin : REAL;
	rPrevTargetMax : REAL;
	rPrevTargetMin : REAL;
	rPrevTargetRange : REAL;
	bNewCyclePrev : BOOL;
	iIterCount : INT;
	nScaleCycleCount : INT;
	rAmpFbPosSum : REAL;
	rAmpFbNegSum : REAL;
	rAmpFbPos : REAL;
	rAmpFbNeg : REAL;
	rErrorSum2 : REAL;
	iErrorCount : INT;
	iQ1Count : INT; // 反馈：上升 + 低于均值
	iQ2Count : INT; // 反馈：上升 + 高于均值
	iQ3Count : INT; // 反馈：下降 + 高于均值
	iQ4Count : INT; // 反馈：下降 + 低于均值
	rAlpha1Fb : REAL;
	rAlpha2Fb : REAL;
	rAlpha3Fb : REAL;
	rAlpha4Fb : REAL;
	rActualPrev : REAL;
	bFbRising : BOOL;
	rAlphaSum : REAL;
	rT1 : REAL;
	rT2 : REAL;
	rT3 : REAL;
	rDelta : REAL;
	rPhi : REAL;
	rPhiStd : REAL;
	rWarpedY : REAL;
	rWarpedTarget : REAL;
END_VAR
VAR CONSTANT
	SCALE_MIN : REAL := 0.2;
	SCALE_MAX : REAL := 5.0;
	ALPHA_Q_MIN : REAL := 0.05; // 每象限最小时长占比
	ALPHA_Q_MAX : REAL := 0.7; // 每象限最大时长占比
	TWO_PI : REAL := 6.283185307;
	CYCLES_PER_UPDATE : INT := 2;
END_VAR


// ============================================================
// 复位 / 禁用
// ============================================================
IF bReset OR NOT bEnable THEN
    IF bReset THEN
        iIterCount       := 0;
        nScaleCycleCount := 0;
        rAmpFbPosSum     := 0.0;
        rAmpFbNegSum     := 0.0;
        rRmsError        := 0.0;
        bConverged       := FALSE;
        rMidpoint        := 0.0;
        rHalfRange       := 0.0;
        rPrevTargetMax   := 0.0;
        rPrevTargetMin   := 0.0;
        rPrevTargetRange := 0.0;
        rAlpha1Cmd       := 0.25;
        rAlpha2Cmd       := 0.25;
        rAlpha3Cmd       := 0.25;
        rAlpha4Cmd       := 0.25;
        rAlphaFb         := 0.5;
        rScalePos        := 1.0;
        rScaleNeg        := 1.0;
        iQ1Count         := 0;
        iQ2Count         := 0;
        iQ3Count         := 0;
        iQ4Count         := 0;
        rActualPrev      := 0.0;
    END_IF
    rOutput        := 0.0;
    rVirtualTarget := 0.0;
    rTargetMax     := -1.0E30;
    rTargetMin     :=  1.0E30;
    rActualMax     := -1.0E30;
    rActualMin     :=  1.0E30;
    rErrorSum2     := 0.0;
    iErrorCount    := 0;
    iQ1Count       := 0;
    iQ2Count       := 0;
    iQ3Count       := 0;
    iQ4Count       := 0;
    bNewCyclePrev  := FALSE;
    IF NOT bEnable THEN
        RETURN;
    END_IF
END_IF

IF iPointsPerCycle < 10 THEN
    rOutput := 0.0; rVirtualTarget := 0.0; RETURN;
END_IF

// ============================================================
// 新周期边界
// ============================================================
IF bNewCycle AND NOT bNewCyclePrev THEN

    // RMS
    IF iErrorCount > 0 THEN
        rRmsError := SQRT(rErrorSum2 / INT_TO_REAL(iErrorCount));
    END_IF
    rErrorSum2  := 0.0;
    iErrorCount := 0;

    // 4象限 α_fb 计算
    rAlphaSum := INT_TO_REAL(iQ1Count + iQ2Count + iQ3Count + iQ4Count);
    IF rAlphaSum > 0.0 THEN
        rAlpha1Fb := INT_TO_REAL(iQ1Count) / rAlphaSum;
        rAlpha2Fb := INT_TO_REAL(iQ2Count) / rAlphaSum;
        rAlpha3Fb := INT_TO_REAL(iQ3Count) / rAlphaSum;
        rAlpha4Fb := INT_TO_REAL(iQ4Count) / rAlphaSum;
        rAlphaFb  := rAlpha2Fb + rAlpha3Fb;  // 过均值总占比（诊断）
    END_IF
    iQ1Count := 0; iQ2Count := 0; iQ3Count := 0; iQ4Count := 0;

    // 峰谷误差诊断（使用旧 rMidpoint）
    rPeakError   := rTargetMax - rActualMax;
    rValleyError := rTargetMin - rActualMin;
    rAmpFbPos    := rActualMax - rMidpoint;
    rAmpFbNeg    := rMidpoint  - rActualMin;

    // 更新中点 & 半幅
    rMidpoint  := (rTargetMax + rTargetMin) / 2.0;
    rHalfRange := (rTargetMax - rTargetMin) / 2.0;
    IF rHalfRange < 0.001 THEN rHalfRange := 0.001; END_IF

    rPrevTargetMax   := rTargetMax;
    rPrevTargetMin   := rTargetMin;
    rPrevTargetRange := rTargetMax - rTargetMin;

    rTargetMax := -1.0E30; rTargetMin :=  1.0E30;
    rActualMax := -1.0E30; rActualMin :=  1.0E30;

    iIterCount := iIterCount + 1;
    iIteration := iIterCount;

    IF iIterCount <= nWarmupCycles THEN
        // 暖机期：清空累积数据，等系统稳定，不让坏数据污染第一次更新
        rAmpFbPosSum     := 0.0;
        rAmpFbNegSum     := 0.0;
        nScaleCycleCount := 0;
    ELSIF NOT bConverged THEN
        IF iMaxIterations > 0 AND iIterCount >= iMaxIterations THEN
            bConverged := TRUE;
        ELSE
            // ---- α 4象限自学习 ----
            // 每象限目标均为 0.25，误差正 → 该象限时间不足 → 增大对应 αCmd
            IF bAlphaEnable THEN
                rAlpha1Cmd := rAlpha1Cmd + rAlphaLR * (0.25 - rAlpha1Fb);
                rAlpha2Cmd := rAlpha2Cmd + rAlphaLR * (0.25 - rAlpha2Fb);
                rAlpha3Cmd := rAlpha3Cmd + rAlphaLR * (0.25 - rAlpha3Fb);
                rAlpha4Cmd := rAlpha4Cmd + rAlphaLR * (0.25 - rAlpha4Fb);
                IF rAlpha1Cmd < ALPHA_Q_MIN THEN rAlpha1Cmd := ALPHA_Q_MIN; END_IF
                IF rAlpha1Cmd > ALPHA_Q_MAX THEN rAlpha1Cmd := ALPHA_Q_MAX; END_IF
                IF rAlpha2Cmd < ALPHA_Q_MIN THEN rAlpha2Cmd := ALPHA_Q_MIN; END_IF
                IF rAlpha2Cmd > ALPHA_Q_MAX THEN rAlpha2Cmd := ALPHA_Q_MAX; END_IF
                IF rAlpha3Cmd < ALPHA_Q_MIN THEN rAlpha3Cmd := ALPHA_Q_MIN; END_IF
                IF rAlpha3Cmd > ALPHA_Q_MAX THEN rAlpha3Cmd := ALPHA_Q_MAX; END_IF
                IF rAlpha4Cmd < ALPHA_Q_MIN THEN rAlpha4Cmd := ALPHA_Q_MIN; END_IF
                IF rAlpha4Cmd > ALPHA_Q_MAX THEN rAlpha4Cmd := ALPHA_Q_MAX; END_IF
                // 归一化，确保四象限之和 = 1
                rAlphaSum := rAlpha1Cmd + rAlpha2Cmd + rAlpha3Cmd + rAlpha4Cmd;
                IF rAlphaSum > 0.001 THEN
                    rAlpha1Cmd := rAlpha1Cmd / rAlphaSum;
                    rAlpha2Cmd := rAlpha2Cmd / rAlphaSum;
                    rAlpha3Cmd := rAlpha3Cmd / rAlphaSum;
                    rAlpha4Cmd := rAlpha4Cmd / rAlphaSum;
                END_IF
            END_IF

            // ---- 幅值自学习（每 CYCLES_PER_UPDATE 周期更新）----
            rAmpFbPosSum     := rAmpFbPosSum + rAmpFbPos;
            rAmpFbNegSum     := rAmpFbNegSum + rAmpFbNeg;
            nScaleCycleCount := nScaleCycleCount + 1;
            IF nScaleCycleCount >= CYCLES_PER_UPDATE THEN
                rAmpFbPos := rAmpFbPosSum / INT_TO_REAL(nScaleCycleCount);
                rAmpFbNeg := rAmpFbNegSum / INT_TO_REAL(nScaleCycleCount);
                IF rAmpFbPos > 0.001 THEN
                    rScalePos := rScalePos * (1.0 + rLearningRate * (rHalfRange / rAmpFbPos - 1.0));
                END_IF
                IF rAmpFbNeg > 0.001 THEN
                    rScaleNeg := rScaleNeg * (1.0 + rLearningRate * (rHalfRange / rAmpFbNeg - 1.0));
                END_IF
                IF rScalePos < SCALE_MIN THEN rScalePos := SCALE_MIN; END_IF
                IF rScalePos > SCALE_MAX THEN rScalePos := SCALE_MAX; END_IF
                IF rScaleNeg < SCALE_MIN THEN rScaleNeg := SCALE_MIN; END_IF
                IF rScaleNeg > SCALE_MAX THEN rScaleNeg := SCALE_MAX; END_IF
                rAmpFbPosSum     := 0.0;
                rAmpFbNegSum     := 0.0;
                nScaleCycleCount := 0;
            END_IF
        END_IF
    END_IF

END_IF

// ============================================================
// 每个采样点
// ============================================================

// 峰谷跟踪
IF rTargetRaw > rTargetMax THEN rTargetMax := rTargetRaw; END_IF
IF rTargetRaw < rTargetMin THEN rTargetMin := rTargetRaw; END_IF
IF rActual > rActualMax THEN rActualMax := rActual; END_IF
IF rActual < rActualMin THEN rActualMin := rActual; END_IF

// RMS
rErrorSum2  := rErrorSum2 + (rTargetRaw - rActual) * (rTargetRaw - rActual);
iErrorCount := iErrorCount + 1;

// 4象限采样（反馈上升/下降 × 高于/低于均值）
IF rActual >= rActualPrev THEN
    bFbRising := TRUE;
ELSE
    bFbRising := FALSE;
END_IF
rActualPrev := rActual;

IF bFbRising THEN
    IF rActual < rMidpoint THEN
        iQ1Count := iQ1Count + 1;   // Q1: 上升 + 低于均值
    ELSE
        iQ2Count := iQ2Count + 1;   // Q2: 上升 + 高于均值
    END_IF
ELSE
    IF rActual >= rMidpoint THEN
        iQ3Count := iQ3Count + 1;   // Q3: 下降 + 高于均值
    ELSE
        iQ4Count := iQ4Count + 1;   // Q4: 下降 + 低于均值
    END_IF
END_IF

// ---- 输出：4段线性相位畸变 + 幅值缩放 ----

// 归一化相位 φ ∈ [0,1)
IF iPointsPerCycle > 0 THEN
    rPhi := INT_TO_REAL(iPointIndex) / INT_TO_REAL(iPointsPerCycle);
ELSE
    rPhi := 0.0;
END_IF
IF rPhi < 0.0 THEN rPhi := 0.0; END_IF
IF rPhi > 1.0 THEN rPhi := 1.0; END_IF

// 4段线性相位畸变（累积断点 T1, T2, T3）
// [0, T1)         → φ_std ∈ [0,    0.25)  Q1段
// [T1, T2)        → φ_std ∈ [0.25, 0.50)  Q2段
// [T2, T3)        → φ_std ∈ [0.50, 0.75)  Q3段
// [T3, 1)         → φ_std ∈ [0.75, 1.0)   Q4段
rT1 := rAlpha1Cmd;
rT2 := rT1 + rAlpha2Cmd;
rT3 := rT2 + rAlpha3Cmd;

IF rPhi < rT1 THEN
    IF rT1 > 0.001 THEN
        rPhiStd := rPhi / rT1 * 0.25;
    ELSE
        rPhiStd := 0.0;
    END_IF
ELSIF rPhi < rT2 THEN
    rDelta := rT2 - rT1;
    IF rDelta > 0.001 THEN
        rPhiStd := 0.25 + (rPhi - rT1) / rDelta * 0.25;
    ELSE
        rPhiStd := 0.25;
    END_IF
ELSIF rPhi < rT3 THEN
    rDelta := rT3 - rT2;
    IF rDelta > 0.001 THEN
        rPhiStd := 0.50 + (rPhi - rT2) / rDelta * 0.25;
    ELSE
        rPhiStd := 0.50;
    END_IF
ELSE
    rDelta := 1.0 - rT3;
    IF rDelta > 0.001 THEN
        rPhiStd := 0.75 + (rPhi - rT3) / rDelta * 0.25;
    ELSE
        rPhiStd := 0.75;
    END_IF
END_IF

// 余弦波 → 归一化幅值 [0,1]
rWarpedY := (1.0 - COS(TWO_PI * rPhiStd)) / 2.0;

// 映射到目标压力范围
IF rPrevTargetRange > 0.001 THEN
    rWarpedTarget := rPrevTargetMin + rWarpedY * rPrevTargetRange;
ELSE
    rWarpedTarget := rTargetRaw;
END_IF

// 暖机期直接透传，不施加任何修正，防止初始大误差超压
IF iIterCount <= nWarmupCycles THEN
    rVirtualTarget := rTargetRaw;
ELSE
    // 上下半独立幅值缩放
    IF rWarpedTarget >= rMidpoint THEN
        rVirtualTarget := rMidpoint + (rWarpedTarget - rMidpoint) * rScalePos;
    ELSE
        rVirtualTarget := rMidpoint - (rMidpoint - rWarpedTarget) * rScaleNeg;
    END_IF
END_IF

rOutput := rVirtualTarget - rTargetRaw;

bNewCyclePrev := bNewCycle;

END_FUNCTION_BLOCK