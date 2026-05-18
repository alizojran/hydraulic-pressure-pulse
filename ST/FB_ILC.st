FUNCTION_BLOCK FB_ILC
VAR_INPUT
	bEnable         : BOOL;
	rTargetRaw      : REAL;          // 原始目标值 (MPa)
	rActual         : REAL;          // 当前反馈值 (MPa)
	iPointIndex     : INT;           // 周期内采样点序号 (0 ~ iPointsPerCycle-1)
	iPointsPerCycle : INT;
	bNewCycle       : BOOL;
	bReset          : BOOL;
	iMaxIterations  : INT;
	rLearningRate   : REAL := 0.3;   // 端点学习率（仅非三角波）/ 三角波 vTop/vBottom 也共用
	rAlphaLR        : REAL := 0.2;   // α 学习率（仅正弦 nWaveType=1）
	bAlphaEnable    : BOOL := TRUE;  // α 自学习使能（仅对正弦生效）
	// 三角波 4 状态补偿参数
	rTriWidthLR     : REAL := 0.5;   // 平台宽度学习率（信号"平台首尾差 - 容差"量纲在 MPa，需要较大 LR）
	rTriKickLR      : REAL := 0.1;   // kick 振幅学习率
	rTriKickFrac    : REAL := 0.10;  // kick 占斜坡末端的相位比例
	nWarmupCycles   : INT  := 3;     // 暖机周期数：前N个周期透传不修正，同时完成波形类型检测
END_VAR
VAR_OUTPUT
	rOutput        : REAL;           // 修正量 = rVirtualTarget - rTargetRaw (MPa)
	rVirtualTarget : REAL;           // 预畸变指令实时值 (MPa)
	iIteration     : INT;
	rRmsError      : REAL;
	bConverged     : BOOL;
	rPeakError     : REAL;
	rValleyError   : REAL;
	// 非三角波端点学习量
	rVMax          : REAL;
	rVMin          : REAL;
	rScalePos      : REAL := 1.0;
	rScaleNeg      : REAL := 1.0;
	// 正弦 8 段 α 时长占比
	rAlphaCmd      : ARRAY [1..8] OF REAL;
	rAlphaTgt      : ARRAY [1..8] OF REAL;
	rAlphaFb       : ARRAY [1..8] OF REAL;
	// 三角波 4 状态补偿量
	rVBottom       : REAL;           // 学到的底部平台 cmd 值
	rVTop          : REAL;           // 学到的顶部平台 cmd 值
	rW_bot         : REAL;           // 学到的底部平台宽度（周期占比）
	rW_top         : REAL;           // 学到的顶部平台宽度
	rKickBotAmp    : REAL;           // 下降斜坡末端 kick 振幅（负）
	rKickTopAmp    : REAL;           // 上升斜坡末端 kick 振幅（正）
	rValleyPhase   : REAL;           // 检测到的谷相位（0~1）
	rPeakPhase     : REAL;           // 检测到的峰相位
	rFbMinInBotWin : REAL;           // 底部窗口内反馈最小值（诊断）
	rFbMaxInTopWin : REAL;           // 顶部窗口内反馈最大值（诊断）
	// 波形检测
	nWaveType      : INT  := 0;      // 0=检测中, 1=正弦, 2=三角, 3=梯形, 4=矩形, 5=任意波
	rFlatFrac      : REAL;
	rSymFrac       : REAL;
