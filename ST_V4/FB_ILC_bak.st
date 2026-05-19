FUNCTION_BLOCK FB_ILC_bak
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
	rAlphaLR : REAL := 0.4; // α 学习率（仅正弦/三角波有效）
	bAlphaEnable : BOOL := TRUE; // α 自学习使能（FALSE = 4象限参数锁定不更新）
	nWarmupCycles : INT := 3; // 暖机周期数：前N个周期透传不修正，同时完成波形类型检测
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
	nWaveType : INT := 0; // 检测到的波形类型：0=检测中, 1=正弦, 2=三角, 3=梯形, 4=矩形, 5=任意波
	rFlatFrac : REAL; // 指令峰谷附近时间占比（波形类型判断依据，诊断）
	rSymFrac : REAL; // 指令在均值以上时间占比（对称性，诊断：0.5=对称，偏离大→任意波）
	rTopSatRatio : REAL; // 顶部饱和比 = 反馈近顶停留比 - 指令近顶停留比（>SAT_TOL 视为饱和）
	rBotSatRatio : REAL; // 谷部饱和比 = 反馈近谷停留比 - 指令近谷停留比（>SAT_TOL 视为饱和）
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
	iQ1Count : INT;
	iQ2Count : INT;
	iQ3Count : INT;
	iQ4Count : INT;
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
	iNearExtCount : INT; // 暖机期：指令接近峰谷的采样点数（用于波形类型检测）
	iTargetAboveMidCount : INT; // 暖机期：指令在均值以上的采样点数（用于对称性检测）
	iTotalDetectCount : INT; // 暖机期：有效检测采样总数
	bWaveDetected : BOOL; // 波形类型已检测完成
	iTargetNearTop : INT; // 当前周期：目标在自身上半 10% 内的采样数
	iTargetNearBot : INT; // 当前周期：目标在自身下半 10% 内的采样数
	iActualNearTop : INT; // 当前周期：反馈在自身上半 10% 内的采样数
	iActualNearBot : INT; // 当前周期：反馈在自身下半 10% 内的采样数
END_VAR


