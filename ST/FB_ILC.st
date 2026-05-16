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
	rAlphaLR        : REAL := 0.4;   // α 学习率（仅正弦/三角波有效）
	bAlphaEnable    : BOOL := TRUE;  // α 自学习使能（FALSE = 4象限参数锁定不更新）
	bHarmEnable     : BOOL := FALSE; // 谐波 ILC 第三层使能（2~5 阶傅里叶系数学习，修被控对象段内非单调响应）
	rHarmLR         : REAL := 0.2;   // 谐波学习率
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
	rAlpha1Cmd     : REAL := 0.25;   // Q1 指令时长占比：上升 + 低于均值
	rAlpha2Cmd     : REAL := 0.25;   // Q2 指令时长占比：上升 + 高于均值
	rAlpha3Cmd     : REAL := 0.25;   // Q3 指令时长占比：下降 + 高于均值
	rAlpha4Cmd     : REAL := 0.25;   // Q4 指令时长占比：下降 + 低于均值
	rAlphaFb       : REAL := 0.5;    // 反馈过均值时长占比 = α2_fb+α3_fb（诊断）
	nWaveType      : INT  := 0;      // 检测到的波形类型：0=检测中, 1=正弦, 2=三角, 3=梯形, 4=矩形, 5=任意波
	rFlatFrac      : REAL;           // 指令峰谷附近时间占比（波形类型判断依据，诊断）
	rSymFrac       : REAL;           // 指令在均值以上时间占比（对称性，诊断：0.5=对称，偏离大→任意波）
END_VAR
VAR
	rMidpoint        : REAL;
	rHalfRange       : REAL;
	rTargetMax       : REAL;
	rTargetMin       : REAL;
	rActualMax       : REAL;
	rActualMin       : REAL;
	rPrevTargetMax   : REAL;
	rPrevTargetMin   : REAL;
	rPrevTargetRange : REAL;
	bNewCyclePrev    : BOOL;
	iIterCount       : INT;
	bVInitialized    : BOOL;         // rVMax/rVMin 是否已用首个有效周期端点初始化
	nUpdateCount     : INT;          // 当前学习窗口已累计周期数
	rPeakErrSum      : REAL;         // 当前窗口峰误差累计
	rValleyErrSum    : REAL;         // 当前窗口谷误差累计
	rErrorSum2       : REAL;
	iErrorCount      : INT;
	iQ1Count         : INT;
	iQ2Count         : INT;
	iQ3Count         : INT;
	iQ4Count         : INT;
	rAlpha1Fb        : REAL;
	rAlpha2Fb        : REAL;
	rAlpha3Fb        : REAL;
	rAlpha4Fb        : REAL;
	rActualPrev      : REAL;
	bFbRising        : BOOL;
	rAlphaSum        : REAL;
	rT1              : REAL;
	rT2              : REAL;
	rT3              : REAL;
	rDelta           : REAL;
	rPhi             : REAL;
	rPhiStd          : REAL;
	rWarpedY         : REAL;
	rSourceTarget    : REAL;         // 仿射映射前的源波形：1/2 用 α 重建，其余直通 rTargetRaw
	rNorm            : REAL;
	rLimit           : REAL;
	iNearExtCount       : INT;       // 暖机期：指令接近峰谷的采样点数（波形类型检测）
	iTargetAboveMidCount: INT;       // 暖机期：指令在均值以上的采样点数（对称性检测）
	iTotalDetectCount   : INT;       // 暖机期：有效检测采样总数
	bWaveDetected       : BOOL;      // 波形类型已检测完成
	// ---- 谐波 ILC 第三层 ----
	// 索引 2..5 对应 2~5 阶谐波；基波（1 阶）交给端点学习层，不在这里学
	aTgtSum         : ARRAY [2..5] OF REAL;   // 当前周期：目标 k 阶余弦内积累加
	bTgtSum         : ARRAY [2..5] OF REAL;   // 当前周期：目标 k 阶正弦内积累加
	aActSum         : ARRAY [2..5] OF REAL;   // 当前周期：反馈 k 阶余弦内积累加
	bActSum         : ARRAY [2..5] OF REAL;   // 当前周期：反馈 k 阶正弦内积累加
	aHarmCorr       : ARRAY [2..5] OF REAL;   // 学到的 cmd k 阶余弦修正系数（持久）
	bHarmCorr       : ARRAY [2..5] OF REAL;   // 学到的 cmd k 阶正弦修正系数（持久）
	iHarmK          : INT;
	rHarmAngle      : REAL;
	rHarmCos        : REAL;
	rHarmSin        : REAL;
	rHarmCorrection : REAL;
	rHarmNorm       : REAL;
	rHarmLimit      : REAL;
	rATgt           : REAL;
	rBTgt           : REAL;
	rAAct           : REAL;
	rBAct           : REAL;
