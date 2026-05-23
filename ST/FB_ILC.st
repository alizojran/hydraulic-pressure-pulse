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
	bPlatCorrEnable : BOOL := TRUE;  // 平台 2 段幅值修正使能（仅梯形/矩形生效）
	nWarmupCycles   : INT  := 3;     // 暖机周期数：前N个周期透传不修正，同时完成波形类型检测
	iWaveTypeIn     : INT  := -1;    // 显式波形类型 (与 FB_WaveformGen 对齐): -1=自动检测, 0=正弦, 1=梯形, 2=水锤波
	rWHPMaxTarget   : REAL := 0.0;   // [水锤] PMax 保压段目标 (MPa); 用于 hold 段幅值修正学习
	rWHRiseFrac     : REAL := 0.05;  // [水锤] 段 1: 过冲上升段归一化相位宽 (= 上游 FB_WaveformGen 归一化后的 rR)
	rWHRingFrac     : REAL := 0.07;  // [水锤] 段 2: 过冲衰减段归一化相位宽 (= rRing)
	rWHHoldFrac     : REAL := 0.35;  // [水锤] 段 3: PMax 保压段归一化相位宽 (= rH)
	rWHFallFrac     : REAL := 0.05;  // [水锤] 段 4: 下降段归一化相位宽 (= rF); 段 5 (低保持) = 1 - 上述 4 段
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
	// 梯形 / 矩形：平台分 2 段幅值修正（MPa，叠加在 vMin/vMax 上）
	rPlatBotA      : REAL;
	rPlatBotB      : REAL;
	rPlatTopA      : REAL;
	rPlatTopB      : REAL;
	// 波形检测
	nWaveType      : INT  := -1;     // 与 FB_WaveformGen 同编码: -1=检测中, 0=正弦, 1=梯形, 2=水锤波
	rFlatFrac      : REAL;
	rSymFrac       : REAL;
	// 水锤波 3 级端点学习 (除 rVMin/rVMax 外, 额外学习过冲峰指令)
	rVPeak         : REAL;           // 水锤过冲峰指令 (MPa) — 让 actual 抵达 P_OS
	rWHHoldActual  : REAL;           // 上周期 PMax 保压段 actual 均值 (诊断)
	rWHLowActual   : REAL;           // 上周期 PMin 低保持段 actual 均值 (诊断)
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
	// 平台 2 段反馈累加（按 cmd phase 切割）
	rFbSumBotA       : REAL;
	rFbSumBotB       : REAL;
	rFbSumTopA       : REAL;
	rFbSumTopB       : REAL;
	iCntBotA         : INT;
	iCntBotB         : INT;
	iCntTopA         : INT;
	iCntTopB         : INT;
	// cmd 平台 phase 边界缓存（每周期边界更新一次）
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
	// 水锤波段边界 (新周期缓存; per-sample 与输出阶段共用)
	rWH_T1              : REAL;       // = rWHRiseFrac
	rWH_T2              : REAL;       // = T1 + rWHRingFrac
	rWH_T3              : REAL;       // = T2 + rWHHoldFrac
	rWH_T4              : REAL;       // = T3 + rWHFallFrac
	// 水锤波 per-segment 反馈累加 (每周期清零)
	rWHOSPeakActual     : REAL;       // 段 1: actual 峰
	rWHHoldSum          : REAL;       // 段 3: actual 累加
	iWHHoldCount        : INT;
	rWHLowSum           : REAL;       // 段 5: actual 累加
	iWHLowCount         : INT;
	// 水锤波 ILC 误差 (供学习; 同时作为诊断)
	rWHPeakErr          : REAL;       // P_OS 峰误差
	rWHHoldErr          : REAL;       // PMax hold 误差
	rWHLowErr           : REAL;       // PMin low 误差
END_VAR
VAR CONSTANT
	ALPHA_Q_MIN       : REAL := 0.04;
	ALPHA_Q_MAX       : REAL := 0.35;
	ALPHA12_Q_MIN     : REAL := 0.02;
	ALPHA12_Q_MAX     : REAL := 0.45;
	PLATEAU_BAND_K    : REAL := 0.7;     // 平台判定带：|y - mid| > K * halfRange
	PLAT_CORR_LR      : REAL := 0.3;     // 平台幅值修正学习率
	PLAT_CORR_LIMIT_K : REAL := 0.3;     // 平台幅值修正上限：0.3 * halfRange
	PLAT_TGT_MIN_FRAC : REAL := 0.03;    // 目标平台占比阈值：低于此值视为"没有平台"，跳过修正学习
	PLAT_CORR_DECAY   : REAL := 0.9;     // 跳过学习时的修正衰减系数
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
        nWaveType              := -1;
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
        rPlatBotA := 0.0; rPlatBotB := 0.0;
        rPlatTopA := 0.0; rPlatTopB := 0.0;
        rVPeak := 0.0;
        rWHHoldActual := 0.0;
        rWHLowActual  := 0.0;
        rWH_T1 := 0.0; rWH_T2 := 0.0; rWH_T3 := 0.0; rWH_T4 := 0.0;
        rWHPeakErr := 0.0; rWHHoldErr := 0.0; rWHLowErr := 0.0;
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
    rWHOSPeakActual := -1.0E30;
    rWHHoldSum := 0.0; iWHHoldCount := 0;
    rWHLowSum  := 0.0; iWHLowCount  := 0;
    bNewCyclePrev  := FALSE;
    IF NOT bEnable THEN
        RETURN;
    END_IF
