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
	rLearningRate   : REAL := 0.3;   // 端点学习率 (rVMax/rVMin 的步长系数)
	rAlphaLR        : REAL := 0.2;   // α 学习率（仅正弦/三角波有效）
	bAlphaEnable    : BOOL := TRUE;  // α 自学习使能（FALSE = 8 段参数锁定不更新）
	nWarmupCycles   : INT  := 3;     // 暖机周期数：前N个周期透传不修正，同时完成波形类型检测
END_VAR
VAR_OUTPUT
	rOutput        : REAL;           // 修正量 = rVirtualTarget - rTargetRaw (MPa)
	rVirtualTarget : REAL;           // 预畸变指令实时值 (MPa)
	iIteration     : INT;
	rRmsError      : REAL;
	bConverged     : BOOL;
	rPeakError     : REAL;           // = rTargetMax - rActualMax（反馈峰不够高 → 正）
	rValleyError   : REAL;           // = rTargetMin - rActualMin（反馈谷不够低 → 负）
	rVMax          : REAL;           // 虚拟峰：仿射映射的目标上端点
	rVMin          : REAL;           // 虚拟谷：仿射映射的目标下端点
	rScalePos      : REAL := 1.0;    // 诊断派生量：(rVMax - rMidpoint) / rHalfRange
	rScaleNeg      : REAL := 1.0;    // 诊断派生量：(rMidpoint - rVMin) / rHalfRange
	// ---- 8 段 α 时长占比（替代原 4 象限）----
	//   1: 上升+深下 (rActual < mid - 0.5*halfRange)
	//   2: 上升+浅下 (mid - 0.5*halfRange ≤ rActual < mid)
	//   3: 上升+浅上 (mid ≤ rActual < mid + 0.5*halfRange)
	//   4: 上升+深上 (rActual ≥ mid + 0.5*halfRange)
	//   5: 下降+深上
	//   6: 下降+浅上
	//   7: 下降+浅下
	//   8: 下降+深下
	rAlphaCmd      : ARRAY [1..8] OF REAL;   // 学习得到的 cmd 8 段时长占比
	rAlphaTgt      : ARRAY [1..8] OF REAL;   // 目标 8 段实际分布（学习参考，诊断）
	rAlphaFb       : ARRAY [1..8] OF REAL;   // 反馈 8 段实际分布（诊断）
	nWaveType      : INT  := 0;      // 检测到的波形类型：0=检测中, 1=正弦, 2=三角, 3=梯形, 4=矩形, 5=任意波
	rFlatFrac      : REAL;           // 指令峰谷附近时间占比（波形类型判断依据，诊断）
	rSymFrac       : REAL;           // 指令在均值以上时间占比（对称性，诊断：0.5=对称，偏离大→任意波）
END_VAR
VAR
	rMidpoint        : REAL;
	rHalfRange       : REAL;
	rQuarter         : REAL;         // = 0.5 * rHalfRange，幅值四分档分界量
	rTargetMax       : REAL;
	rTargetMin       : REAL;
	rActualMax       : REAL;
	rActualMin       : REAL;
	rPrevTargetMax   : REAL;
	rPrevTargetMin   : REAL;
	rPrevTargetRange : REAL;
	bNewCyclePrev    : BOOL;
	iIterCount       : INT;
	bVInitialized    : BOOL;
	nUpdateCount     : INT;
	rPeakErrSum      : REAL;
	rValleyErrSum    : REAL;
	rErrorSum2       : REAL;
	iErrorCount      : INT;
	// ---- 8 段分箱计数 ----
	iTgtBin          : ARRAY [1..8] OF INT;
	iFbBin           : ARRAY [1..8] OF INT;
	iBinTotal        : INT;          // 本周期内有效分箱采样总数（rHalfRange 已初始化的样本）
	rTargetPrev      : REAL;
	bTgtRising       : BOOL;
	rActualPrev      : REAL;
	bFbRising        : BOOL;
	rTgtPos          : REAL;
	rFbPos           : REAL;
	iBinK            : INT;          // 分箱循环临时
	iSegK            : INT;          // 输出段循环临时
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
	rBinTotal        : REAL;         // INT_TO_REAL(iBinTotal)
	iNearExtCount       : INT;
	iTargetAboveMidCount: INT;
	iTotalDetectCount   : INT;
	bWaveDetected       : BOOL;
