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
	rAlphaLR        : REAL := 0.2;   // α 学习率（正弦 8 段、梯形 12 段）
	bAlphaEnable    : BOOL := TRUE;  // α 自学习使能（仅正弦 8 段; 梯形形态由 bTrapShapeEnable 控制）
	bPlatCorrEnable : BOOL := TRUE;  // 平台 2 段幅值修正使能（仅梯形, 且需 bTrapShapeEnable=TRUE 才生效）
	bTrapShapeEnable : BOOL := FALSE; // 梯形形态补偿使能(α-12 时序重映射 + 平台幅值修正); 默认 FALSE = 仅端点补偿(rVMin/rVMax 重映射)
	nWarmupCycles   : INT  := 3;     // 暖机周期数：前N个周期透传不修正
	iWaveTypeIn     : INT  := 0;     // 波形类型 (与 FB_WaveformGen 同编码): 0=正弦 1=梯形 2=水锤波; 其他值按正弦处理
	rWHPMaxTarget   : REAL := 0.0;   // [水锤] PMax 保压段目标 (MPa); 用于 hold 段幅值修正学习
	rWHRiseFrac     : REAL := 0.05;  // [水锤] 段 1: 过冲上升段归一化相位宽 (= 上游 FB_WaveformGen 归一化后的 rR)
	rWHRingFrac     : REAL := 0.07;  // [水锤] 段 2: 过冲衰减段归一化相位宽 (= rRing)
	rWHHoldFrac     : REAL := 0.35;  // [水锤] 段 3: PMax 保压段归一化相位宽 (= rH)
	rWHFallFrac     : REAL := 0.05;  // [水锤] 段 4: 下降段归一化相位宽 (= rF); 段 5 (低保持) = 1 - 上述 4 段
	rEnvUpper       : REAL := 0.0;   // ARP1383C 包络上限 (MPa); 内部用 ENV_INNER_RATIO (默认 80%) 内缩为学习门控阈值; 0 ⇒ 禁用门控 (每周期都学习)
	rEnvLower       : REAL := 0.0;   // ARP1383C 包络下限 (MPa)
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
	// 8 段 α 时长占比（正弦）
	rAlphaCmd      : ARRAY [1..8] OF REAL;
	rAlphaTgt      : ARRAY [1..8] OF REAL;
	rAlphaFb       : ARRAY [1..8] OF REAL;
	// 12 段 α 时长占比（梯形：底平 / 升 1..5 / 顶平 / 降 1..5）
	rAlpha12Cmd    : ARRAY [1..12] OF REAL;
	rAlpha12Tgt    : ARRAY [1..12] OF REAL;
	rAlpha12Fb     : ARRAY [1..12] OF REAL;
	// 梯形：平台分 2 段幅值修正（MPa，叠加在 vMin/vMax 上）
	rPlatBotA      : REAL;
	rPlatBotB      : REAL;
	rPlatTopA      : REAL;
	rPlatTopB      : REAL;
	// 水锤波 3 级端点学习 (除 rVMin/rVMax 外, 额外学习过冲峰指令)
	rVPeak         : REAL;           // 水锤过冲峰指令 (MPa) — 让 actual 抵达 P_OS
	rWHHoldActual  : REAL;           // 上周期 PMax 保压段 actual 均值 (诊断)
	rWHLowActual   : REAL;           // 上周期 PMin 低保持段 actual 均值 (诊断)
	// 梯形包络形态修正 (端点补偿之上叠加; 12 相位段, 把 actual 逐段压回上下包络带内)
	rShapeCorr     : ARRAY [1..12] OF REAL;  // 各相位段 MPa 修正量 (叠加在端点重映射虚拟目标上)
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
	bAnyOver100        : BOOL;       // 本周期内 actual 是否曾越出 100% 包络 (硬边界)
	bAnyOver80         : BOOL;       // 本周期内 actual 是否曾越出 80% 内包络 (含 100% 越界蕴含)
	bLearningArmed     : BOOL;       // 学习态: TRUE = 正在迭代, FALSE = 已收敛停学 (跨周期保持)
	bDoLearnNow        : BOOL;       // 本周期是否执行学习 (在 bNewCycle 边界捕获)
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
	// 波形类型 (每次调用由 iWaveTypeIn 整定: 非 0/1/2 按正弦处理)
	nWaveType           : INT;
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
	rEnvInUp            : REAL;       // 内缩包络上限 = rTargetRaw + ENV_INNER_RATIO * (rEnvUpper - rTargetRaw)
	rEnvInLo            : REAL;       // 内缩包络下限
	// 梯形包络形态修正状态
	rShapeOobSum        : ARRAY [1..12] OF REAL;  // 本周期各段越界量累加 (越上包络为负, 越下包络为正)
	iShapeCnt           : ARRAY [1..12] OF INT;   // 各段采样计数
	iShapeSeg           : INT;       // 当前相位段 (1..12)
	rShapeOob           : REAL;      // 当前采样越界量
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
	V_RANGE_LIMIT_K   : REAL := 2.0;
	ENV_INNER_RATIO   : REAL := 0.8;     // 包络门控内缩比例: 用 80% 内包络作为学习门限, 防止 100% 边界震荡
	SHAPE_CORR_LR     : REAL := 0.3;     // 包络形态修正学习率
	SHAPE_CORR_LIMIT_K : REAL := 0.6;    // 包络形态修正限幅 = K × 量程
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
        bVInitialized     := FALSE;
        rActualPrev       := 0.0;
        rTargetPrev       := 0.0;
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
    FOR iBinK := 1 TO 12 DO
        rShapeCorr[iBinK]   := 0.0;
        rShapeOobSum[iBinK] := 0.0;
        iShapeCnt[iBinK]    := 0;
    END_FOR
    bNewCyclePrev  := FALSE;
    bAnyOver100    := FALSE;
    bAnyOver80     := FALSE;
    bLearningArmed := FALSE;          // 复位后从"未学习"开始, 任何 100% 越界会触发首次 arming
    bDoLearnNow    := FALSE;
    IF NOT bEnable THEN
        RETURN;
    END_IF