END_VAR
VAR CONSTANT
	// α 边界：原来 0.05/0.70 会让重建波形出现"平台+尖刺"，被控对象跟不上反而塑形出反馈凸起
	// 收紧到 0.10/0.45：最短相位段占 10% 周期（斜率 2.5×正常正弦，液压能跟），最长段不超过 45% 周期
	// 单边占空可达 0.80/0.20，已能覆盖典型液压"上升快下降慢"的占空补偿需求
	ALPHA_Q_MIN       : REAL := 0.10;
	ALPHA_Q_MAX       : REAL := 0.45;
	TWO_PI            : REAL := 6.283185307;
	CYCLES_PER_UPDATE : INT  := 2;
	// 波形类型判断阈值（基于指令在峰谷附近时间占比 rFlatFrac）
	// 三角波~10%，正弦波~28%，梯形波~55%，矩形波~90%
	FLAT_THR_TRI      : REAL := 0.15;  // < 15%   → 三角波
	FLAT_THR_SIN      : REAL := 0.40;  // 15~40%  → 正弦波
	FLAT_THR_TRAP     : REAL := 0.70;  // 40~70%  → 梯形波
	                                   // > 70%   → 矩形波
	// 端点限幅：rVMax / rVMin 距各自目标端点不超过 K * rPrevTargetRange
	// 等价于把幅值/偏置整体放大不超过 (1 + 2K) 倍，防积分饱和
	V_RANGE_LIMIT_K   : REAL := 2.0;
	// 谐波系数限幅：|aHarmCorr[k]|, |bHarmCorr[k]| ≤ HARM_CORR_LIMIT_K * rHalfRange
	// 单阶谐波幅值不超过目标半幅的 30%，防个别频道发散
	HARM_CORR_LIMIT_K : REAL := 0.3;
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
        rPrevTargetMax    := 0.0;
        rPrevTargetMin    := 0.0;
        rPrevTargetRange  := 0.0;
        rAlpha1Cmd        := 0.25;
        rAlpha2Cmd        := 0.25;
        rAlpha3Cmd        := 0.25;
        rAlpha4Cmd        := 0.25;
        rAlphaFb          := 0.5;
        rVMax             := 0.0;
        rVMin             := 0.0;
        rScalePos         := 1.0;
        rScaleNeg         := 1.0;
        bVInitialized     := FALSE;
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
        FOR iHarmK := 2 TO 5 DO
            aHarmCorr[iHarmK] := 0.0;
            bHarmCorr[iHarmK] := 0.0;
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
    iQ1Count       := 0;
    iQ2Count       := 0;
    iQ3Count       := 0;
    iQ4Count       := 0;
    bNewCyclePrev  := FALSE;
    FOR iHarmK := 2 TO 5 DO
        aTgtSum[iHarmK] := 0.0;
        bTgtSum[iHarmK] := 0.0;
        aActSum[iHarmK] := 0.0;
        bActSum[iHarmK] := 0.0;
    END_FOR
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

    // 4 象限 α_fb 计算
    rAlphaSum := INT_TO_REAL(iQ1Count + iQ2Count + iQ3Count + iQ4Count);
    IF rAlphaSum > 0.0 THEN
        rAlpha1Fb := INT_TO_REAL(iQ1Count) / rAlphaSum;
        rAlpha2Fb := INT_TO_REAL(iQ2Count) / rAlphaSum;
        rAlpha3Fb := INT_TO_REAL(iQ3Count) / rAlphaSum;
        rAlpha4Fb := INT_TO_REAL(iQ4Count) / rAlphaSum;
        rAlphaFb  := rAlpha2Fb + rAlpha3Fb;
    END_IF
    iQ1Count := 0; iQ2Count := 0; iQ3Count := 0; iQ4Count := 0;

    // 端点误差：cmd 与 fb 各自一周期的峰、谷直接对比
    rPeakError   := rTargetMax - rActualMax;
    rValleyError := rTargetMin - rActualMin;

    // rMidpoint / rHalfRange 仍由 cmd 计算，供波形检测、α 学习、4 象限分类、诊断输出使用
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
        // ---- 暖机期末：完成波形类型检测 ----
        IF iIterCount = nWarmupCycles AND NOT bWaveDetected AND iTotalDetectCount > 20 THEN
            rFlatFrac := INT_TO_REAL(iNearExtCount)        / INT_TO_REAL(iTotalDetectCount);
            rSymFrac  := INT_TO_REAL(iTargetAboveMidCount) / INT_TO_REAL(iTotalDetectCount);

            IF rSymFrac < 0.35 OR rSymFrac > 0.65 THEN
                nWaveType := 5;      // 任意波：波形不对称
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
        // 暖机期清空学习窗口
        nUpdateCount   := 0;
        rPeakErrSum    := 0.0;
        rValleyErrSum  := 0.0;

    ELSIF NOT bConverged THEN
        // 出暖机首次：用首个有效周期的目标端点初始化 rVMax / rVMin（等效透传）
        IF NOT bVInitialized THEN
            rVMax := rPrevTargetMax;
            rVMin := rPrevTargetMin;
            bVInitialized := TRUE;
        END_IF

        IF iMaxIterations > 0 AND iIterCount >= iMaxIterations THEN
            bConverged := TRUE;
        ELSE
            // ---- α 4 象限自学习（仅正弦/三角，nWaveType=1或2）----
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

            // ---- 端点幅值自学习（加法型，所有波形通用）----
            //   rVMax += LR * (rTargetMax - rActualMax)   // 反馈峰不够高 → 抬虚拟峰
            //   rVMin += LR * (rTargetMin - rActualMin)   // 反馈谷不够低 → 压虚拟谷
            //   优点：上下端点独立学，自然解耦幅值与 DC 偏置；不依赖反馈相对 cmd 中点的位置
            rPeakErrSum   := rPeakErrSum   + rPeakError;
            rValleyErrSum := rValleyErrSum + rValleyError;
            nUpdateCount  := nUpdateCount  + 1;
            IF nUpdateCount >= CYCLES_PER_UPDATE THEN
                rVMax := rVMax + rLearningRate * (rPeakErrSum   / INT_TO_REAL(nUpdateCount));
                rVMin := rVMin + rLearningRate * (rValleyErrSum / INT_TO_REAL(nUpdateCount));

                // 端点限幅：|rVMax-rTargetMax|, |rVMin-rTargetMin| ≤ K*range
                // 作用：物理饱和时防积分饱和，等价于老 SCALE_MAX
                IF rPrevTargetRange > 0.001 THEN
                    rLimit := V_RANGE_LIMIT_K * rPrevTargetRange;
                    IF rVMax > rPrevTargetMax + rLimit THEN rVMax := rPrevTargetMax + rLimit; END_IF
                    IF rVMax < rPrevTargetMax - rLimit THEN rVMax := rPrevTargetMax - rLimit; END_IF
                    IF rVMin > rPrevTargetMin + rLimit THEN rVMin := rPrevTargetMin + rLimit; END_IF
                    IF rVMin < rPrevTargetMin - rLimit THEN rVMin := rPrevTargetMin - rLimit; END_IF
                END_IF
                // 防 vMax/vMin 倒挂（极端误差下可能发生）
                IF rVMax <= rVMin + 0.001 THEN
                    rVMax := rVMin + 0.001;
                END_IF

                rPeakErrSum   := 0.0;
                rValleyErrSum := 0.0;
                nUpdateCount  := 0;
            END_IF

            // ---- 谐波 ILC 第三层自学习（2~5 阶傅里叶系数）----
            // 用累计的内积 (∫signal·cos/sin) 算出本周期目标/反馈各阶谐波系数（×2/N 归一）
            // 更新法则：c_k_cos += LR · (a_k_tgt - a_k_act)，正弦同理
            // 输出时 Σ c_k · 谐波_k(rPhi) 加到 rVirtualTarget
            // 修被控对象段内非单调响应（凸起、台阶），是 4 段 α 无法表达的形状细节
            IF bHarmEnable AND rPrevTargetRange > 0.001 AND iPointsPerCycle > 0 THEN
                rHarmNorm  := 2.0 / INT_TO_REAL(iPointsPerCycle);
                rHarmLimit := HARM_CORR_LIMIT_K * rHalfRange;
                FOR iHarmK := 2 TO 5 DO
                    rATgt := aTgtSum[iHarmK] * rHarmNorm;
                    rBTgt := bTgtSum[iHarmK] * rHarmNorm;
                    rAAct := aActSum[iHarmK] * rHarmNorm;
                    rBAct := bActSum[iHarmK] * rHarmNorm;
                    aHarmCorr[iHarmK] := aHarmCorr[iHarmK] + rHarmLR * (rATgt - rAAct);
                    bHarmCorr[iHarmK] := bHarmCorr[iHarmK] + rHarmLR * (rBTgt - rBAct);
                    IF aHarmCorr[iHarmK] >  rHarmLimit THEN aHarmCorr[iHarmK] :=  rHarmLimit; END_IF
                    IF aHarmCorr[iHarmK] < -rHarmLimit THEN aHarmCorr[iHarmK] := -rHarmLimit; END_IF
                    IF bHarmCorr[iHarmK] >  rHarmLimit THEN bHarmCorr[iHarmK] :=  rHarmLimit; END_IF
                    IF bHarmCorr[iHarmK] < -rHarmLimit THEN bHarmCorr[iHarmK] := -rHarmLimit; END_IF
                END_FOR
            END_IF
        END_IF
    END_IF

    // 重置谐波内积累加器（每周期开始重新积分）
    FOR iHarmK := 2 TO 5 DO
        aTgtSum[iHarmK] := 0.0;
        bTgtSum[iHarmK] := 0.0;
        aActSum[iHarmK] := 0.0;
        bActSum[iHarmK] := 0.0;
    END_FOR

    // 诊断派生量：保留 rScalePos / rScaleNeg 给上位机看
    IF rHalfRange > 0.001 AND bVInitialized THEN
        rScalePos := (rVMax - rMidpoint) / rHalfRange;
        rScaleNeg := (rMidpoint - rVMin) / rHalfRange;
    END_IF