// ============================================================
// 复位 / 禁用
// ============================================================
IF bReset OR NOT bEnable THEN
    IF bReset THEN
        iIterCount        := 0;
        nScaleCycleCount  := 0;
        rAmpFbPosSum      := 0.0;
        rAmpFbNegSum      := 0.0;
        rRmsError         := 0.0;
        bConverged        := FALSE;
        rMidpoint         := 0.0;
        rHalfRange        := 0.0;
        rPrevTargetMax    := 0.0;
        rPrevTargetMin    := 0.0;
        rPrevTargetRange  := 0.0;
        rAlpha1Cmd        := 0.25;
        rAlpha2Cmd        := 0.25;
        rAlpha3Cmd        := 0.25;
        rAlpha4Cmd        := 0.25;
        rAlphaFb          := 0.5;
        rScalePos         := 1.0;
        rScaleNeg         := 1.0;
        iQ1Count          := 0;
        iQ2Count          := 0;
        iQ3Count          := 0;
        iQ4Count          := 0;
        rActualPrev       := 0.0;
        nWaveType              := 0;
        rFlatFrac              := 0.0;
        rSymFrac               := 0.0;
        iNearExtCount          := 0;
        iTargetAboveMidCount   := 0;
        iTotalDetectCount      := 0;
        bWaveDetected          := FALSE;
        rTopSatRatio           := 0.0;
        rBotSatRatio           := 0.0;
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
    iTargetNearTop := 0;
    iTargetNearBot := 0;
    iActualNearTop := 0;
    iActualNearBot := 0;
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
        rAlphaFb  := rAlpha2Fb + rAlpha3Fb;
    END_IF
    iQ1Count := 0; iQ2Count := 0; iQ3Count := 0; iQ4Count := 0;

    rPeakError   := rTargetMax - rActualMax;
    rValleyError := rTargetMin - rActualMin;
    rAmpFbPos    := rActualMax - rMidpoint;
    rAmpFbNeg    := rMidpoint  - rActualMin;

    rMidpoint  := (rTargetMax + rTargetMin) / 2.0;
    rHalfRange := (rTargetMax - rTargetMin) / 2.0;
    IF rHalfRange < 0.001 THEN rHalfRange := 0.001; END_IF

    // ---- 饱和检测：本周期反馈/指令近峰停留比之差，正值表示反馈被削顶/削底 ----
    IF iPointsPerCycle > 0 THEN
        rTopSatRatio := INT_TO_REAL(iActualNearTop - iTargetNearTop) / INT_TO_REAL(iPointsPerCycle);
        rBotSatRatio := INT_TO_REAL(iActualNearBot - iTargetNearBot) / INT_TO_REAL(iPointsPerCycle);
    END_IF
    iTargetNearTop := 0; iTargetNearBot := 0;
    iActualNearTop := 0; iActualNearBot := 0;

    rPrevTargetMax   := rTargetMax;
    rPrevTargetMin   := rTargetMin;
    rPrevTargetRange := rTargetMax - rTargetMin;

    rTargetMax := -1.0E30; rTargetMin :=  1.0E30;
    rActualMax := -1.0E30; rActualMin :=  1.0E30;

    iIterCount := iIterCount + 1;
    iIteration := iIterCount;

    IF iIterCount <= nWarmupCycles THEN
        // ---- 暖机期末：完成波形类型检测 ----
        IF iIterCount = nWarmupCycles AND NOT bWaveDetected AND iTotalDetectCount > 20 THEN
            rFlatFrac := INT_TO_REAL(iNearExtCount)        / INT_TO_REAL(iTotalDetectCount);
            rSymFrac  := INT_TO_REAL(iTargetAboveMidCount) / INT_TO_REAL(iTotalDetectCount);

            // 对称性检查优先：均值以上时间占比严重偏离0.5 → 任意波（如锯齿波）
            IF rSymFrac < 0.35 OR rSymFrac > 0.65 THEN
                nWaveType := 5;      // 任意波：波形不对称，无法用标准基底重建
            ELSIF rFlatFrac > FLAT_THR_TRAP THEN
                nWaveType := 4;      // 矩形波：峰谷附近>70%
            ELSIF rFlatFrac > FLAT_THR_SIN THEN
                nWaveType := 3;      // 梯形波：40~70%
            ELSIF rFlatFrac > FLAT_THR_TRI THEN
                nWaveType := 1;      // 正弦波：15~40%
            ELSE
                nWaveType := 2;      // 三角波：<15%
            END_IF
            bWaveDetected := TRUE;
        END_IF
        // 暖机期清空幅值累积数据
        rAmpFbPosSum     := 0.0;
        rAmpFbNegSum     := 0.0;
        nScaleCycleCount := 0;

    ELSIF NOT bConverged THEN
        IF iMaxIterations > 0 AND iIterCount >= iMaxIterations THEN
            bConverged := TRUE;
        ELSE
            // ---- α 4象限自学习（仅正弦/三角波，nWaveType=1或2）----
            IF bAlphaEnable AND (nWaveType = 1 OR nWaveType = 2) THEN
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
                rAlphaSum := rAlpha1Cmd + rAlpha2Cmd + rAlpha3Cmd + rAlpha4Cmd;
                IF rAlphaSum > 0.001 THEN
                    rAlpha1Cmd := rAlpha1Cmd / rAlphaSum;
                    rAlpha2Cmd := rAlpha2Cmd / rAlphaSum;
                    rAlpha3Cmd := rAlpha3Cmd / rAlphaSum;
                    rAlpha4Cmd := rAlpha4Cmd / rAlphaSum;
                END_IF
            END_IF

            // ---- 幅值自学习（所有波形类型均有效）----
            rAmpFbPosSum     := rAmpFbPosSum + rAmpFbPos;
            rAmpFbNegSum     := rAmpFbNegSum + rAmpFbNeg;
            nScaleCycleCount := nScaleCycleCount + 1;
            IF nScaleCycleCount >= CYCLES_PER_UPDATE THEN
                rAmpFbPos := rAmpFbPosSum / INT_TO_REAL(nScaleCycleCount);
                rAmpFbNeg := rAmpFbNegSum / INT_TO_REAL(nScaleCycleCount);
                // 上半：饱和判定细分指令是否已过冲（rScalePos > 1）
                //   - 饱和 + 过冲：指令超过目标导致削顶 → 缩小 rScalePos
                //   - 饱和 + 未过冲：系统物理触顶 → 保持不变（再缩小只让反馈更够不到目标）
                //   - 无饱和：按幅值比律学习
                IF rAmpFbPos > 0.001 THEN
                    IF rTopSatRatio > SAT_TOL THEN
                        IF rScalePos > 1.0 THEN
                            rScalePos := rScalePos * (1.0 - rLearningRate * rTopSatRatio);
                        END_IF
                    ELSE
                        rScalePos := rScalePos * (1.0 + rLearningRate * (rHalfRange / rAmpFbPos - 1.0));
                    END_IF
                END_IF
                // 下半：同理（rScaleNeg > 1 表示指令已贴到目标底之下）
                IF rAmpFbNeg > 0.001 THEN
                    IF rBotSatRatio > SAT_TOL THEN
                        IF rScaleNeg > 1.0 THEN
                            rScaleNeg := rScaleNeg * (1.0 - rLearningRate * rBotSatRatio);
                        END_IF
                    ELSE
                        rScaleNeg := rScaleNeg * (1.0 + rLearningRate * (rHalfRange / rAmpFbNeg - 1.0));
                    END_IF
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

IF rTargetRaw > rTargetMax THEN rTargetMax := rTargetRaw; END_IF
IF rTargetRaw < rTargetMin THEN rTargetMin := rTargetRaw; END_IF
IF rActual > rActualMax THEN rActualMax := rActual; END_IF
IF rActual < rActualMin THEN rActualMin := rActual; END_IF

rErrorSum2  := rErrorSum2 + (rTargetRaw - rActual) * (rTargetRaw - rActual);
iErrorCount := iErrorCount + 1;