END_IF

IF iPointsPerCycle < 10 THEN
    rOutput := 0.0; rVirtualTarget := 0.0; RETURN;
END_IF

// ============================================================
// 波形类型整定 (与 FB_WaveformGen 的 iWaveType 同编码)
//   0 = 正弦 (Fig.3) / 1 = 梯形 (Fig.1) / 2 = 水锤波 (Fig.2)
//   其他值与 FB_WaveformGen 的 ELSE 分支保持一致, 按正弦处理
// ============================================================
nWaveType := iWaveTypeIn;
IF nWaveType < 0 OR nWaveType > 2 THEN nWaveType := 0; END_IF

// ============================================================
// 新周期边界
// ============================================================
IF bNewCycle AND NOT bNewCyclePrev THEN

    // 包络门控 (迟滞型):
    //   - 进学习态: disarmed → armed, 触发条件 = 任一采样越 100% 包络
    //   - 出学习态: armed → disarmed, 触发条件 = 整个周期所有采样都在 80% 内包络
    //   - 不对称阈值避免临界处的 on/off 震荡。
    //   - 包络未配置 (rEnvUpper <= rEnvLower) 时退化为"每周期都学习", 兼容旧调用。
    IF nWaveType = 2 THEN
        // 水锤波: Fig.2 包络含大段自由窗(过冲+ring 窗、下降窗), 不能当学习门控
        // (actual 总在宽带内 → 永不触发 → 3 级端点学习不执行 → 无输出)。
        // 改为始终学习: 端点设定点(P_OS/PMax/PMin)误差为 P 型, 抵达后自然趋零,
        // iMaxIterations 仍可停学。
        bDoLearnNow := TRUE;
    ELSIF rEnvUpper <= rEnvLower THEN
        bDoLearnNow := TRUE;                 // 门控禁用 → 全部周期都学
    ELSIF bLearningArmed THEN
        // 当前在学习态: 本周期照学; 若 actual 已"全部回到 80% 内"则下周期起停学
        bDoLearnNow := TRUE;
        IF NOT bAnyOver80 THEN
            bLearningArmed := FALSE;         // 出学习态
        END_IF
    ELSE
        // 当前不在学习态: 若本周期任一采样越 100% 则进入学习态并立即学; 否则继续旁观
        IF bAnyOver100 THEN
            bLearningArmed := TRUE;          // 进学习态
            bDoLearnNow := TRUE;
        ELSE
            bDoLearnNow := FALSE;
        END_IF
    END_IF
    // 重置本周期累积标志
    bAnyOver100 := FALSE;
    bAnyOver80  := FALSE;

    // (水锤累加器复位下移到学习之后, 见 bNewCycle 块尾; 否则会"复位早于学习读取")

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
        ELSIF bDoLearnNow THEN  // 包络越界才学习 (本周期内 actual 曾越出 rEnvLower..rEnvUpper)
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
            IF bTrapShapeEnable AND nWaveType = 1 THEN
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
            IF bTrapShapeEnable AND bPlatCorrEnable AND nWaveType = 1 THEN
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

            // 梯形包络形态修正: 12 段, 把 actual 逐段压回上下包络带内 (带内→不变=保持已学修正)
            IF bTrapShapeEnable AND nWaveType = 1 THEN
                rLimit := SHAPE_CORR_LIMIT_K * rPrevTargetRange;
                FOR iBinK := 1 TO 12 DO
                    IF iShapeCnt[iBinK] > 0 THEN
                        rShapeCorr[iBinK] := rShapeCorr[iBinK]
                            + SHAPE_CORR_LR * (rShapeOobSum[iBinK] / INT_TO_REAL(iShapeCnt[iBinK]));
                        IF rShapeCorr[iBinK] >  rLimit THEN rShapeCorr[iBinK] :=  rLimit; END_IF
                        IF rShapeCorr[iBinK] < -rLimit THEN rShapeCorr[iBinK] := -rLimit; END_IF
                    END_IF
                END_FOR
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
                // 累加器复位已上提到 bNewCycle 入口 (无论是否学习都需要复位)
            END_IF
        END_IF
    END_IF

    // 缓存梯形平台 phase 边界（per-sample 与输出阶段共用）
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

    // 水锤段累加器复位 (放在学习之后: 本周期学习已读完上一周期的累加值, 现清零供新周期累加)
    IF nWaveType = 2 THEN
        rWHOSPeakActual := -1.0E30;
        rWHHoldSum := 0.0; iWHHoldCount := 0;
        rWHLowSum  := 0.0; iWHLowCount  := 0;
    END_IF

    // 梯形形态修正累加器复位 (同样放在学习之后)
    IF nWaveType = 1 THEN
        FOR iBinK := 1 TO 12 DO
            rShapeOobSum[iBinK] := 0.0;
            iShapeCnt[iBinK]    := 0;
        END_FOR
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