END_IF

// ============================================================
// 每个采样点
// ============================================================

// 周期相位 rPhi（供谐波累加与正弦/三角重建共用）
IF iPointsPerCycle > 0 THEN
    rPhi := INT_TO_REAL(iPointIndex) / INT_TO_REAL(iPointsPerCycle);
ELSE
    rPhi := 0.0;
END_IF
IF rPhi < 0.0 THEN rPhi := 0.0; END_IF
IF rPhi > 1.0 THEN rPhi := 1.0; END_IF

IF rTargetRaw > rTargetMax THEN rTargetMax := rTargetRaw; END_IF
IF rTargetRaw < rTargetMin THEN rTargetMin := rTargetRaw; END_IF
IF rActual > rActualMax THEN rActualMax := rActual; END_IF
IF rActual < rActualMin THEN rActualMin := rActual; END_IF

// ---- 谐波内积累加（仅当 bHarmEnable 开启时执行，省 CPU）----
// 每周期累加 ∫ signal · cos(2π·k·φ) dφ 与 ∫ signal · sin(2π·k·φ) dφ
// 周期边界处归一为本周期的傅里叶系数 a_k, b_k
IF bHarmEnable THEN
    FOR iHarmK := 2 TO 5 DO
        rHarmAngle := TWO_PI * INT_TO_REAL(iHarmK) * rPhi;
        rHarmCos   := COS(rHarmAngle);
        rHarmSin   := SIN(rHarmAngle);
        aTgtSum[iHarmK] := aTgtSum[iHarmK] + rTargetRaw * rHarmCos;
        bTgtSum[iHarmK] := bTgtSum[iHarmK] + rTargetRaw * rHarmSin;
        aActSum[iHarmK] := aActSum[iHarmK] + rActual    * rHarmCos;
        bActSum[iHarmK] := bActSum[iHarmK] + rActual    * rHarmSin;
    END_FOR
