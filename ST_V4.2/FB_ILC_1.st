FUNCTION_BLOCK FB_ILC_1
VAR_INPUT
	bEnable : BOOL;
	rTargetRaw : REAL; // 原始目标值 (MPa)
	rActual : REAL; // 当前反馈值 (MPa)
	iPointIndex : INT;
	iPointsPerCycle : INT;
	bNewCycle : BOOL;
	bReset : BOOL;
	iMaxIterations : INT;
	rLearningRate : REAL := 0.3;
END_VAR
VAR_OUTPUT
	rOutput : REAL; // 目标修正量 (MPa)
	rVirtualTarget : REAL; // 虚拟指令实时值（诊断）
	iIteration : INT;
	rRmsError : REAL;
	bConverged : BOOL;
	rPeakError : REAL;
	rValleyError : REAL;
END_VAR
VAR
	arrScale : ARRAY[0..19] OF REAL; // 每段的缩放系数
	arrBinSum : ARRAY[0..19] OF REAL; // 每段本周期误差累加
	arrBinCount : ARRAY[0..19] OF INT; // 每段本周期采样计数
	rMidpoint : REAL; // 目标中点
	rHalfRange : REAL; // 目标半幅
	rTargetMax : REAL; // 本周期目标峰值
	rTargetMin : REAL; // 本周期目标谷值
	rActualMax : REAL; // 本周期反馈峰值
	rActualMin : REAL; // 本周期反馈谷值
	rPrevActualMax : REAL; // 上周期反馈峰值（用于构建虚拟指令）
	rPrevActualMin : REAL; // 上周期反馈谷值
	rPrevActualRange : REAL; // 上周期反馈幅值范围
	rPrevTargetMax : REAL; // 上周期目标峰值
	rPrevTargetMin : REAL; // 上周期目标谷值
	rPrevTargetRange : REAL; // 上周期目标幅值范围
	bNewCyclePrev : BOOL;
	iIterCount : INT;
	rErrorSum2 : REAL;
	iErrorCount : INT;
	iClrIdx : INT;
	iBin : INT;
	rNorm : REAL;
	rVT : REAL;
	rAmpErr : REAL;
	rAvgErr : REAL;
END_VAR

IF bReset OR NOT bEnable THEN
    IF bReset THEN
        FOR iClrIdx := 0 TO 19 DO
            arrScale[iClrIdx] := 1.0;
            arrBinSum[iClrIdx] := 0.0;
            arrBinCount[iClrIdx] := 0;
        END_FOR
        iIterCount := 0;
        rRmsError := 0.0;
        bConverged := FALSE;
        rMidpoint := 0.0;
        rHalfRange := 0.0;
        rPrevActualMax := 0.0;
        rPrevActualMin := 0.0;
        rPrevActualRange := 0.0;
        rPrevTargetMax := 0.0;
        rPrevTargetMin := 0.0;
        rPrevTargetRange := 0.0;
    END_IF
    rOutput := 0.0;
    rVirtualTarget := 0.0;
    rTargetMax := -1.0E30;
    rTargetMin := 1.0E30;
    rActualMax := -1.0E30;
    rActualMin := 1.0E30;
    rErrorSum2 := 0.0;
    iErrorCount := 0;
    bNewCyclePrev := FALSE;
    IF NOT bEnable THEN
        RETURN;
    END_IF
END_IF

IF iPointsPerCycle < 10 THEN
    rOutput := 0.0;
    rVirtualTarget := 0.0;
    RETURN;
END_IF

