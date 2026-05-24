FUNCTION_BLOCK FB_ILC_2_1
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
	rAlphaTarget : REAL := 0.5; // 目标过均值时长占比
	rAlphaLR : REAL := 0.4; // α 学习率
END_VAR
VAR_OUTPUT
	rOutput : REAL; // 修正量 = rVirtualTarget - rTargetRaw (MPa)
	rVirtualTarget : REAL; // 预畸变指令实时值 (MPa)
	iIteration : INT;
	rRmsError : REAL;
	bConverged : BOOL;
	rPeakError : REAL; // 目标峰值 - 反馈峰值 (MPa)
	rValleyError : REAL; // 目标谷值 - 反馈谷值 (MPa)
	rAlphaFb : REAL := 0.5; // 反馈过均值时长占比（诊断）
	rAlphaCmd : REAL := 0.5; // 当前指令 α（诊断）
	rScalePos : REAL := 1.0; // 上半幅值放大系数（诊断）
	rScaleNeg : REAL := 1.0; // 下半幅值放大系数（诊断）
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
	nScaleCycleCount : INT; // 为幅值 scale 已累积的周期数
	rAmpFbPosSum : REAL; // 累积：反馈上半幅值之和
	rAmpFbNegSum : REAL; // 累积：反馈下半幅值之和
	rAmpFbPos : REAL;
	rAmpFbNeg : REAL;
	rErrorSum2 : REAL;
	iErrorCount : INT;
	iAboveMidCount : INT;
	rPhi : REAL;
	rPhiStd : REAL;
	rAlphaLo : REAL;
	rAlphaHi : REAL;
	rWarpedY : REAL;
	rWarpedTarget : REAL;
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
        rAlphaCmd        := 0.5;
        rAlphaFb         := 0.5;
        rScalePos        := 1.0;
        rScaleNeg        := 1.0;
        iAboveMidCount   := 0;
    END_IF
    rOutput        := 0.0;
    rVirtualTarget := 0.0;
    rTargetMax     := -1.0E30;
    rTargetMin     :=  1.0E30;
    rActualMax     := -1.0E30;
    rActualMin     :=  1.0E30;
    rErrorSum2     := 0.0;
    iErrorCount    := 0;
    iAboveMidCount := 0;
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

    // RMS + α_fb
    IF iErrorCount > 0 THEN
        rRmsError := SQRT(rErrorSum2 / INT_TO_REAL(iErrorCount));
        rAlphaFb  := INT_TO_REAL(iAboveMidCount) / INT_TO_REAL(iErrorCount);
    END_IF
    rErrorSum2     := 0.0;
    iErrorCount    := 0;
    iAboveMidCount := 0;

    // 峰谷误差诊断（使用旧 rMidpoint）
    rPeakError   := rTargetMax - rActualMax;
    rValleyError := rTargetMin - rActualMin;

    // 本周期反馈上下半幅值（使用旧 rMidpoint，与 rAlphaFb 同基准）
    rAmpFbPos := rActualMax - rMidpoint;
    rAmpFbNeg := rMidpoint  - rActualMin;

    // 更新中点 & 半幅（现在才切换到新周期的目标数据）
    rMidpoint  := (rTargetMax + rTargetMin) / 2.0;
    rHalfRange := (rTargetMax - rTargetMin) / 2.0;
    IF rHalfRange < 0.001 THEN rHalfRange := 0.001; END_IF

    // 保存本周期目标峰谷，供下周期生成预畸变指令
    rPrevTargetMax   := rTargetMax;
    rPrevTargetMin   := rTargetMin;
    rPrevTargetRange := rTargetMax - rTargetMin;

    // 重置峰谷追踪
    rTargetMax := -1.0E30; rTargetMin :=  1.0E30;
    rActualMax := -1.0E30; rActualMin :=  1.0E30;

    iIterCount := iIterCount + 1;
    iIteration := iIterCount;

    IF iIterCount > 1 AND NOT bConverged THEN
        IF iMaxIterations > 0 AND iIterCount >= iMaxIterations THEN
            bConverged := TRUE;
        ELSE
            // ---- α 自学习：每周期更新（只改时间轴，不影响幅值）----
            // rAlphaFb < rAlphaTarget → 反馈尖峰圆谷 → 增大 rAlphaCmd
            rAlphaCmd := rAlphaCmd + rAlphaLR * (rAlphaTarget - rAlphaFb);
            IF rAlphaCmd < ALPHA_MIN THEN rAlphaCmd := ALPHA_MIN; END_IF
            IF rAlphaCmd > ALPHA_MAX THEN rAlphaCmd := ALPHA_MAX; END_IF

            // ---- 幅值自学习：每 CYCLES_PER_UPDATE 周期更新（只改幅值，不影响波形形状）----
            // rScalePos/rScaleNeg 与 α 正交，互不干扰
            rAmpFbPosSum     := rAmpFbPosSum + rAmpFbPos;
            rAmpFbNegSum     := rAmpFbNegSum + rAmpFbNeg;
            nScaleCycleCount := nScaleCycleCount + 1;

            IF nScaleCycleCount >= CYCLES_PER_UPDATE THEN
                rAmpFbPos := rAmpFbPosSum / INT_TO_REAL(nScaleCycleCount);
                rAmpFbNeg := rAmpFbNegSum / INT_TO_REAL(nScaleCycleCount);

                // 目标幅值 = rHalfRange（新周期，已更新）
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