// 包络越界跟踪 (迟滞门控): 同步收集 100% 与 80% 两套越界标志, 由 bNewCycle 边界决定 arm/disarm
//   bAnyOver100: 至少一个采样越出 ARP1383C 100% 包络 (硬边界, 触发 arm)
//   bAnyOver80:  至少一个采样越出 80% 内包络 (软边界, 用于判定 disarm 条件: 全周期 ≤ 80%)
IF rEnvUpper > rEnvLower THEN
    rEnvInUp := rTargetRaw + ENV_INNER_RATIO * (rEnvUpper - rTargetRaw);
    rEnvInLo := rTargetRaw - ENV_INNER_RATIO * (rTargetRaw - rEnvLower);
    IF (rActual > rEnvUpper) OR (rActual < rEnvLower) THEN
        bAnyOver100 := TRUE;   // 100% 越界 → 蕴含 80% 越界
        bAnyOver80  := TRUE;
    ELSIF (rActual > rEnvInUp) OR (rActual < rEnvInLo) THEN
        bAnyOver80  := TRUE;   // 仅 80% 越界 (在 80%~100% 之间)
    END_IF
END_IF

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

// 方向检测
IF rTargetRaw >= rTargetPrev THEN bTgtRising := TRUE; ELSE bTgtRising := FALSE; END_IF
rTargetPrev := rTargetRaw;
IF rActual   >= rActualPrev THEN bFbRising  := TRUE; ELSE bFbRising  := FALSE; END_IF
rActualPrev := rActual;

