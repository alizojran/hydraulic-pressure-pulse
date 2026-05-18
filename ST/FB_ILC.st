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
	rLearningRate   : REAL := 0.3;   // 端点学习率
	rAlphaLR        : REAL := 0.2;   // α 学习率（正弦/三角 8 段、梯形/矩形 6 段）
	bAlphaEnable    : BOOL := TRUE;  // α 自学习使能（正弦/三角/梯形/矩形）
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
	// 端点学习量
	rVMax          : REAL;
	rVMin          : REAL;
	rScalePos      : REAL := 1.0;
	rScaleNeg      : REAL := 1.0;
	// 8 段 α 时长占比（正弦 / 三角共用）
	rAlphaCmd      : ARRAY [1..8] OF REAL;
	rAlphaTgt      : ARRAY [1..8] OF REAL;
	rAlphaFb       : ARRAY [1..8] OF REAL;
	// 12 段 α 时长占比（梯形 / 矩形共用：底平 / 升 1..5 / 顶平 / 降 1..5）
	rAlpha12Cmd    : ARRAY [1..12] OF REAL;
	rAlpha12Tgt    : ARRAY [1..12] OF REAL;
	rAlpha12Fb     : ARRAY [1..12] OF REAL;
	// 梯形 / 矩形：平台分 2 段的幅值修正（MPa，叠加在 vMax/vMin 上）
	rPlatBotA      : REAL;       // 底部平台前半段修正
	rPlatBotB      : REAL;       // 底部平台后半段修正
	rPlatTopA      : REAL;       // 顶部平台前半段修正
	rPlatTopB      : REAL;       // 顶部平台后半段修正
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
	bVInitialized    : BOOL;         // vMax/vMin 已初始化
	nUpdateCount     : INT;
	rPeakErrSum      : REAL;
	rValleyErrSum    : REAL;
	rErrorSum2       : REAL;
	iErrorCount      : INT;
	// 8 段 α 状态
	iTgtBin          : ARRAY [1..8] OF INT;
	iFbBin           : ARRAY [1..8] OF INT;
	iBinTotal        : INT;
	// 12 段 α 状态
	iTgtBin12        : ARRAY [1..12] OF INT;
	iFbBin12         : ARRAY [1..12] OF INT;
	iBinTotal12      : INT;
	// 平台分 2 段反馈累加（基于 cmd phase 切割）
	rFbSumBotA       : REAL;
	rFbSumBotB       : REAL;
	rFbSumTopA       : REAL;
	rFbSumTopB       : REAL;
	iCntBotA         : INT;
	iCntBotB         : INT;
	iCntTopA         : INT;
	iCntTopB         : INT;
	// cmd 平台 phase 边界缓存（每周期更新）
	rT1Cached        : REAL;
	rT6Cached        : REAL;
	rT7Cached        : REAL;
	rBotMidPhase     : REAL;
	rTopMidPhase     : REAL;
	rFbAvg           : REAL;
	rPlatCorrLimit   : REAL;
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
	rT8              : REAL;
	rT9              : REAL;
	rT10             : REAL;
	rT11             : REAL;
	rBand1           : REAL;
	rBand2           : REAL;
	rBand3           : REAL;
	rBand4           : REAL;
	rPlateauThr      : REAL;
	rDelta           : REAL;
	rPhi             : REAL;
	rPhiStd          : REAL;
	rWarpedY         : REAL;
	rSourceTarget    : REAL;
	rNorm            : REAL;
	rLimit           : REAL;
	rBinTotal        : REAL;
	// 波形检测
	iNearExtCount       : INT;
	iTargetAboveMidCount: INT;
	iTotalDetectCount   : INT;
	bWaveDetected       : BOOL;