// ============================================================
// 新周期：更新缩放系数 + 保存峰谷
// ============================================================
IF bNewCycle AND NOT bNewCyclePrev THEN
    IF iErrorCount > 0 THEN
        rRmsError := SQRT(rErrorSum2 / INT_TO_REAL(iErrorCount));
    END_IF
    rErrorSum2 := 0.0;
    iErrorCount := 0;

    // 诊断
    rPeakError := rTargetMax - rActualMax;
    rValleyError := rTargetMin - rActualMin;

    IF iIterCount > 0 THEN
        IF iMaxIterations > 0 AND iIterCount >= iMaxIterations THEN
            bConverged := TRUE;
        ELSE
            // 逐段更新缩放系数
            // 上半段(bin >= NUM_BINS/2): ampErr正 = 不够高 → scale增大
            // 下半段(bin < NUM_BINS/2): ampErr负 = 谷值太高 → 需scale增大来推低
            //   但 (target-mid) 是负数，scale增大让结果更负→更低，所以下半段取反
            FOR iBin := 0 TO NUM_BINS - 1 DO
                IF arrBinCount[iBin] > 2 THEN
                    rAvgErr := arrBinSum[iBin] / INT_TO_REAL(arrBinCount[iBin]);
                    IF rHalfRange > 0.001 THEN
                        IF iBin >= (NUM_BINS / 2) THEN
                            arrScale[iBin] := arrScale[iBin] + rLearningRate * rAvgErr / rHalfRange;
                        ELSE
                            arrScale[iBin] := arrScale[iBin] - rLearningRate * rAvgErr / rHalfRange;
                        END_IF
                    END_IF
                    IF arrScale[iBin] < SCALE_MIN THEN arrScale[iBin] := SCALE_MIN; END_IF
                    IF arrScale[iBin] > SCALE_MAX THEN arrScale[iBin] := SCALE_MAX; END_IF
                END_IF
            END_FOR
        END_IF
    END_IF

    // 保存本周期峰谷给下周期用（构建虚拟指令）
    rPrevActualMax := rActualMax;
    rPrevActualMin := rActualMin;
    rPrevActualRange := rActualMax - rActualMin;
    rPrevTargetMax := rTargetMax;
    rPrevTargetMin := rTargetMin;
    rPrevTargetRange := rTargetMax - rTargetMin;

    // 更新目标中点和半幅
    rMidpoint := (rTargetMax + rTargetMin) / 2.0;
    rHalfRange := (rTargetMax - rTargetMin) / 2.0;
    IF rHalfRange < 0.001 THEN rHalfRange := 0.001; END_IF

    // 重置
    FOR iClrIdx := 0 TO 19 DO
        arrBinSum[iClrIdx] := 0.0;
        arrBinCount[iClrIdx] := 0;
    END_FOR
    rTargetMax := -1.0E30;
    rTargetMin := 1.0E30;
    rActualMax := -1.0E30;
    rActualMin := 1.0E30;

    iIterCount := iIterCount + 1;
    iIteration := iIterCount;
END_IF

// ============================================================
// 每个采样点
// ============================================================
// 跟踪峰谷
IF rTargetRaw > rTargetMax THEN rTargetMax := rTargetRaw; END_IF
IF rTargetRaw < rTargetMin THEN rTargetMin := rTargetRaw; END_IF
IF rActual > rActualMax THEN rActualMax := rActual; END_IF
IF rActual < rActualMin THEN rActualMin := rActual; END_IF

// RMS
rErrorSum2 := rErrorSum2 + (rTargetRaw - rActual) * (rTargetRaw - rActual);
iErrorCount := iErrorCount + 1;

// ---- 学习：构建虚拟指令（从反馈缩放到目标范围）→ 纯幅值误差 ----
// 虚拟指令和反馈天然同相，误差不含相位分量
IF rPrevActualRange > 0.001 THEN
    // 反馈归一化到 [0,1]
    rNorm := (rActual - rPrevActualMin) / rPrevActualRange;
    IF rNorm < 0.0 THEN rNorm := 0.0; END_IF
    IF rNorm > 1.0 THEN rNorm := 1.0; END_IF

    // 虚拟指令 = 用目标的幅值范围重建
    rVT := rPrevTargetMin + rNorm * rPrevTargetRange;

    // 纯幅值误差
    rAmpErr := rVT - rActual;

    // 按反馈归一化位置索引 bin
    iBin := REAL_TO_INT(rNorm * INT_TO_REAL(NUM_BINS - 1));
    IF iBin < 0 THEN iBin := 0; END_IF
    IF iBin > NUM_BINS - 1 THEN iBin := NUM_BINS - 1; END_IF

    arrBinSum[iBin] := arrBinSum[iBin] + rAmpErr;
    arrBinCount[iBin] := arrBinCount[iBin] + 1;
END_IF

// ---- 输出：按目标归一化位置查表，施加修正 ----
IF rHalfRange > 0.001 THEN
    rNorm := (rTargetRaw - rMidpoint + rHalfRange) / (2.0 * rHalfRange);
ELSE
    rNorm := 0.5;
END_IF
IF rNorm < 0.0 THEN rNorm := 0.0; END_IF
IF rNorm > 1.0 THEN rNorm := 1.0; END_IF

iBin := REAL_TO_INT(rNorm * INT_TO_REAL(NUM_BINS - 1));
IF iBin < 0 THEN iBin := 0; END_IF
IF iBin > NUM_BINS - 1 THEN iBin := NUM_BINS - 1; END_IF

rVirtualTarget := rMidpoint + (rTargetRaw - rMidpoint) * arrScale[iBin];
rOutput := rVirtualTarget - rTargetRaw;

bNewCyclePrev := bNewCycle;
END_FUNCTION_BLOCK