END_IF

rErrorSum2  := rErrorSum2 + (rTargetRaw - rActual) * (rTargetRaw - rActual);
iErrorCount := iErrorCount + 1;

// ---- 波形类型检测：统计指令在峰谷附近(|target-mid| > 90%*halfRange)的时间占比 ----
// 从 iIterCount>=1 开始（rMidpoint/rHalfRange 已由第一个周期数据初始化）
IF NOT bWaveDetected AND iIterCount >= 1 AND rHalfRange > 0.001 THEN
    iTotalDetectCount := iTotalDetectCount + 1;
    IF ABS(rTargetRaw - rMidpoint) > 0.9 * rHalfRange THEN
        iNearExtCount := iNearExtCount + 1;
    END_IF
    IF rTargetRaw >= rMidpoint THEN
        iTargetAboveMidCount := iTargetAboveMidCount + 1;
    END_IF
END_IF

// 4 象限反馈采样（仅供 α 学习与诊断；不参与端点学习）
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

// 暖机期 / 首次学习窗未到 / 目标无幅值：直通
IF iIterCount <= nWarmupCycles OR NOT bVInitialized OR rPrevTargetRange < 0.001 THEN
    rVirtualTarget := rTargetRaw;
    rOutput        := 0.0;
    bNewCyclePrev  := bNewCycle;
    RETURN;