END_VAR
VAR CONSTANT
	ALPHA_Q_MIN       : REAL := 0.04;
	ALPHA_Q_MAX       : REAL := 0.35;
	ALPHA12_Q_MIN     : REAL := 0.02;
	ALPHA12_Q_MAX     : REAL := 0.45;
	PLATEAU_BAND_K    : REAL := 0.7;     // 平台判定带：|y - mid| > K * halfRange
	PLAT_CORR_LR      : REAL := 0.3;     // 平台幅值修正学习率
	PLAT_CORR_LIMIT_K : REAL := 0.3;     // 平台幅值修正上限：0.3 * halfRange
	TWO_PI            : REAL := 6.283185307;
	CYCLES_PER_UPDATE : INT  := 2;
	FLAT_THR_TRI      : REAL := 0.15;
	FLAT_THR_SIN      : REAL := 0.40;
	FLAT_THR_TRAP     : REAL := 0.70;
	V_RANGE_LIMIT_K   : REAL := 2.0;
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
        // 12 段 α 默认均分（1/12 ≈ 0.08333）
        FOR iBinK := 1 TO 12 DO
            rAlpha12Cmd[iBinK] := 0.08333;
            rAlpha12Tgt[iBinK] := 0.08333;
            rAlpha12Fb[iBinK]  := 0.08333;
        END_FOR
        // 平台幅值修正复位
        rPlatBotA := 0.0;
        rPlatBotB := 0.0;
        rPlatTopA := 0.0;
        rPlatTopB := 0.0;
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
    FOR iBinK := 1 TO 12 DO
        iTgtBin12[iBinK] := 0;
        iFbBin12[iBinK]  := 0;
    END_FOR
    iBinTotal12    := 0;
    rFbSumBotA := 0.0; rFbSumBotB := 0.0;
    rFbSumTopA := 0.0; rFbSumTopB := 0.0;
    iCntBotA := 0; iCntBotB := 0;
    iCntTopA := 0; iCntTopB := 0;
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

    // 8 段分布归一
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

    // 12 段分布归一
    IF iBinTotal12 > 0 THEN
        rBinTotal := INT_TO_REAL(iBinTotal12);
        FOR iBinK := 1 TO 12 DO
            rAlpha12Tgt[iBinK] := INT_TO_REAL(iTgtBin12[iBinK]) / rBinTotal;
            rAlpha12Fb[iBinK]  := INT_TO_REAL(iFbBin12[iBinK])  / rBinTotal;
        END_FOR
    END_IF
    FOR iBinK := 1 TO 12 DO
        iTgtBin12[iBinK] := 0;
        iFbBin12[iBinK]  := 0;
    END_FOR
    iBinTotal12 := 0;

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
        IF NOT bVInitialized THEN
            rVMax := rPrevTargetMax;
            rVMin := rPrevTargetMin;
            bVInitialized := TRUE;
        END_IF

        IF iMaxIterations > 0 AND iIterCount >= iMaxIterations THEN
            bConverged := TRUE;
        ELSE
            // α 8 段自学习（正弦 nWaveType=1 + 三角 nWaveType=2）
            IF bAlphaEnable AND (nWaveType = 1 OR nWaveType = 2) THEN
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

            // α 12 段自学习（梯形 nWaveType=3 + 矩形 nWaveType=4）
            IF bAlphaEnable AND (nWaveType = 3 OR nWaveType = 4) THEN
                FOR iBinK := 1 TO 12 DO
                    rAlpha12Cmd[iBinK] := rAlpha12Cmd[iBinK]
                                       + rAlphaLR * (rAlpha12Tgt[iBinK] - rAlpha12Fb[iBinK]);
                    IF rAlpha12Cmd[iBinK] < ALPHA12_Q_MIN THEN rAlpha12Cmd[iBinK] := ALPHA12_Q_MIN; END_IF
                    IF rAlpha12Cmd[iBinK] > ALPHA12_Q_MAX THEN rAlpha12Cmd[iBinK] := ALPHA12_Q_MAX; END_IF
                END_FOR
                rAlphaSum := 0.0;
                FOR iBinK := 1 TO 12 DO
                    rAlphaSum := rAlphaSum + rAlpha12Cmd[iBinK];
                END_FOR
                IF rAlphaSum > 0.001 THEN
                    FOR iBinK := 1 TO 12 DO
                        rAlpha12Cmd[iBinK] := rAlpha12Cmd[iBinK] / rAlphaSum;
                    END_FOR
                END_IF
            END_IF

            // 平台分 2 段幅值修正学习（梯形 + 矩形）
            IF nWaveType = 3 OR nWaveType = 4 THEN
                IF iCntBotA > 0 THEN
                    rFbAvg := rFbSumBotA / INT_TO_REAL(iCntBotA);
                    rPlatBotA := rPlatBotA + PLAT_CORR_LR * (rPrevTargetMin - rFbAvg);
                END_IF
                IF iCntBotB > 0 THEN
                    rFbAvg := rFbSumBotB / INT_TO_REAL(iCntBotB);
                    rPlatBotB := rPlatBotB + PLAT_CORR_LR * (rPrevTargetMin - rFbAvg);
                END_IF
                IF iCntTopA > 0 THEN
                    rFbAvg := rFbSumTopA / INT_TO_REAL(iCntTopA);
                    rPlatTopA := rPlatTopA + PLAT_CORR_LR * (rPrevTargetMax - rFbAvg);
                END_IF
                IF iCntTopB > 0 THEN
                    rFbAvg := rFbSumTopB / INT_TO_REAL(iCntTopB);
                    rPlatTopB := rPlatTopB + PLAT_CORR_LR * (rPrevTargetMax - rFbAvg);
                END_IF
                rPlatCorrLimit := PLAT_CORR_LIMIT_K * rHalfRange;
                IF rPlatBotA >  rPlatCorrLimit THEN rPlatBotA :=  rPlatCorrLimit; END_IF
                IF rPlatBotA < -rPlatCorrLimit THEN rPlatBotA := -rPlatCorrLimit; END_IF
                IF rPlatBotB >  rPlatCorrLimit THEN rPlatBotB :=  rPlatCorrLimit; END_IF
                IF rPlatBotB < -rPlatCorrLimit THEN rPlatBotB := -rPlatCorrLimit; END_IF
                IF rPlatTopA >  rPlatCorrLimit THEN rPlatTopA :=  rPlatCorrLimit; END_IF
                IF rPlatTopA < -rPlatCorrLimit THEN rPlatTopA := -rPlatCorrLimit; END_IF
                IF rPlatTopB >  rPlatCorrLimit THEN rPlatTopB :=  rPlatCorrLimit; END_IF
                IF rPlatTopB < -rPlatCorrLimit THEN rPlatTopB := -rPlatCorrLimit; END_IF
            END_IF

            // 端点幅值自学习（加法型，所有波形通用）
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

    // 诊断派生量 rScalePos / rScaleNeg
    IF rHalfRange > 0.001 AND bVInitialized THEN
        rScalePos := (rVMax - rMidpoint) / rHalfRange;
        rScaleNeg := (rMidpoint - rVMin) / rHalfRange;
    END_IF

    // 缓存梯形/矩形平台 phase 边界（per-sample 和 输出阶段共用）
    IF nWaveType = 3 OR nWaveType = 4 THEN
        rT1Cached    := rAlpha12Cmd[1];
        rT6Cached    := rT1Cached + rAlpha12Cmd[2] + rAlpha12Cmd[3]
                     + rAlpha12Cmd[4] + rAlpha12Cmd[5] + rAlpha12Cmd[6];
        rT7Cached    := rT6Cached + rAlpha12Cmd[7];
        rBotMidPhase := rT1Cached * 0.5;
        rTopMidPhase := (rT6Cached + rT7Cached) * 0.5;
    END_IF

    // 复位平台分段反馈累加
    rFbSumBotA := 0.0; rFbSumBotB := 0.0;
    rFbSumTopA := 0.0; rFbSumTopB := 0.0;
    iCntBotA := 0; iCntBotB := 0;
    iCntTopA := 0; iCntTopB := 0;

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