// RMS 累积
rErrorSum2  := rErrorSum2 + (rTargetRaw - rActual) * (rTargetRaw - rActual);
iErrorCount := iErrorCount + 1;

// α 采样
IF rActual > rMidpoint THEN iAboveMidCount := iAboveMidCount + 1; END_IF

// ---- 输出：α 相位畸变 + 上下半幅值缩放（正交，不干扰）----

// 1. 归一化相位 φ ∈ [0,1)
IF iPointsPerCycle > 0 THEN
    rPhi := INT_TO_REAL(iPointIndex) / INT_TO_REAL(iPointsPerCycle);
ELSE
    rPhi := 0.0;
END_IF
IF rPhi < 0.0 THEN rPhi := 0.0; END_IF
IF rPhi > 1.0 THEN rPhi := 1.0; END_IF

// 2. 3段线性相位畸变：将过均值时长从 0.5 调整为 rAlphaCmd
//    lo=(1-α)/2, hi=(1+α)/2
//    [0, lo]   → φ_std ∈ [0,   0.25]
//    [lo, hi]  → φ_std ∈ [0.25,0.75]
//    [hi, 1]   → φ_std ∈ [0.75,1.0]
rAlphaLo := (1.0 - rAlphaCmd) / 2.0;
rAlphaHi := (1.0 + rAlphaCmd) / 2.0;

IF rPhi <= rAlphaLo THEN
    IF rAlphaLo > 0.001 THEN
        rPhiStd := rPhi / rAlphaLo * 0.25;
    ELSE
        rPhiStd := 0.0;
    END_IF
ELSIF rPhi <= rAlphaHi THEN
    IF rAlphaCmd > 0.001 THEN
        rPhiStd := 0.25 + (rPhi - rAlphaLo) / rAlphaCmd * 0.5;
    ELSE
        rPhiStd := 0.5;
    END_IF
ELSE
    IF rAlphaLo > 0.001 THEN
        rPhiStd := 0.75 + (rPhi - rAlphaHi) / rAlphaLo * 0.25;
    ELSE
        rPhiStd := 1.0;
    END_IF
END_IF

// 3. 余弦波 → 归一化幅值 [0,1]
rWarpedY := (1.0 - COS(TWO_PI * rPhiStd)) / 2.0;

// 4. 映射到目标压力范围（第1周期前无上周期数据，回退到原始指令）
IF rPrevTargetRange > 0.001 THEN
    rWarpedTarget := rPrevTargetMin + rWarpedY * rPrevTargetRange;
ELSE
    rWarpedTarget := rTargetRaw;
END_IF

// 5. 上下半独立幅值缩放（rScalePos/rScaleNeg 与 α 正交）
IF rWarpedTarget >= rMidpoint THEN
    rVirtualTarget := rMidpoint + (rWarpedTarget - rMidpoint) * rScalePos;
ELSE
    rVirtualTarget := rMidpoint - (rMidpoint - rWarpedTarget) * rScaleNeg;
END_IF

rOutput := rVirtualTarget - rTargetRaw;

bNewCyclePrev := bNewCycle;
END_FUNCTION_BLOCK