END_VAR
VAR
	rMidpoint        : REAL;
	rHalfRange       : REAL;
	rQuarter         : REAL;
	rTargetMax       : REAL;
	rTargetMin       : REAL;
	rActualMax       : REAL;
	rActualMin       : REAL;
	rPrevTargetMax   : REAL;
	rPrevTargetMin   : REAL;
	rPrevTargetRange : REAL;
	bNewCyclePrev    : BOOL;
	iIterCount       : INT;
	bVInitialized    : BOOL;         // 非三角波 vMax/vMin 已初始化
	bTri4StateInit   : BOOL;         // 三角波 4 状态参数已初始化
	nUpdateCount     : INT;
	rPeakErrSum      : REAL;
	rValleyErrSum    : REAL;
	rErrorSum2       : REAL;
	iErrorCount      : INT;
	// 8 段 α 状态（正弦用）
	iTgtBin          : ARRAY [1..8] OF INT;
	iFbBin           : ARRAY [1..8] OF INT;
	iBinTotal        : INT;
	rTargetPrev      : REAL;
	bTgtRising       : BOOL;
	rActualPrev      : REAL;
	bFbRising        : BOOL;
	rTgtPos          : REAL;
	rFbPos           : REAL;
	iBinK            : INT;
	rAlphaSum        : REAL;
	rT1              : REAL;
	rT2              : REAL;
	rT3              : REAL;
	rT4              : REAL;
	rT5              : REAL;
	rT6              : REAL;
	rT7              : REAL;
	rDelta           : REAL;
	rPhi             : REAL;
	rPhiStd          : REAL;
	rWarpedY         : REAL;
	rSourceTarget    : REAL;
	rNorm            : REAL;
	rLimit           : REAL;
	rBinTotal        : REAL;
	// 4 状态用临时量
	iPeakIdxThisCycle   : INT;
	iValleyIdxThisCycle : INT;
	rRiseTotal       : REAL;         // 从谷到峰的相位长度（不含窗口）
	rBotHalf         : REAL;
	rTopHalf         : REAL;
	rPhiV            : REAL;         // 谷相对相位 = (rPhi - rValleyPhase + 1) mod 1
	iCurrentState    : INT;          // 0=底部 1=上升 2=顶部 3=下降
	iPrevState       : INT;
	rFbAtBotEntry    : REAL;
	rFbAtBotExit     : REAL;
	rFbAtTopEntry    : REAL;
	rFbAtTopExit     : REAL;
	rDeltaTop        : REAL;
	rDeltaBot        : REAL;
	rWidthTolerance  : REAL;
	rRampStart       : REAL;
	rRampEnd         : REAL;
	rRampDur         : REAL;
	rRampProgress    : REAL;
	rKickLocalPhi    : REAL;
	rKickShape       : REAL;
	rKickAmpLimit    : REAL;
	// 波形检测
	iNearExtCount       : INT;
	iTargetAboveMidCount: INT;
	iTotalDetectCount   : INT;
	bWaveDetected       : BOOL;
END_VAR
VAR CONSTANT
	ALPHA_Q_MIN       : REAL := 0.05;
	ALPHA_Q_MAX       : REAL := 0.25;
	TWO_PI            : REAL := 6.283185307;
	CYCLES_PER_UPDATE : INT  := 2;
	FLAT_THR_TRI      : REAL := 0.15;
	FLAT_THR_SIN      : REAL := 0.40;
	FLAT_THR_TRAP     : REAL := 0.70;
	V_RANGE_LIMIT_K   : REAL := 2.0;
	// 三角波 4 状态边界
	WIDTH_MIN         : REAL := 0.02;   // 平台最小 2% 周期
	WIDTH_MAX         : REAL := 0.30;   // 平台最大 30% 周期
	KICK_AMP_LIMIT_K  : REAL := 0.3;    // kick 振幅最大 0.3 * halfRange
	WIDTH_DELTA_REL   : REAL := 0.02;   // 平台首尾差容差 = 2% * halfRange
END_VAR