// 目标 / 反馈极值跟踪
IF rTargetRaw > rTargetMax THEN rTargetMax := rTargetRaw; END_IF
IF rTargetRaw < rTargetMin THEN rTargetMin := rTargetRaw; END_IF
IF rActual    > rActualMax THEN rActualMax := rActual;    END_IF
IF rActual    < rActualMin THEN rActualMin := rActual;    END_IF

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

// --------- 8 段分箱（正弦 + 三角共用）---------
IF (nWaveType = 1 OR nWaveType = 2) AND iIterCount >= 1 AND rHalfRange > 0.001 THEN
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

// --------- 12 段分箱（梯形 + 矩形共用）---------
// 1=底平; 2..6=升 5 子段（自下而上）; 7=顶平; 8..12=降 5 子段（自上而下）
// 斜坡振幅区间 [-PLATEAU_BAND_K, +PLATEAU_BAND_K]·hR 五等分
IF (nWaveType = 3 OR nWaveType = 4) AND iIterCount >= 1 AND rHalfRange > 0.001 THEN
    iBinTotal12 := iBinTotal12 + 1;
    rPlateauThr := PLATEAU_BAND_K * rHalfRange;
    rBand1 := -0.6 * rPlateauThr;   // = -0.42 hR
    rBand2 := -0.2 * rPlateauThr;   // = -0.14 hR
    rBand3 :=  0.2 * rPlateauThr;   // = +0.14 hR
    rBand4 :=  0.6 * rPlateauThr;   // = +0.42 hR

    rTgtPos := rTargetRaw - rMidpoint;
    IF rTgtPos < -rPlateauThr THEN
        iBinK := 1;
    ELSIF rTgtPos > rPlateauThr THEN
        iBinK := 7;
    ELSIF bTgtRising THEN
        IF      rTgtPos < rBand1 THEN iBinK := 2;
        ELSIF   rTgtPos < rBand2 THEN iBinK := 3;
        ELSIF   rTgtPos < rBand3 THEN iBinK := 4;
        ELSIF   rTgtPos < rBand4 THEN iBinK := 5;
        ELSE                          iBinK := 6;
        END_IF
    ELSE
        IF      rTgtPos > rBand4 THEN iBinK := 8;
        ELSIF   rTgtPos > rBand3 THEN iBinK := 9;
        ELSIF   rTgtPos > rBand2 THEN iBinK := 10;
        ELSIF   rTgtPos > rBand1 THEN iBinK := 11;
        ELSE                          iBinK := 12;
        END_IF
    END_IF
    iTgtBin12[iBinK] := iTgtBin12[iBinK] + 1;

    rFbPos := rActual - rMidpoint;
    IF rFbPos < -rPlateauThr THEN
        iBinK := 1;
    ELSIF rFbPos > rPlateauThr THEN
        iBinK := 7;
    ELSIF bFbRising THEN
        IF      rFbPos < rBand1 THEN iBinK := 2;
        ELSIF   rFbPos < rBand2 THEN iBinK := 3;
        ELSIF   rFbPos < rBand3 THEN iBinK := 4;
        ELSIF   rFbPos < rBand4 THEN iBinK := 5;
        ELSE                         iBinK := 6;
        END_IF
    ELSE
        IF      rFbPos > rBand4 THEN iBinK := 8;
        ELSIF   rFbPos > rBand3 THEN iBinK := 9;
        ELSIF   rFbPos > rBand2 THEN iBinK := 10;
        ELSIF   rFbPos > rBand1 THEN iBinK := 11;
        ELSE                         iBinK := 12;
        END_IF
    END_IF
    iFbBin12[iBinK] := iFbBin12[iBinK] + 1;