END_VAR
VAR CONSTANT
	// 8 段 α 边界
	// 默认 1/8 = 0.125；下界 0.05（最快段占 5% 周期，斜率 2.5× 正常，液压能跟）；
	// 上界 0.25（最慢段占 25% 周期）
	ALPHA_Q_MIN       : REAL := 0.05;
	ALPHA_Q_MAX       : REAL := 0.25;
	TWO_PI            : REAL := 6.283185307;
	CYCLES_PER_UPDATE : INT  := 2;
	// 波形类型判断阈值
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
        // 8 段 α 默认均分 1/8 = 0.125（透传基底）
        FOR iBinK := 1 TO 8 DO
            rAlphaCmd[iBinK] := 0.125;
            rAlphaTgt[iBinK] := 0.125;
            rAlphaFb[iBinK]  := 0.125;
        END_FOR
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

    // 8 段分布归一（目标 / 反馈各自）
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

    // rMidpoint / rHalfRange / rQuarter
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
        // ---- 暖机期末：完成波形类型检测 ----
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
            // ---- 8 段 α 自学习（仅正弦/三角 nWaveType=1/2）----
            // 参考使用目标自身分布 rAlphaTgt[k]，不是写死 1/8——这样正弦的非均匀分布
            // (0.167, 0.083, 0.083, 0.167, ...) 也是合法的稳态点
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

            // ---- 端点幅值自学习（加法型，所有波形通用）----
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

    // 诊断派生量
    IF rHalfRange > 0.001 AND bVInitialized THEN
        rScalePos := (rVMax - rMidpoint) / rHalfRange;
        rScaleNeg := (rMidpoint - rVMin) / rHalfRange;
    END_IF

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

IF rTargetRaw > rTargetMax THEN rTargetMax := rTargetRaw; END_IF
IF rTargetRaw < rTargetMin THEN rTargetMin := rTargetRaw; END_IF
IF rActual    > rActualMax THEN rActualMax := rActual;    END_IF
IF rActual    < rActualMin THEN rActualMin := rActual;    END_IF

rErrorSum2  := rErrorSum2 + (rTargetRaw - rActual) * (rTargetRaw - rActual);
iErrorCount := iErrorCount + 1;

// ---- 波形类型检测 ----
IF NOT bWaveDetected AND iIterCount >= 1 AND rHalfRange > 0.001 THEN
    iTotalDetectCount := iTotalDetectCount + 1;
    IF ABS(rTargetRaw - rMidpoint) > 0.9 * rHalfRange THEN
        iNearExtCount := iNearExtCount + 1;
    END_IF
    IF rTargetRaw >= rMidpoint THEN
        iTargetAboveMidCount := iTargetAboveMidCount + 1;
    END_IF
END_IF

// ---- 方向检测（目标 / 反馈各自）----
IF rTargetRaw >= rTargetPrev THEN bTgtRising := TRUE; ELSE bTgtRising := FALSE; END_IF
rTargetPrev := rTargetRaw;
IF rActual   >= rActualPrev THEN bFbRising  := TRUE; ELSE bFbRising  := FALSE; END_IF
rActualPrev := rActual;

// ---- 8 段分箱（rHalfRange 已由上一周期初始化后才生效）----
IF iIterCount >= 1 AND rHalfRange > 0.001 THEN
    iBinTotal := iBinTotal + 1;

    // 目标分箱
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

    // 反馈分箱
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

// ============================================================
// 输出生成
// ============================================================