// ============================================================
// 复位 / 禁用
// ============================================================
IF bReset OR NOT bEnable THEN
    IF bReset THEN
        iIterCount        := 0;
        nUpdateCount      := 0;
        rPeakErrSum       := 0.0;
        rValleyErrSum     := 0.0;
        rRmsError         := 0.0;
        bConverged        := FALSE;
        rMidpoint         := 0.0;
        rHalfRange        := 0.0;
        rQuarter          := 0.0;
        rPrevTargetMax    := 0.0;
        rPrevTargetMin    := 0.0;
        rPrevTargetRange  := 0.0;
        rVMax             := 0.0;
        rVMin             := 0.0;
        rScalePos         := 1.0;
        rScaleNeg         := 1.0;
        bVInitialized     := FALSE;
        bTri4StateInit    := FALSE;
        rActualPrev       := 0.0;
        rTargetPrev       := 0.0;
        nWaveType              := 0;
        rFlatFrac              := 0.0;
        rSymFrac               := 0.0;
        iNearExtCount          := 0;
        iTargetAboveMidCount   := 0;
        iTotalDetectCount      := 0;
        bWaveDetected          := FALSE;
        // 8 段 α 默认均分
        FOR iBinK := 1 TO 8 DO
            rAlphaCmd[iBinK] := 0.125;
            rAlphaTgt[iBinK] := 0.125;
            rAlphaFb[iBinK]  := 0.125;
        END_FOR
        // 4 状态参数复位（暖机后由首次检测到的波形端点初始化）
        rVBottom          := 0.0;
        rVTop             := 0.0;
        rW_bot            := 0.08;
        rW_top            := 0.08;
        rKickBotAmp       := 0.0;
        rKickTopAmp       := 0.0;
        rValleyPhase      := 0.0;
        rPeakPhase        := 0.5;
        rFbMinInBotWin    := 0.0;
        rFbMaxInTopWin    := 0.0;
        rFbAtBotEntry     := 0.0;
        rFbAtBotExit      := 0.0;
        rFbAtTopEntry     := 0.0;
        rFbAtTopExit      := 0.0;
        iCurrentState     := 0;
        iPrevState        := 0;
        iPeakIdxThisCycle   := 0;
        iValleyIdxThisCycle := 0;
        rRiseTotal        := 0.5;
    END_IF
    rOutput        := 0.0;
    rVirtualTarget := 0.0;
    rTargetMax     := -1.0E30;
    rTargetMin     :=  1.0E30;
    rActualMax     := -1.0E30;
    rActualMin     :=  1.0E30;
    rErrorSum2     := 0.0;
    iErrorCount    := 0;
    iBinTotal      := 0;
    FOR iBinK := 1 TO 8 DO
        iTgtBin[iBinK] := 0;
        iFbBin[iBinK]  := 0;
    END_FOR
    // 4 状态周期内统计复位
    rFbMinInBotWin :=  1.0E30;
    rFbMaxInTopWin := -1.0E30;
    iPeakIdxThisCycle   := 0;
    iValleyIdxThisCycle := 0;
    iPrevState     := -1;       // -1 表示尚未确定，下个采样首次进入哪个状态都算"刚进入"
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

    // 8 段分布归一（仅正弦真正使用，三角/其他波形也算上但不参与学习）
    IF iBinTotal > 0 THEN
        rBinTotal := INT_TO_REAL(iBinTotal);
        FOR iBinK := 1 TO 8 DO
            rAlphaTgt[iBinK] := INT_TO_REAL(iTgtBin[iBinK]) / rBinTotal;
            rAlphaFb[iBinK]  := INT_TO_REAL(iFbBin[iBinK])  / rBinTotal;
        END_FOR
    END_IF
    FOR iBinK := 1 TO 8 DO
        iTgtBin[iBinK] := 0;
        iFbBin[iBinK]  := 0;
    END_FOR
    iBinTotal := 0;

    // 端点误差
    rPeakError   := rTargetMax - rActualMax;
    rValleyError := rTargetMin - rActualMin;

    // rMidpoint / rHalfRange
    rMidpoint  := (rTargetMax + rTargetMin) / 2.0;
    rHalfRange := (rTargetMax - rTargetMin) / 2.0;
    IF rHalfRange < 0.001 THEN rHalfRange := 0.001; END_IF
    rQuarter   := 0.5 * rHalfRange;

    rPrevTargetMax   := rTargetMax;
    rPrevTargetMin   := rTargetMin;
    rPrevTargetRange := rTargetMax - rTargetMin;

    // 三角波 4 状态：本周期检测到的峰/谷相位
    IF iPointsPerCycle > 0 THEN
        rValleyPhase := INT_TO_REAL(iValleyIdxThisCycle) / INT_TO_REAL(iPointsPerCycle);
        rPeakPhase   := INT_TO_REAL(iPeakIdxThisCycle)   / INT_TO_REAL(iPointsPerCycle);
    END_IF
    rRiseTotal := rPeakPhase - rValleyPhase;
    IF rRiseTotal < 0.0 THEN rRiseTotal := rRiseTotal + 1.0; END_IF

    rTargetMax := -1.0E30; rTargetMin :=  1.0E30;
    rActualMax := -1.0E30; rActualMin :=  1.0E30;

    iIterCount := iIterCount + 1;
    iIteration := iIterCount;

    IF iIterCount <= nWarmupCycles THEN
        // 暖机末完成波形类型检测
        IF iIterCount = nWarmupCycles AND NOT bWaveDetected AND iTotalDetectCount > 20 THEN
            rFlatFrac := INT_TO_REAL(iNearExtCount)        / INT_TO_REAL(iTotalDetectCount);
            rSymFrac  := INT_TO_REAL(iTargetAboveMidCount) / INT_TO_REAL(iTotalDetectCount);
            IF rSymFrac < 0.35 OR rSymFrac > 0.65 THEN
                nWaveType := 5;
            ELSIF rFlatFrac > FLAT_THR_TRAP THEN
                nWaveType := 4;
            ELSIF rFlatFrac > FLAT_THR_SIN THEN
                nWaveType := 3;
            ELSIF rFlatFrac > FLAT_THR_TRI THEN
                nWaveType := 1;
            ELSE
                nWaveType := 2;
            END_IF
            bWaveDetected := TRUE;
        END_IF
        nUpdateCount  := 0;
        rPeakErrSum   := 0.0;
        rValleyErrSum := 0.0;

    ELSIF NOT bConverged THEN

        // ============ 三角波 (nWaveType = 2)：4 状态学习 ============
        IF nWaveType = 2 THEN

            // 首次进入：用上一周期端点初始化 vTop / vBottom
            IF NOT bTri4StateInit THEN
                rVTop       := rPrevTargetMax;
                rVBottom    := rPrevTargetMin;
                rW_top      := 0.08;
                rW_bot      := 0.08;
                rKickTopAmp := 0.0;
                rKickBotAmp := 0.0;
                bTri4StateInit := TRUE;
            END_IF

            IF iMaxIterations > 0 AND iIterCount >= iMaxIterations THEN
                bConverged := TRUE;
            ELSE
                // --- 平台 cmd 值学习：用平台窗口内反馈极值作判据 ---
                // vTop 上调当反馈顶平台没冲到目标峰；下调当反馈过冲超过目标峰
                IF rFbMaxInTopWin > -1.0E29 THEN
                    rVTop := rVTop + rLearningRate * (rPrevTargetMax - rFbMaxInTopWin);
                END_IF
                IF rFbMinInBotWin <  1.0E29 THEN
                    rVBottom := rVBottom + rLearningRate * (rPrevTargetMin - rFbMinInBotWin);
                END_IF
                // 限幅：|v - target_endpoint| ≤ K * range
                IF rPrevTargetRange > 0.001 THEN
                    rLimit := V_RANGE_LIMIT_K * rPrevTargetRange;
                    IF rVTop    > rPrevTargetMax + rLimit THEN rVTop    := rPrevTargetMax + rLimit; END_IF
                    IF rVTop    < rPrevTargetMax - rLimit THEN rVTop    := rPrevTargetMax - rLimit; END_IF
                    IF rVBottom > rPrevTargetMin + rLimit THEN rVBottom := rPrevTargetMin + rLimit; END_IF
                    IF rVBottom < rPrevTargetMin - rLimit THEN rVBottom := rPrevTargetMin - rLimit; END_IF
                END_IF
                IF rVTop <= rVBottom + 0.001 THEN
                    rVTop := rVBottom + 0.001;
                END_IF

                // --- 平台宽度学习：平台首尾反馈差 > 容差 → 加宽；小于容差 → 缩窄 ---
                rDeltaTop       := ABS(rFbAtTopExit - rFbAtTopEntry);
                rDeltaBot       := ABS(rFbAtBotExit - rFbAtBotEntry);
                rWidthTolerance := WIDTH_DELTA_REL * rHalfRange;
                rW_top := rW_top + rTriWidthLR * (rDeltaTop - rWidthTolerance);
                rW_bot := rW_bot + rTriWidthLR * (rDeltaBot - rWidthTolerance);
                IF rW_top < WIDTH_MIN THEN rW_top := WIDTH_MIN; END_IF
                IF rW_top > WIDTH_MAX THEN rW_top := WIDTH_MAX; END_IF
                IF rW_bot < WIDTH_MIN THEN rW_bot := WIDTH_MIN; END_IF
                IF rW_bot > WIDTH_MAX THEN rW_bot := WIDTH_MAX; END_IF

                // --- kick 学习：反馈进入平台窗口那一瞬还差多少 ---
                // err = target_endpoint - fb_at_entry
                // 上升斜坡末端 kick：err 正 = 反馈还没冲到 vTop → 加大正 kick
                // 下降斜坡末端 kick：err 负 = 反馈还没到达 vBottom → 加大负 kick
                rKickTopAmp   := rKickTopAmp   + rTriKickLR * (rPrevTargetMax - rFbAtTopEntry);
                rKickBotAmp   := rKickBotAmp   + rTriKickLR * (rPrevTargetMin - rFbAtBotEntry);
                rKickAmpLimit := KICK_AMP_LIMIT_K * rHalfRange;
                IF rKickTopAmp >  rKickAmpLimit THEN rKickTopAmp :=  rKickAmpLimit; END_IF
                IF rKickTopAmp < -rKickAmpLimit THEN rKickTopAmp := -rKickAmpLimit; END_IF
                IF rKickBotAmp >  rKickAmpLimit THEN rKickBotAmp :=  rKickAmpLimit; END_IF
                IF rKickBotAmp < -rKickAmpLimit THEN rKickBotAmp := -rKickAmpLimit; END_IF
            END_IF

        // ============ 非三角波：α (仅正弦) + 端点学习 ============
        ELSE
            IF NOT bVInitialized THEN
                rVMax := rPrevTargetMax;
                rVMin := rPrevTargetMin;
                bVInitialized := TRUE;
            END_IF

            IF iMaxIterations > 0 AND iIterCount >= iMaxIterations THEN
                bConverged := TRUE;
            ELSE
                // α 8 段自学习（仅正弦 nWaveType=1）
                IF bAlphaEnable AND nWaveType = 1 THEN
                    FOR iBinK := 1 TO 8 DO
                        rAlphaCmd[iBinK] := rAlphaCmd[iBinK]
                                         + rAlphaLR * (rAlphaTgt[iBinK] - rAlphaFb[iBinK]);
                        IF rAlphaCmd[iBinK] < ALPHA_Q_MIN THEN rAlphaCmd[iBinK] := ALPHA_Q_MIN; END_IF
                        IF rAlphaCmd[iBinK] > ALPHA_Q_MAX THEN rAlphaCmd[iBinK] := ALPHA_Q_MAX; END_IF
                    END_FOR
                    rAlphaSum := 0.0;
                    FOR iBinK := 1 TO 8 DO
                        rAlphaSum := rAlphaSum + rAlphaCmd[iBinK];
                    END_FOR
                    IF rAlphaSum > 0.001 THEN
                        FOR iBinK := 1 TO 8 DO
                            rAlphaCmd[iBinK] := rAlphaCmd[iBinK] / rAlphaSum;
                        END_FOR
                    END_IF
                END_IF

                // 端点幅值自学习（加法型，正弦/梯形/矩形/任意波通用）
                rPeakErrSum   := rPeakErrSum   + rPeakError;
                rValleyErrSum := rValleyErrSum + rValleyError;
                nUpdateCount  := nUpdateCount  + 1;
                IF nUpdateCount >= CYCLES_PER_UPDATE THEN
                    rVMax := rVMax + rLearningRate * (rPeakErrSum   / INT_TO_REAL(nUpdateCount));
                    rVMin := rVMin + rLearningRate * (rValleyErrSum / INT_TO_REAL(nUpdateCount));
                    IF rPrevTargetRange > 0.001 THEN
                        rLimit := V_RANGE_LIMIT_K * rPrevTargetRange;
                        IF rVMax > rPrevTargetMax + rLimit THEN rVMax := rPrevTargetMax + rLimit; END_IF
                        IF rVMax < rPrevTargetMax - rLimit THEN rVMax := rPrevTargetMax - rLimit; END_IF
                        IF rVMin > rPrevTargetMin + rLimit THEN rVMin := rPrevTargetMin + rLimit; END_IF
                        IF rVMin < rPrevTargetMin - rLimit THEN rVMin := rPrevTargetMin - rLimit; END_IF
                    END_IF
                    IF rVMax <= rVMin + 0.001 THEN
                        rVMax := rVMin + 0.001;
                    END_IF
                    rPeakErrSum   := 0.0;
                    rValleyErrSum := 0.0;
                    nUpdateCount  := 0;
                END_IF
            END_IF
        END_IF
    END_IF

    // 诊断派生量 rScalePos / rScaleNeg
    IF rHalfRange > 0.001 THEN
        IF nWaveType = 2 AND bTri4StateInit THEN
            rScalePos := (rVTop    - rMidpoint) / rHalfRange;
            rScaleNeg := (rMidpoint - rVBottom) / rHalfRange;
        ELSIF bVInitialized THEN
            rScalePos := (rVMax - rMidpoint) / rHalfRange;
            rScaleNeg := (rMidpoint - rVMin) / rHalfRange;
        END_IF
    END_IF

    // 复位 4 状态周期内统计
    rFbMinInBotWin :=  1.0E30;
    rFbMaxInTopWin := -1.0E30;
    iPeakIdxThisCycle   := 0;
    iValleyIdxThisCycle := 0;
    iPrevState     := -1;

