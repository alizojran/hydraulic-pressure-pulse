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
	bAlphaEnable    : BOOL := TRUE;  // α 自学习使能（仅正弦 8 段; 梯形形态为固定启用的 12 段命令跟踪前馈）
	bTrapShapeEnable : BOOL := FALSE; // [保留/不再门控] 梯形已固定启用 12 段命令跟踪前馈修正(只向上); 仅为接口/Modbus 兼容保留
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
	// 水锤波 3 级端点学习 (除 rVMin/rVMax 外, 额外学习过冲峰指令)
	rVPeak         : REAL;           // 水锤过冲峰指令 (MPa) — 让 actual 抵达 P_OS
	rWHHoldActual  : REAL;           // 上周期 PMax 保压段 actual 均值 (诊断)
	rWHLowActual   : REAL;           // 上周期 PMin 低保持段 actual 均值 (诊断)
	// 梯形包络形态修正 (端点补偿之上叠加; 12 相位段, 把 actual 逐段压回上下包络带内)
	rShapeCorr     : ARRAY [1..12] OF REAL;  // 各相位段 MPa 修正量 (≥0, 只向上; 叠加在端点重映射虚拟目标上)
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
	rShapeOobSum        : ARRAY [1..12] OF REAL;  // 本周期各段命令跟踪误差累加 (指令-实际; >0 实际偏低)
	iShapeCnt           : ARRAY [1..12] OF INT;   // 各段采样计数
	iShapeSeg           : INT;       // 当前相位段 (1..12)
	rShapeErrSeg        : REAL;      // 某段平均命令跟踪误差 (临时)
	rShapeDB            : REAL;      // 形态修正死区 (MPa, = K×量程)
	iFlatDur            : INT;       // 指令在保持平顶连续采样数 (离开平顶清零); 用于稳定段门控
	iSettleThresh       : INT;       // 稳定段门控阈值 = SHAPE_SETTLE_FRAC × iPointsPerCycle
END_VAR
VAR CONSTANT
	ALPHA_Q_MIN       : REAL := 0.04;
	ALPHA_Q_MAX       : REAL := 0.35;
	TWO_PI            : REAL := 6.283185307;
	CYCLES_PER_UPDATE : INT  := 2;
	V_RANGE_LIMIT_K   : REAL := 2.0;
	ENV_INNER_RATIO   : REAL := 0.8;     // 包络门控内缩比例: 用 80% 内包络作为学习门限, 防止 100% 边界震荡
	SHAPE_CORR_LR     : REAL := 0.1;     // 形态修正学习率 (温和: 滞后下逐段修正需慢学防失稳)
	SHAPE_CORR_LIMIT_K : REAL := 0.25;   // 形态修正限幅 = K × 量程 (上限; 下限恒 0)
	SHAPE_CORR_DB_K   : REAL := 0.01;    // 形态修正死区 = K × 量程 (|误差|<死区不修, 防抖)
	SHAPE_SETTLE_FRAC : REAL := 0.1;     // 稳定段门控: 指令在平顶连续保持 > 此比例×周期点数 才修 (放过上升沿后的实际爬升瞬态)
	SHAPE_HOLD_EPS    : REAL := 0.05;    // 平顶判定: rTargetRaw > rPrevTargetMax - K×量程 视为在保持平顶 (排除上升/下降/低保持)
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
    rWHOSPeakActual := -1.0E30;
    rWHHoldSum := 0.0; iWHHoldCount := 0;
    rWHLowSum  := 0.0; iWHLowCount  := 0;
    FOR iBinK := 1 TO 12 DO
        rShapeCorr[iBinK]   := 0.0;
        rShapeOobSum[iBinK] := 0.0;
        iShapeCnt[iBinK]    := 0;
    END_FOR
    iFlatDur       := 0;
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

            // 端点幅值自学习（加法型, 仅正弦: 供 α 重映射后的仿射缩放）
            //   梯形改用逐段命令跟踪、水锤用专用 3 级学习, 均跳过此通用路径
            IF nWaveType = 0 THEN
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
                // 累加器复位已上提到 bNewCycle 入口 (无论是否学习都需要复位)
            END_IF
        END_IF
    END_IF

    // ============================================================
    // 梯形形态修正更新 (每个暖机后周期都跑; 脱离 bConverged 与包络门控, 仅自死区门控)
    //   逐段命令跟踪前馈, 只向上, 仅作用于"保持稳定段"(累加门控见 per-sample 段):
    //     实际低于指令(误差>0) → 抬高该保持段把实际顶回公差带 (治 P 控稳态下垂);
    //     实际高于指令(误差<0) → 该段触底归 0, 不做无效下压(被动泄压压不下去);
    //     |误差|<死区 → 保持已学修正 (防抖)。
    //   上升/下降沿与早段瞬态不累加 → 修正量恒为 0, 不参与 → 放过滞后引起的 windup。
    //   不随 iMaxIterations 收敛冻结 → 稳态下垂可持续上修; 与包络门控无关 → 带内也修。
    // ============================================================
    IF nWaveType = 1 AND iIterCount > nWarmupCycles THEN
        rLimit   := SHAPE_CORR_LIMIT_K * rPrevTargetRange;
        rShapeDB := SHAPE_CORR_DB_K   * rPrevTargetRange;
        FOR iBinK := 1 TO 12 DO
            IF iShapeCnt[iBinK] > 0 THEN
                rShapeErrSeg := rShapeOobSum[iBinK] / INT_TO_REAL(iShapeCnt[iBinK]);
                IF rShapeErrSeg > rShapeDB OR rShapeErrSeg < -rShapeDB THEN
                    rShapeCorr[iBinK] := rShapeCorr[iBinK] + SHAPE_CORR_LR * rShapeErrSeg;
                    IF rShapeCorr[iBinK] < 0.0    THEN rShapeCorr[iBinK] := 0.0;    END_IF
                    IF rShapeCorr[iBinK] > rLimit THEN rShapeCorr[iBinK] := rLimit; END_IF
                END_IF
            END_IF
        END_FOR
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