// ---- 波形类型检测：统计指令在峰谷附近(|target-mid| > 90%×halfRange)的时间占比 ----
// 从 iIterCount>=1 开始（此时 rMidpoint/rHalfRange 已由第一个周期数据初始化）
IF NOT bWaveDetected AND iIterCount >= 1 AND rHalfRange > 0.001 THEN
    iTotalDetectCount := iTotalDetectCount + 1;
    IF ABS(rTargetRaw - rMidpoint) > 0.9 * rHalfRange THEN
        iNearExtCount := iNearExtCount + 1;
    END_IF
    IF rTargetRaw >= rMidpoint THEN
        iTargetAboveMidCount := iTargetAboveMidCount + 1;
    END_IF
END_IF

// ---- 饱和检测计数：目标用 rHalfRange、反馈用 rAmpFbPos/Neg 作为各自基准 ----
// 占比对比是波形无关的：任意波形稳态时两者应相等，反馈停留时间显著更长即饱和
IF iIterCount >= 1 AND rHalfRange > 0.001 THEN
    IF (rTargetRaw - rMidpoint) > 0.9 * rHalfRange THEN
        iTargetNearTop := iTargetNearTop + 1;
    END_IF
    IF (rMidpoint - rTargetRaw) > 0.9 * rHalfRange THEN
        iTargetNearBot := iTargetNearBot + 1;
    END_IF
END_IF
IF rAmpFbPos > 0.001 AND (rActual - rMidpoint) > 0.9 * rAmpFbPos THEN
    iActualNearTop := iActualNearTop + 1;
END_IF
IF rAmpFbNeg > 0.001 AND (rMidpoint - rActual) > 0.9 * rAmpFbNeg THEN
    iActualNearBot := iActualNearBot + 1;
END_IF

// 4象限反馈采样
IF rActual >= rActualPrev THEN
    bFbRising := TRUE;
ELSE
    bFbRising := FALSE;
END_IF
rActualPrev := rActual;

IF bFbRising THEN
    IF rActual < rMidpoint THEN
        iQ1Count := iQ1Count + 1;
    ELSE
        iQ2Count := iQ2Count + 1;
    END_IF
ELSE
    IF rActual >= rMidpoint THEN
        iQ3Count := iQ3Count + 1;
    ELSE
        iQ4Count := iQ4Count + 1;
    END_IF
END_IF

// ============================================================
// 输出生成
// ============================================================

// 暖机期直接透传
IF iIterCount <= nWarmupCycles THEN
    rVirtualTarget := rTargetRaw;
    rOutput        := 0.0;
    bNewCyclePrev  := bNewCycle;
    RETURN;
END_IF

// 梯形波 / 矩形波 / 任意波（nWaveType=3,4,5）：跳过相位畸变，直接对 rTargetRaw 幅值缩放
IF nWaveType = 3 OR nWaveType = 4 OR nWaveType = 5 THEN
    IF rTargetRaw >= rMidpoint THEN
        rVirtualTarget := rMidpoint + (rTargetRaw - rMidpoint) * rScalePos;
    ELSE
        rVirtualTarget := rMidpoint - (rMidpoint - rTargetRaw) * rScaleNeg;
    END_IF
    rOutput       := rVirtualTarget - rTargetRaw;
    bNewCyclePrev := bNewCycle;
    RETURN;
END_IF

// 正弦波(1) / 三角波(2)：4段线性相位畸变 + 幅值缩放
IF iPointsPerCycle > 0 THEN
    rPhi := INT_TO_REAL(iPointIndex) / INT_TO_REAL(iPointsPerCycle);
ELSE
    rPhi := 0.0;
END_IF
IF rPhi < 0.0 THEN rPhi := 0.0; END_IF
IF rPhi > 1.0 THEN rPhi := 1.0; END_IF

// 4段线性相位畸变
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

// 基底波形：正弦=余弦形，三角=线性斜坡
IF nWaveType = 2 THEN
    // 三角波基底
    IF rPhiStd < 0.5 THEN
        rWarpedY := 2.0 * rPhiStd;
    ELSE
        rWarpedY := 2.0 * (1.0 - rPhiStd);
    END_IF
ELSE
    // 正弦波基底（默认）
    rWarpedY := (1.0 - COS(TWO_PI * rPhiStd)) / 2.0;
END_IF

IF rPrevTargetRange > 0.001 THEN
    rWarpedTarget := rPrevTargetMin + rWarpedY * rPrevTargetRange;
ELSE
    rWarpedTarget := rTargetRaw;
END_IF

IF rWarpedTarget >= rMidpoint THEN
    rVirtualTarget := rMidpoint + (rWarpedTarget - rMidpoint) * rScalePos;
ELSE
    rVirtualTarget := rMidpoint - (rMidpoint - rWarpedTarget) * rScaleNeg;
END_IF

rOutput := rVirtualTarget - rTargetRaw;

bNewCyclePrev := bNewCycle;
END_FUNCTION_BLOCK