END_IF

// ============================================================
// 每个采样点
// ============================================================

// 周期相位
IF iPointsPerCycle > 0 THEN
    rPhi := INT_TO_REAL(iPointIndex) / INT_TO_REAL(iPointsPerCycle);
ELSE
    rPhi := 0.0;
END_IF
IF rPhi < 0.0 THEN rPhi := 0.0; END_IF
IF rPhi > 1.0 THEN rPhi := 1.0; END_IF

// 目标 / 反馈极值跟踪 + 三角波用 argmax/argmin 索引
IF rTargetRaw > rTargetMax THEN
    rTargetMax := rTargetRaw;
    iPeakIdxThisCycle := iPointIndex;
END_IF
IF rTargetRaw < rTargetMin THEN
    rTargetMin := rTargetRaw;
    iValleyIdxThisCycle := iPointIndex;
END_IF
IF rActual > rActualMax THEN rActualMax := rActual; END_IF
IF rActual < rActualMin THEN rActualMin := rActual; END_IF

rErrorSum2  := rErrorSum2 + (rTargetRaw - rActual) * (rTargetRaw - rActual);
iErrorCount := iErrorCount + 1;

// 波形类型检测
IF NOT bWaveDetected AND iIterCount >= 1 AND rHalfRange > 0.001 THEN
    iTotalDetectCount := iTotalDetectCount + 1;
    IF ABS(rTargetRaw - rMidpoint) > 0.9 * rHalfRange THEN
        iNearExtCount := iNearExtCount + 1;
    END_IF
    IF rTargetRaw >= rMidpoint THEN
        iTargetAboveMidCount := iTargetAboveMidCount + 1;
    END_IF