END_IF

// --------- 平台分 2 段反馈累加（按 cmd phase 边界）---------
IF (nWaveType = 3 OR nWaveType = 4) AND iIterCount >= 1 THEN
    IF rPhi < rT1Cached THEN
        IF rPhi < rBotMidPhase THEN
            rFbSumBotA := rFbSumBotA + rActual;
            iCntBotA   := iCntBotA + 1;
        ELSE
            rFbSumBotB := rFbSumBotB + rActual;
            iCntBotB   := iCntBotB + 1;
        END_IF
    ELSIF rPhi >= rT6Cached AND rPhi < rT7Cached THEN
        IF rPhi < rTopMidPhase THEN
            rFbSumTopA := rFbSumTopA + rActual;
            iCntTopA   := iCntTopA + 1;
        ELSE
            rFbSumTopB := rFbSumTopB + rActual;
            iCntTopB   := iCntTopB + 1;
        END_IF
    END_IF
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

IF NOT bVInitialized THEN
    rVirtualTarget := rTargetRaw;
    rOutput        := 0.0;
    bNewCyclePrev  := bNewCycle;
    RETURN;
END_IF

// 源波形 rSourceTarget：
//   正弦(1) / 三角(2) → α 8 段相位重映射后再按各自基波形重建
//   其他波形         → 直通 rTargetRaw
IF nWaveType = 1 OR nWaveType = 2 THEN
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

    IF nWaveType = 1 THEN
        // 正弦：基波形 = (1 - cos(2π·φ_std)) / 2
        rWarpedY := (1.0 - COS(TWO_PI * rPhiStd)) / 2.0;
    ELSE
        // 三角：基波形 = 0→1→0 线性三角，尖峰在 φ_std = 0.5
        IF rPhiStd < 0.5 THEN
            rWarpedY := 2.0 * rPhiStd;
        ELSE
            rWarpedY := 2.0 * (1.0 - rPhiStd);
        END_IF
    END_IF
    rSourceTarget := rPrevTargetMin + rWarpedY * rPrevTargetRange;