// --------- 梯形形态修正 per-segment 命令跟踪误差累加 (仅保持稳定段) ---------
// 稳定段门控: 指令须在平顶 (rTargetRaw 接近 rPrevTargetMax) 连续保持 > iSettleThresh 采样才累加。
//   放过 (a) 上升/下降沿与低保持段; (b) 上升沿后实际仍在爬升的早段瞬态 —— 后者在传输滞后下
//   会让逐段修正 windup/过冲(把指令推到上包络外、实际冲出公差带, 即此前的 M 形)。
//   只修真正稳态下垂的后保持段, 配合温和学习率/限幅, 逐段修正即稳定。
IF nWaveType = 1 AND iIterCount >= 1 THEN
    iSettleThresh := REAL_TO_INT(SHAPE_SETTLE_FRAC * INT_TO_REAL(iPointsPerCycle));
    IF rPrevTargetRange > 0.001 AND rTargetRaw > rPrevTargetMax - SHAPE_HOLD_EPS * rPrevTargetRange THEN
        iFlatDur := iFlatDur + 1;       // 在保持平顶
    ELSE
        iFlatDur := 0;                  // 离开平顶 (上升/下降/低保持) → 清零
    END_IF
    IF iFlatDur > iSettleThresh THEN
        iShapeSeg := REAL_TO_INT(rPhi * 12.0);
        IF iShapeSeg < 0  THEN iShapeSeg := 0;  END_IF
        IF iShapeSeg > 11 THEN iShapeSeg := 11; END_IF
        iShapeSeg := iShapeSeg + 1;
        rShapeOobSum[iShapeSeg] := rShapeOobSum[iShapeSeg] + (rTargetRaw - rActual);  // 指令-实际; >0=实际偏低
        iShapeCnt[iShapeSeg]    := iShapeCnt[iShapeSeg] + 1;
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
    // 梯形：逐段叠加 rShapeCorr (只向上, 仅保持稳定段非零), 不做端点仿射重映射 → 提前返回。
    //   端点仿射重映射从含瞬态过冲的峰/谷极值反学 → 把整段指令往下压(负输出),
    //   既无法塑形保持段下垂, 又在谷段做无效下压(被动泄压压不下去)。
    //   rShapeCorr 只在保持稳定段学习(见 per-sample 门控), 上升/下降/早段瞬态恒 0;
    //   故 rVirtualTarget = 指令 + 该段修正(≥0) → rOutput 恒 ≥ 0, 只抬保持平顶。
    iShapeSeg := REAL_TO_INT(rPhi * 12.0);
    IF iShapeSeg < 0  THEN iShapeSeg := 0;  END_IF
    IF iShapeSeg > 11 THEN iShapeSeg := 11; END_IF
    rVirtualTarget := rTargetRaw + rShapeCorr[iShapeSeg + 1];
    rOutput        := rVirtualTarget - rTargetRaw;
    bNewCyclePrev  := bNewCycle;
    RETURN;

ELSE
    rSourceTarget := rTargetRaw;
END_IF

// 仿射重映射 [tMin, tMax] → [vMin, vMax] (正弦 / 兜底)
rNorm          := (rSourceTarget - rPrevTargetMin) / rPrevTargetRange;
rVirtualTarget := rVMin + rNorm * (rVMax - rVMin);

rOutput := rVirtualTarget - rTargetRaw;

bNewCyclePrev := bNewCycle;

END_FUNCTION_BLOCK