END_IF

IF iPointsPerCycle < 10 THEN
    rOutput := 0.0; rVirtualTarget := 0.0; RETURN;
END_IF

// ============================================================
// 显式波形类型映射 (优先于自动检测)
//   nWaveType 与 FB_WaveformGen 的 iWaveType 同编码:
//     0 = 正弦       (Fig.3)
//     1 = 梯形       (Fig.1)
//     2 = 水锤波     (Fig.2)
//    -1 = 检测中     (仅当 iWaveTypeIn = -1 时使用自动检测)
//   水锤波必须由 iWaveTypeIn = 2 显式指定 (自动检测无法判别过冲)
// ============================================================
IF iWaveTypeIn = 0 OR iWaveTypeIn = 1 OR iWaveTypeIn = 2 THEN
    IF nWaveType <> iWaveTypeIn THEN nWaveType := iWaveTypeIn; END_IF
    bWaveDetected := TRUE;
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
            // 自动检测仅在 sine / trapezoid 间区分 (水锤需 iWaveTypeIn=2 显式指定)
            // 平台占比大 → 梯形 (含旧矩形); 否则 → 正弦 (含旧三角/任意波)
            IF rFlatFrac > FLAT_THR_SIN THEN
                nWaveType := 1;       // 梯形
            ELSE
                nWaveType := 0;       // 正弦
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
            IF nWaveType = 2 THEN
                // 水锤波: rTargetMax 是 P_OS 而非 PMax 保压目标
                rVPeak := rPrevTargetMax;
                IF rWHPMaxTarget > 0.001 THEN
                    rVMax := rWHPMaxTarget;       // PMax 保压目标
                END_IF
            END_IF
            bVInitialized := TRUE;
        END_IF

        IF iMaxIterations > 0 AND iIterCount >= iMaxIterations THEN
            bConverged := TRUE;
        ELSE
            // α 8 段自学习 (正弦 nWaveType=0)
            IF bAlphaEnable AND nWaveType = 0 THEN
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

            // α 12 段自学习 (梯形 nWaveType=1)
            IF bAlphaEnable AND nWaveType = 1 THEN
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

            // 平台分 2 段幅值修正学习 (梯形 nWaveType=1)
            // 双门控：目标平台时间占比 < 3% → 跳过并衰减；样本不足 → 跳过
            IF bPlatCorrEnable AND nWaveType = 1 THEN
                // 顶部平台
                IF rAlpha12Tgt[7] >= PLAT_TGT_MIN_FRAC THEN
                    IF iCntTopA >= 2 THEN
                        rFbAvg := rFbSumTopA / INT_TO_REAL(iCntTopA);
                        rPlatTopA := rPlatTopA + PLAT_CORR_LR * (rPrevTargetMax - rFbAvg);
                    END_IF
                    IF iCntTopB >= 2 THEN
                        rFbAvg := rFbSumTopB / INT_TO_REAL(iCntTopB);
                        rPlatTopB := rPlatTopB + PLAT_CORR_LR * (rPrevTargetMax - rFbAvg);
                    END_IF
                ELSE
                    rPlatTopA := rPlatTopA * PLAT_CORR_DECAY;
                    rPlatTopB := rPlatTopB * PLAT_CORR_DECAY;
                END_IF
                // 底部平台
                IF rAlpha12Tgt[1] >= PLAT_TGT_MIN_FRAC THEN
                    IF iCntBotA >= 2 THEN
                        rFbAvg := rFbSumBotA / INT_TO_REAL(iCntBotA);
                        rPlatBotA := rPlatBotA + PLAT_CORR_LR * (rPrevTargetMin - rFbAvg);
                    END_IF
                    IF iCntBotB >= 2 THEN
                        rFbAvg := rFbSumBotB / INT_TO_REAL(iCntBotB);
                        rPlatBotB := rPlatBotB + PLAT_CORR_LR * (rPrevTargetMin - rFbAvg);
                    END_IF
                ELSE
                    rPlatBotA := rPlatBotA * PLAT_CORR_DECAY;
                    rPlatBotB := rPlatBotB * PLAT_CORR_DECAY;
                END_IF
                // 限幅
                rPlatCorrLimit := PLAT_CORR_LIMIT_K * rHalfRange;
                IF rPlatTopA >  rPlatCorrLimit THEN rPlatTopA :=  rPlatCorrLimit; END_IF
                IF rPlatTopA < -rPlatCorrLimit THEN rPlatTopA := -rPlatCorrLimit; END_IF
                IF rPlatTopB >  rPlatCorrLimit THEN rPlatTopB :=  rPlatCorrLimit; END_IF
                IF rPlatTopB < -rPlatCorrLimit THEN rPlatTopB := -rPlatCorrLimit; END_IF
                IF rPlatBotA >  rPlatCorrLimit THEN rPlatBotA :=  rPlatCorrLimit; END_IF
                IF rPlatBotA < -rPlatCorrLimit THEN rPlatBotA := -rPlatCorrLimit; END_IF
                IF rPlatBotB >  rPlatCorrLimit THEN rPlatBotB :=  rPlatCorrLimit; END_IF
                IF rPlatBotB < -rPlatCorrLimit THEN rPlatBotB := -rPlatCorrLimit; END_IF
            END_IF

            // 端点幅值自学习（加法型）：水锤波由专用 3 级学习处理, 跳过通用路径
            IF nWaveType <> 2 THEN
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

            // ----- 水锤波 3 级端点学习 (vPeak / vMax / vMin 分别对应 P_OS / PMax / PMin) -----
            // 仅当对应段有足够样本时更新; 段 2 (ring) 与段 4 (fall) 是过渡段, 不学习
            IF nWaveType = 2 THEN
                // 段 1 峰: drive actual 抵达 rPrevTargetMax (= P_OS)
                IF rWHOSPeakActual > -1.0E29 THEN
                    rWHPeakErr := rPrevTargetMax - rWHOSPeakActual;
                    rVPeak := rVPeak + rLearningRate * rWHPeakErr;
                END_IF
                // 段 3 hold: drive actual 抵达 rWHPMaxTarget
                IF iWHHoldCount >= 2 THEN
                    rWHHoldActual := rWHHoldSum / INT_TO_REAL(iWHHoldCount);
                    IF rWHPMaxTarget > 0.001 THEN
                        rWHHoldErr := rWHPMaxTarget - rWHHoldActual;
                        rVMax := rVMax + rLearningRate * rWHHoldErr;
                    END_IF
                END_IF
                // 段 5 low: drive actual 抵达 rPrevTargetMin
                IF iWHLowCount >= 2 THEN
                    rWHLowActual := rWHLowSum / INT_TO_REAL(iWHLowCount);
                    rWHLowErr := rPrevTargetMin - rWHLowActual;
                    rVMin := rVMin + rLearningRate * rWHLowErr;
                END_IF
                // 限幅 (与通用端点学习一致)
                IF rPrevTargetRange > 0.001 THEN
                    rLimit := V_RANGE_LIMIT_K * rPrevTargetRange;
                    IF rVMax  > rPrevTargetMax + rLimit THEN rVMax  := rPrevTargetMax + rLimit; END_IF
                    IF rVMax  < rPrevTargetMax - rLimit THEN rVMax  := rPrevTargetMax - rLimit; END_IF
                    IF rVMin  > rPrevTargetMin + rLimit THEN rVMin  := rPrevTargetMin + rLimit; END_IF
                    IF rVMin  < rPrevTargetMin - rLimit THEN rVMin  := rPrevTargetMin - rLimit; END_IF
                    IF rVPeak > rPrevTargetMax + rLimit THEN rVPeak := rPrevTargetMax + rLimit; END_IF
                    IF rVPeak < rPrevTargetMax - rLimit THEN rVPeak := rPrevTargetMax - rLimit; END_IF
                END_IF
                IF rVMax  <= rVMin + 0.001 THEN rVMax  := rVMin + 0.001;  END_IF
                IF rVPeak < rVMax              THEN rVPeak := rVMax;        END_IF
                // 复位累加器 (下周期重新统计)
                rWHOSPeakActual := -1.0E30;
                rWHHoldSum := 0.0; iWHHoldCount := 0;
                rWHLowSum  := 0.0; iWHLowCount  := 0;
            END_IF
        END_IF
    END_IF

    // 诊断派生量 rScalePos / rScaleNeg
    IF rHalfRange > 0.001 AND bVInitialized THEN
        rScalePos := (rVMax - rMidpoint) / rHalfRange;
        rScaleNeg := (rMidpoint - rVMin) / rHalfRange;
    END_IF

    // 缓存梯形/矩形平台 phase 边界（per-sample 与输出阶段共用）
    IF nWaveType = 1 THEN
        rT1Cached    := rAlpha12Cmd[1];
        rT6Cached    := rT1Cached + rAlpha12Cmd[2] + rAlpha12Cmd[3]
                     + rAlpha12Cmd[4] + rAlpha12Cmd[5] + rAlpha12Cmd[6];
        rT7Cached    := rT6Cached + rAlpha12Cmd[7];
        rBotMidPhase := rT1Cached * 0.5;
        rTopMidPhase := (rT6Cached + rT7Cached) * 0.5;
    END_IF

    // 缓存水锤波 5 段边界 (累积归一化相位; 上游已保证 sum = 1)
    IF nWaveType = 2 THEN
        rWH_T1 := rWHRiseFrac;
        rWH_T2 := rWH_T1 + rWHRingFrac;
        rWH_T3 := rWH_T2 + rWHHoldFrac;
        rWH_T4 := rWH_T3 + rWHFallFrac;
    END_IF

    // 复位平台 2 段反馈累加
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
IF (nWaveType = 0) AND iIterCount >= 1 AND rHalfRange > 0.001 THEN
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
IF (nWaveType = 1) AND iIterCount >= 1 AND rHalfRange > 0.001 THEN
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