ELSIF nWaveType = 3 OR nWaveType = 4 THEN
    // 梯形 / 矩形：12 段相位重映射 + 梯形模板
    // 模板（标准振幅 0..1）：
    //   底平(0) → 升 0→0.2→0.4→0.6→0.8→1 → 顶平(1) → 降 1→0.8→0.6→0.4→0.2→0
    rT1  := rAlpha12Cmd[1];
    rT2  := rT1  + rAlpha12Cmd[2];
    rT3  := rT2  + rAlpha12Cmd[3];
    rT4  := rT3  + rAlpha12Cmd[4];
    rT5  := rT4  + rAlpha12Cmd[5];
    rT6  := rT5  + rAlpha12Cmd[6];
    rT7  := rT6  + rAlpha12Cmd[7];
    rT8  := rT7  + rAlpha12Cmd[8];
    rT9  := rT8  + rAlpha12Cmd[9];
    rT10 := rT9  + rAlpha12Cmd[10];
    rT11 := rT10 + rAlpha12Cmd[11];

    IF rPhi < rT1 THEN
        rWarpedY := 0.0;
    ELSIF rPhi < rT2 THEN
        rDelta := rT2 - rT1;
        IF rDelta > 0.001 THEN rWarpedY := (rPhi - rT1) / rDelta * 0.2;
        ELSE rWarpedY := 0.1; END_IF
    ELSIF rPhi < rT3 THEN
        rDelta := rT3 - rT2;
        IF rDelta > 0.001 THEN rWarpedY := 0.2 + (rPhi - rT2) / rDelta * 0.2;
        ELSE rWarpedY := 0.3; END_IF
    ELSIF rPhi < rT4 THEN
        rDelta := rT4 - rT3;
        IF rDelta > 0.001 THEN rWarpedY := 0.4 + (rPhi - rT3) / rDelta * 0.2;
        ELSE rWarpedY := 0.5; END_IF
    ELSIF rPhi < rT5 THEN
        rDelta := rT5 - rT4;
        IF rDelta > 0.001 THEN rWarpedY := 0.6 + (rPhi - rT4) / rDelta * 0.2;
        ELSE rWarpedY := 0.7; END_IF
    ELSIF rPhi < rT6 THEN
        rDelta := rT6 - rT5;
        IF rDelta > 0.001 THEN rWarpedY := 0.8 + (rPhi - rT5) / rDelta * 0.2;
        ELSE rWarpedY := 0.9; END_IF
    ELSIF rPhi < rT7 THEN
        rWarpedY := 1.0;
    ELSIF rPhi < rT8 THEN
        rDelta := rT8 - rT7;
        IF rDelta > 0.001 THEN rWarpedY := 1.0 - (rPhi - rT7) / rDelta * 0.2;
        ELSE rWarpedY := 0.9; END_IF
    ELSIF rPhi < rT9 THEN
        rDelta := rT9 - rT8;
        IF rDelta > 0.001 THEN rWarpedY := 0.8 - (rPhi - rT8) / rDelta * 0.2;
        ELSE rWarpedY := 0.7; END_IF
    ELSIF rPhi < rT10 THEN
        rDelta := rT10 - rT9;
        IF rDelta > 0.001 THEN rWarpedY := 0.6 - (rPhi - rT9) / rDelta * 0.2;
        ELSE rWarpedY := 0.5; END_IF
    ELSIF rPhi < rT11 THEN
        rDelta := rT11 - rT10;
        IF rDelta > 0.001 THEN rWarpedY := 0.4 - (rPhi - rT10) / rDelta * 0.2;
        ELSE rWarpedY := 0.3; END_IF
    ELSE
        rDelta := 1.0 - rT11;
        IF rDelta > 0.001 THEN rWarpedY := 0.2 - (rPhi - rT11) / rDelta * 0.2;
        ELSE rWarpedY := 0.1; END_IF
    END_IF
    rSourceTarget := rPrevTargetMin + rWarpedY * rPrevTargetRange;

ELSE
    rSourceTarget := rTargetRaw;
END_IF

// 仿射重映射 [tMin, tMax] → [vMin, vMax]
rNorm          := (rSourceTarget - rPrevTargetMin) / rPrevTargetRange;
rVirtualTarget := rVMin + rNorm * (rVMax - rVMin);

// 梯形 / 矩形平台幅值修正：按 cmd phase 把每个平台切 2 段，分别叠加 MPa 修正
IF nWaveType = 3 OR nWaveType = 4 THEN
    IF rPhi < rT1Cached THEN
        IF rPhi < rBotMidPhase THEN
            rVirtualTarget := rVirtualTarget + rPlatBotA;
        ELSE
            rVirtualTarget := rVirtualTarget + rPlatBotB;
        END_IF
    ELSIF rPhi >= rT6Cached AND rPhi < rT7Cached THEN
        IF rPhi < rTopMidPhase THEN
            rVirtualTarget := rVirtualTarget + rPlatTopA;
        ELSE
            rVirtualTarget := rVirtualTarget + rPlatTopB;
        END_IF
    END_IF
END_IF

rOutput := rVirtualTarget - rTargetRaw;

bNewCyclePrev := bNewCycle;

END_FUNCTION_BLOCK