END_IF

// 方向检测
IF rTargetRaw >= rTargetPrev THEN bTgtRising := TRUE; ELSE bTgtRising := FALSE; END_IF
rTargetPrev := rTargetRaw;
IF rActual   >= rActualPrev THEN bFbRising  := TRUE; ELSE bFbRising  := FALSE; END_IF
rActualPrev := rActual;

// --------- 8 段分箱（仅正弦用）---------
IF nWaveType = 1 AND iIterCount >= 1 AND rHalfRange > 0.001 THEN
    iBinTotal := iBinTotal + 1;
    rTgtPos := rTargetRaw - rMidpoint;
    IF bTgtRising THEN
        IF      rTgtPos < -rQuarter THEN iBinK := 1;
        ELSIF   rTgtPos <  0.0      THEN iBinK := 2;
        ELSIF   rTgtPos <  rQuarter THEN iBinK := 3;
        ELSE                              iBinK := 4;
        END_IF
    ELSE
        IF      rTgtPos >  rQuarter THEN iBinK := 5;
        ELSIF   rTgtPos >  0.0      THEN iBinK := 6;
        ELSIF   rTgtPos > -rQuarter THEN iBinK := 7;
        ELSE                              iBinK := 8;
        END_IF
    END_IF
    iTgtBin[iBinK] := iTgtBin[iBinK] + 1;

    rFbPos := rActual - rMidpoint;
    IF bFbRising THEN
        IF      rFbPos < -rQuarter THEN iBinK := 1;
        ELSIF   rFbPos <  0.0      THEN iBinK := 2;
        ELSIF   rFbPos <  rQuarter THEN iBinK := 3;
        ELSE                             iBinK := 4;
        END_IF
    ELSE
        IF      rFbPos >  rQuarter THEN iBinK := 5;
        ELSIF   rFbPos >  0.0      THEN iBinK := 6;
        ELSIF   rFbPos > -rQuarter THEN iBinK := 7;
        ELSE                             iBinK := 8;
        END_IF
    END_IF
    iFbBin[iBinK] := iFbBin[iBinK] + 1;