// --------- 水锤波 per-segment 反馈累加（按归一化相位切割）---------
// 段 1: 跟踪 actual 峰 (供 rVPeak 学习, 抵达 P_OS)
// 段 2: ring 过渡, 不学习
// 段 3: 累加均值 (供 rVMax 学习, 抵达 PMax 保压目标)
// 段 4: fall 过渡, 不学习
// 段 5: 累加均值 (供 rVMin 学习, 抵达 PMin 低保持)
IF nWaveType = 2 AND iIterCount >= 1 THEN
    IF rPhi < rWH_T1 THEN
        IF rActual > rWHOSPeakActual THEN rWHOSPeakActual := rActual; END_IF
    ELSIF rPhi >= rWH_T2 AND rPhi < rWH_T3 THEN
        rWHHoldSum   := rWHHoldSum + rActual;
        iWHHoldCount := iWHHoldCount + 1;
    ELSIF rPhi >= rWH_T4 THEN
        rWHLowSum    := rWHLowSum + rActual;
        iWHLowCount  := iWHLowCount + 1;
    END_IF
END_IF

// --------- 平台 2 段反馈累加（按 cmd phase 切割）---------
IF (nWaveType = 1) AND iIterCount >= 1 THEN
    IF rPhi < rT1Cached AND rT1Cached > 0.001 THEN
        IF rPhi < rBotMidPhase THEN
            rFbSumBotA := rFbSumBotA + rActual;
            iCntBotA   := iCntBotA + 1;
        ELSE
            rFbSumBotB := rFbSumBotB + rActual;
            iCntBotB   := iCntBotB + 1;
        END_IF
    ELSIF rPhi >= rT6Cached AND rPhi < rT7Cached AND (rT7Cached - rT6Cached) > 0.001 THEN
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
IF nWaveType = 0 THEN
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

    // 正弦：基波形 = (1 - cos(2π·φ_std)) / 2
    rWarpedY := (1.0 - COS(TWO_PI * rPhiStd)) / 2.0;
    rSourceTarget := rPrevTargetMin + rWarpedY * rPrevTargetRange;