// 暖机期 / 首次学习窗未到 / 目标无幅值：直通
IF iIterCount <= nWarmupCycles OR NOT bVInitialized OR rPrevTargetRange < 0.001 THEN
    rVirtualTarget := rTargetRaw;
    rOutput        := 0.0;
    bNewCyclePrev  := bNewCycle;
    RETURN;
END_IF

// ---- 源波形 rSourceTarget ----
//   正弦(1)/三角(2)：用 8 段 α 重建标准基底
//   其余：直通 rTargetRaw
IF nWaveType = 1 OR nWaveType = 2 THEN
    rT1 := rAlphaCmd[1];
    rT2 := rT1 + rAlphaCmd[2];
    rT3 := rT2 + rAlphaCmd[3];
    rT4 := rT3 + rAlphaCmd[4];
    rT5 := rT4 + rAlphaCmd[5];
    rT6 := rT5 + rAlphaCmd[6];
    rT7 := rT6 + rAlphaCmd[7];

    IF rPhi < rT1 THEN
        IF rT1 > 0.001 THEN
            rPhiStd := rPhi / rT1 * 0.125;
        ELSE
            rPhiStd := 0.0;
        END_IF
    ELSIF rPhi < rT2 THEN
        rDelta := rT2 - rT1;
        IF rDelta > 0.001 THEN
            rPhiStd := 0.125 + (rPhi - rT1) / rDelta * 0.125;
        ELSE
            rPhiStd := 0.125;
        END_IF
    ELSIF rPhi < rT3 THEN
        rDelta := rT3 - rT2;
        IF rDelta > 0.001 THEN
            rPhiStd := 0.250 + (rPhi - rT2) / rDelta * 0.125;
        ELSE
            rPhiStd := 0.250;
        END_IF
    ELSIF rPhi < rT4 THEN
        rDelta := rT4 - rT3;
        IF rDelta > 0.001 THEN
            rPhiStd := 0.375 + (rPhi - rT3) / rDelta * 0.125;
        ELSE
            rPhiStd := 0.375;
        END_IF
    ELSIF rPhi < rT5 THEN
        rDelta := rT5 - rT4;
        IF rDelta > 0.001 THEN
            rPhiStd := 0.500 + (rPhi - rT4) / rDelta * 0.125;
        ELSE
            rPhiStd := 0.500;
        END_IF
    ELSIF rPhi < rT6 THEN
        rDelta := rT6 - rT5;
        IF rDelta > 0.001 THEN
            rPhiStd := 0.625 + (rPhi - rT5) / rDelta * 0.125;
        ELSE
            rPhiStd := 0.625;
        END_IF
    ELSIF rPhi < rT7 THEN
        rDelta := rT7 - rT6;
        IF rDelta > 0.001 THEN
            rPhiStd := 0.750 + (rPhi - rT6) / rDelta * 0.125;
        ELSE
            rPhiStd := 0.750;
        END_IF
    ELSE
        rDelta := 1.0 - rT7;
        IF rDelta > 0.001 THEN
            rPhiStd := 0.875 + (rPhi - rT7) / rDelta * 0.125;
        ELSE
            rPhiStd := 0.875;
        END_IF
    END_IF

    IF nWaveType = 2 THEN
        IF rPhiStd < 0.5 THEN
            rWarpedY := 2.0 * rPhiStd;
        ELSE
            rWarpedY := 2.0 * (1.0 - rPhiStd);
        END_IF
    ELSE
        rWarpedY := (1.0 - COS(TWO_PI * rPhiStd)) / 2.0;
    END_IF

    rSourceTarget := rPrevTargetMin + rWarpedY * rPrevTargetRange;
ELSE
    rSourceTarget := rTargetRaw;
END_IF

// 仿射重映射
rNorm          := (rSourceTarget - rPrevTargetMin) / rPrevTargetRange;
rVirtualTarget := rVMin + rNorm * (rVMax - rVMin);

rOutput := rVirtualTarget - rTargetRaw;

bNewCyclePrev := bNewCycle;

END_FUNCTION_BLOCK