END_IF

// --------- 三角波 4 状态：每采样点状态判定 + 窗口内统计 ---------
IF nWaveType = 2 AND iIterCount >= 1 AND rHalfRange > 0.001 THEN
    // 谷相对相位
    rPhiV := rPhi - rValleyPhase;
    IF rPhiV < 0.0 THEN rPhiV := rPhiV + 1.0; END_IF
    IF rPhiV >= 1.0 THEN rPhiV := rPhiV - 1.0; END_IF

    rBotHalf := rW_bot * 0.5;
    rTopHalf := rW_top * 0.5;

    // 状态判定
    IF rPhiV < rBotHalf OR rPhiV > (1.0 - rBotHalf) THEN
        iCurrentState := 0;     // 底部
    ELSIF rPhiV < (rRiseTotal - rTopHalf) THEN
        iCurrentState := 1;     // 上升
    ELSIF rPhiV < (rRiseTotal + rTopHalf) THEN
        iCurrentState := 2;     // 顶部
    ELSE
        iCurrentState := 3;     // 下降
    END_IF

    // 进入底部窗口的首样本：捕获 fbAtBotEntry
    IF iCurrentState = 0 AND iPrevState <> 0 THEN
        rFbAtBotEntry := rActual;
    END_IF
    // 进入顶部窗口的首样本
    IF iCurrentState = 2 AND iPrevState <> 2 THEN
        rFbAtTopEntry := rActual;
    END_IF
    // 底部窗口内：跟踪 min 与最后值（用作 exit）
    IF iCurrentState = 0 THEN
        IF rActual < rFbMinInBotWin THEN rFbMinInBotWin := rActual; END_IF
        rFbAtBotExit := rActual;
    END_IF
    // 顶部窗口内：跟踪 max 与最后值
    IF iCurrentState = 2 THEN
        IF rActual > rFbMaxInTopWin THEN rFbMaxInTopWin := rActual; END_IF
        rFbAtTopExit := rActual;
    END_IF

    iPrevState := iCurrentState;