ELSIF nWaveType = 2 THEN
    // 水锤波: 5 段直接重构 (3 级端点学习 vPeak / vMax / vMin, 不走仿射重映射)
    //   段 1: rVPeak                       (过冲峰)
    //   段 2: rVMax                        (ring 衰减后立即落到 PMax)
    //   段 3: rVMax                        (PMax 保压)
    //   段 4: 线性 rVMax → rVMin           (下降)
    //   段 5: rVMin                        (PMin 低保持)
    IF rPhi < rWH_T1 THEN
        rVirtualTarget := rVPeak;
    ELSIF rPhi < rWH_T2 THEN
        rVirtualTarget := rVMax;
    ELSIF rPhi < rWH_T3 THEN
        rVirtualTarget := rVMax;
    ELSIF rPhi < rWH_T4 THEN
        rDelta := rWH_T4 - rWH_T3;
        IF rDelta > 0.001 THEN
            rVirtualTarget := rVMax - (rPhi - rWH_T3) / rDelta * (rVMax - rVMin);
        ELSE
            rVirtualTarget := (rVMax + rVMin) / 2.0;
        END_IF
    ELSE
        rVirtualTarget := rVMin;
    END_IF
    rOutput := rVirtualTarget - rTargetRaw;
    bNewCyclePrev := bNewCycle;
    RETURN;

ELSIF nWaveType = 1 THEN
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

// 梯形/矩形平台 2 段幅值修正：按 cmd phase 落在哪个子段叠加对应 MPa 偏置
IF bPlatCorrEnable AND (nWaveType = 1) THEN
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