// --------- 8 段分箱（正弦）---------
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

// --------- 12 段分箱（梯形）---------
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

// --------- 梯形包络形态修正 per-segment 越界累加 (12 等相位段) ---------
IF bTrapShapeEnable AND nWaveType = 1 AND iIterCount >= 1 AND rEnvUpper > rEnvLower THEN
    iShapeSeg := REAL_TO_INT(rPhi * 12.0);
    IF iShapeSeg < 0  THEN iShapeSeg := 0;  END_IF
    IF iShapeSeg > 11 THEN iShapeSeg := 11; END_IF
    iShapeSeg := iShapeSeg + 1;
    IF rActual > rEnvUpper THEN
        rShapeOob := rEnvUpper - rActual;      // 越上包络 → 负 (压低该段)
    ELSIF rActual < rEnvLower THEN
        rShapeOob := rEnvLower - rActual;      // 越下包络 → 正 (抬高该段)
    ELSE
        rShapeOob := 0.0;                       // 带内 → 不修
    END_IF
    rShapeOobSum[iShapeSeg] := rShapeOobSum[iShapeSeg] + rShapeOob;
    iShapeCnt[iShapeSeg]    := iShapeCnt[iShapeSeg] + 1;
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
//   正弦(0) → α 8 段相位重映射后重建
//   水锤(2) → 5 段直接重构并提前返回
//   梯形(1) → α 12 段相位重映射 + 梯形模板
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
    //   段 4+5: rVMin                      (阶跃下降: 指令直落无斜率 + PMin 低保持)
    IF rPhi < rWH_T1 THEN
        rVirtualTarget := rVPeak;
    ELSIF rPhi < rWH_T2 THEN
        rVirtualTarget := rVMax;
    ELSIF rPhi < rWH_T3 THEN
        rVirtualTarget := rVMax;
    ELSE
        rVirtualTarget := rVMin;
    END_IF
    rOutput := rVirtualTarget - rTargetRaw;
    bNewCyclePrev := bNewCycle;
    RETURN;

ELSIF nWaveType = 1 THEN
    // 梯形：端点补偿(下方仿射重映射到 [vMin,vMax]); 形态补偿改为末尾按上下包络逐段叠加 rShapeCorr
    // 注: 下面 IF FALSE 内为(已停用)的 α-12 时序重映射, 大滞后下会把虚拟指令推移≈半周期致反相, 不再使用
    IF FALSE THEN
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
        rSourceTarget := rTargetRaw;   // 仅端点补偿: 保留原指令形状, 由下方仿射重映射缩放到 [vMin,vMax]
    END_IF

ELSE
    rSourceTarget := rTargetRaw;
END_IF

// 仿射重映射 [tMin, tMax] → [vMin, vMax]
rNorm          := (rSourceTarget - rPrevTargetMin) / rPrevTargetRange;
rVirtualTarget := rVMin + rNorm * (rVMax - rVMin);

// 梯形包络形态修正: 端点重映射之上, 按当前相位段叠加 rShapeCorr (把 actual 逐段压回上下包络带内)
// 纯幅值修正, 无相位重映射 → 结构上不会出现 α-12 那种半周期反相
IF bTrapShapeEnable AND (nWaveType = 1) THEN
    iShapeSeg := REAL_TO_INT(rPhi * 12.0);
    IF iShapeSeg < 0  THEN iShapeSeg := 0;  END_IF
    IF iShapeSeg > 11 THEN iShapeSeg := 11; END_IF
    rVirtualTarget := rVirtualTarget + rShapeCorr[iShapeSeg + 1];
END_IF

rOutput := rVirtualTarget - rTargetRaw;

bNewCyclePrev := bNewCycle;

END_FUNCTION_BLOCK