END_IF

// ============================================================
// 输出生成
// ============================================================

// 暖机期 / 首次学习窗未到 / 目标无幅值：直通
IF iIterCount <= nWarmupCycles OR rPrevTargetRange < 0.001 THEN
    rVirtualTarget := rTargetRaw;
    rOutput        := 0.0;
    bNewCyclePrev  := bNewCycle;
    RETURN;
END_IF

// =============== 三角波 (nWaveType=2)：4 状态 cmd 构造 ===============
IF nWaveType = 2 AND bTri4StateInit THEN
    // 计算谷相对相位 rPhiV（采样点段已计算过，这里重算以确保独立性）
    rPhiV := rPhi - rValleyPhase;
    IF rPhiV < 0.0 THEN rPhiV := rPhiV + 1.0; END_IF
    IF rPhiV >= 1.0 THEN rPhiV := rPhiV - 1.0; END_IF

    rBotHalf := rW_bot * 0.5;
    rTopHalf := rW_top * 0.5;

    IF rPhiV < rBotHalf OR rPhiV > (1.0 - rBotHalf) THEN
        // 底部平台
        rVirtualTarget := rVBottom;

    ELSIF rPhiV < (rRiseTotal - rTopHalf) THEN
        // 上升斜坡
        rRampStart := rBotHalf;
        rRampEnd   := rRiseTotal - rTopHalf;
        rRampDur   := rRampEnd - rRampStart;
        IF rRampDur > 0.001 THEN
            rRampProgress := (rPhiV - rRampStart) / rRampDur;
        ELSE
            rRampProgress := 0.5;
        END_IF
        rVirtualTarget := rVBottom + rRampProgress * (rVTop - rVBottom);
        // 斜坡末端 kick：Hann 脉冲，在末端 rTriKickFrac 段内
        IF rRampProgress > (1.0 - rTriKickFrac) THEN
            rKickLocalPhi := (rRampProgress - (1.0 - rTriKickFrac)) / rTriKickFrac;
            rKickShape    := 0.5 * (1.0 - COS(TWO_PI * rKickLocalPhi));
            rVirtualTarget := rVirtualTarget + rKickTopAmp * rKickShape;
        END_IF

    ELSIF rPhiV < (rRiseTotal + rTopHalf) THEN
        // 顶部平台
        rVirtualTarget := rVTop;

    ELSE
        // 下降斜坡
        rRampStart := rRiseTotal + rTopHalf;
        rRampEnd   := 1.0 - rBotHalf;
        rRampDur   := rRampEnd - rRampStart;
        IF rRampDur > 0.001 THEN
            rRampProgress := (rPhiV - rRampStart) / rRampDur;
        ELSE
            rRampProgress := 0.5;
        END_IF
        rVirtualTarget := rVTop - rRampProgress * (rVTop - rVBottom);
        IF rRampProgress > (1.0 - rTriKickFrac) THEN
            rKickLocalPhi := (rRampProgress - (1.0 - rTriKickFrac)) / rTriKickFrac;
            rKickShape    := 0.5 * (1.0 - COS(TWO_PI * rKickLocalPhi));
            rVirtualTarget := rVirtualTarget + rKickBotAmp * rKickShape;
        END_IF
    END_IF

    rOutput := rVirtualTarget - rTargetRaw;
    bNewCyclePrev := bNewCycle;
    RETURN;