END_IF

// ---- 源波形 rSourceTarget ----
//   正弦(1)/三角(2)：用 α 4 段重建标准基底，得到去噪后的 rSourceTarget
//   梯形(3)/矩形(4)/任意波(5)：直接用 rTargetRaw 作源（不假设波形形状）
IF nWaveType = 1 OR nWaveType = 2 THEN
    // rPhi 已在每个采样点开始处算好
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

// ---- 统一仿射重映射 [rPrevTargetMin, rPrevTargetMax] → [rVMin, rVMax] ----
// 形状严格保留，端点替换为学到的虚拟峰/谷
rNorm          := (rSourceTarget - rPrevTargetMin) / rPrevTargetRange;
rVirtualTarget := rVMin + rNorm * (rVMax - rVMin);

// ---- 谐波 ILC 第三层修正叠加（仅 bHarmEnable 开启时） ----
// 形状细节通过 2~5 阶傅里叶系数补到 rVirtualTarget 上
// 注意：基波（1 阶）由端点学习层负责，这里不补，避免与 rVMin/rVMax 冲突
IF bHarmEnable THEN
    rHarmCorrection := 0.0;
    FOR iHarmK := 2 TO 5 DO
        rHarmAngle      := TWO_PI * INT_TO_REAL(iHarmK) * rPhi;
        rHarmCorrection := rHarmCorrection
            + aHarmCorr[iHarmK] * COS(rHarmAngle)
            + bHarmCorr[iHarmK] * SIN(rHarmAngle);
    END_FOR
    rVirtualTarget := rVirtualTarget + rHarmCorrection;
END_IF

rOutput := rVirtualTarget - rTargetRaw;

bNewCyclePrev := bNewCycle;

END_FUNCTION_BLOCK