END_IF

// =============== 非三角波：原 α + 仿射重映射路径 ===============
IF NOT bVInitialized THEN
    rVirtualTarget := rTargetRaw;
    rOutput        := 0.0;
    bNewCyclePrev  := bNewCycle;
    RETURN;
END_IF

// 源波形 rSourceTarget：正弦(1) 用 α 8 段重建；其他直通 rTargetRaw
IF nWaveType = 1 THEN
    rT1 := rAlphaCmd[1];
    rT2 := rT1 + rAlphaCmd[2];
    rT3 := rT2 + rAlphaCmd[3];
    rT4 := rT3 + rAlphaCmd[4];
    rT5 := rT4 + rAlphaCmd[5];
    rT6 := rT5 + rAlphaCmd[6];
    rT7 := rT6 + rAlphaCmd[7];

    IF rPhi < rT1 THEN
        IF rT1 > 0.001 THEN rPhiStd := rPhi / rT1 * 0.125; ELSE rPhiStd := 0.0; END_IF
    ELSIF rPhi < rT2 THEN
        rDelta := rT2 - rT1;
        IF rDelta > 0.001 THEN rPhiStd := 0.125 + (rPhi - rT1) / rDelta * 0.125; ELSE rPhiStd := 0.125; END_IF
    ELSIF rPhi < rT3 THEN
        rDelta := rT3 - rT2;
        IF rDelta > 0.001 THEN rPhiStd := 0.250 + (rPhi - rT2) / rDelta * 0.125; ELSE rPhiStd := 0.250; END_IF
    ELSIF rPhi < rT4 THEN
        rDelta := rT4 - rT3;
        IF rDelta > 0.001 THEN rPhiStd := 0.375 + (rPhi - rT3) / rDelta * 0.125; ELSE rPhiStd := 0.375; END_IF
    ELSIF rPhi < rT5 THEN
        rDelta := rT5 - rT4;
        IF rDelta > 0.001 THEN rPhiStd := 0.500 + (rPhi - rT4) / rDelta * 0.125; ELSE rPhiStd := 0.500; END_IF
    ELSIF rPhi < rT6 THEN
        rDelta := rT6 - rT5;
        IF rDelta > 0.001 THEN rPhiStd := 0.625 + (rPhi - rT5) / rDelta * 0.125; ELSE rPhiStd := 0.625; END_IF
    ELSIF rPhi < rT7 THEN
        rDelta := rT7 - rT6;
        IF rDelta > 0.001 THEN rPhiStd := 0.750 + (rPhi - rT6) / rDelta * 0.125; ELSE rPhiStd := 0.750; END_IF
    ELSE
        rDelta := 1.0 - rT7;
        IF rDelta > 0.001 THEN rPhiStd := 0.875 + (rPhi - rT7) / rDelta * 0.125; ELSE rPhiStd := 0.875; END_IF
    END_IF

    rWarpedY := (1.0 - COS(TWO_PI * rPhiStd)) / 2.0;
    rSourceTarget := rPrevTargetMin + rWarpedY * rPrevTargetRange;
ELSE
    rSourceTarget := rTargetRaw;
END_IF

// 仿射重映射 [tMin, tMax] → [vMin, vMax]
rNorm          := (rSourceTarget - rPrevTargetMin) / rPrevTargetRange;
rVirtualTarget := rVMin + rNorm * (rVMax - rVMin);

rOutput := rVirtualTarget - rTargetRaw;

bNewCyclePrev := bNewCycle;

END_FUNCTION_BLOCK
