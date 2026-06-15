PROGRAM PRG_PressureControl
VAR
	iState : INT := 0; // 0=空闲 1=冲洗排气 3=运行 4=停止中 5=故障 (无 2: 直接控制无需预加压/油缸检查)
	bRunning : BOOL;
	iCmd : INT; // PC命令号 (0~3)
	iCmdPrev : INT; // 上一周期命令号（边沿检测用）
	bCmdChanged : BOOL; // 命令变化标志
	rDt : REAL := 0.001; // 控制周期 1ms
	fbWaveGen_O : FB_WaveformGen;
	fbPID_O : FB_PID;
	fbILC_O : FB_ILC;
	rError_O : REAL; // 油路跟踪误差 (基于 ILC 修正后的目标, MPa)
	rUTotal_O : REAL; // 油路总控制量 (V, 当前就是 PID 输出)
	rUPid_O : REAL; // PID 反馈输出 (V)
	rIlcCorrection_O : REAL; // ILC 学到的指令修正量 (MPa)
	rTargetCorrected_O : REAL; // ILC 修正后的虚拟目标 = rTarget + rIlcCorrection_O (MPa)
	rStopRampKp : REAL := 2.0; // 停止斜坡比例增益 (V/MPa)
	rStopRampErr_O : REAL; // 停止斜坡跟踪误差 (MPa)
	rFlushTimer : REAL; // 冲洗排气计时器(s)
	rFlushDuration : REAL; // 冲洗排气持续时间(s) 缓存
	rFlushOutput : REAL; // 冲洗排气阀门输出(V) 缓存
	rPeakPressure_O : REAL;
	rStopRampVal_O : REAL;
	rActualPMin_O : REAL; // 油路实际PMin
	rStopRampRate : REAL := 5.0; // 卸压速率 (MPa/s)
	bOilCycleResetPrev : BOOL; // 油路循环清零上升沿检测
	Oil_Pressure_Filter : PWControl.LowPassFilter_R;
	tOilFilterTau : TIME; // 油路滤波器时间常数 (从 GVL.PP_Oil_Filter 转换)
	rOilFilterTauMs : REAL; // 中间变量, 带范围保护
	PP_Oil_ActualPressure : REAL;
	nMs1msIdx : INT; // 1ms 采样缓冲写索引 (0..9, 满 10 即在 GVL 发布)
	rPress1msBuf_O : ARRAY[0..9] OF REAL; // 油路 1ms 采样写缓冲 (本地, 写完整 10 个再整体公开)
	// --- ARP1383C 显示包络相位对齐 (整周期互相关估 actual 滞后, 仅显示) ---
	rEnvUpBuf_O : ARRAY[0..1999] OF REAL; // 命令相位上包络环形缓冲 (索引=iPointIndex; 上界=ENV_MAXPPC-1)
	rEnvLoBuf_O : ARRAY[0..1999] OF REAL; // 命令相位下包络环形缓冲
	rEnvActBin_O : ARRAY[0..99] OF REAL;  // 本周期 actual 相位分箱累加 (ENV_NCORR 箱)
	rEnvCmdBin_O : ARRAY[0..99] OF REAL;  // 本周期指令 相位分箱累加
	iEnvBinCnt_O : ARRAY[0..99] OF INT;   // 各分箱采样计数
	rEnvLag_O : REAL;      // 平滑后的 actual 滞后 (周期占比 0~1)
	iEnvKDelay_O : INT;    // 显示延迟 = round(rEnvLag·N) 个采样
	iEnvN_O : INT; iEnvIdx_O : INT; iEnvBin_O : INT; iEnvRd_O : INT; // 互相关临时量
	iEnvK_O : INT; iEnvB_O : INT; iEnvBestK_O : INT;
	rEnvCorr_O : REAL; rEnvBestCorr_O : REAL; rEnvMeanA_O : REAL; rEnvMeanC_O : REAL;
	rEnvLagNew_O : REAL;
END_VAR
VAR CONSTANT
	ENV_MAXPPC    : INT  := 2000; // 显示延迟缓冲容量 (支持最低 ~0.5Hz @1ms; 须与数组上界 1999 一致)
	ENV_NCORR     : INT  := 100;  // 互相关相位分箱数 (要求每周期点数 ≥ 此值; 须与数组上界 99 一致)
	ENV_KMAX      : INT  := 25;   // 互相关搜索的最大滞后 (分箱数, = 25% 周期)
	ENV_LAGSMOOTH : REAL := 0.3;  // 滞后估计的逐周期指数平滑系数

{*
26.01为剂侧产品端低压力传感器
27.01为剂侧产品端15MPa高压力传感器
*}

//剂侧产品端压力 — 默认使用26.01低压传感器(可根据需要切换27.01)
PP_Oil_ActualPressure := GVL_PulsePressure.PP_Dev_Pressure_26_01;

// 滤波时间常数从 GVL 取, 带范围保护 (默认 100ms; ≤1ms 视为旁路, ≥10s 限幅)
rOilFilterTauMs := GVL_PulsePressure.PP_Oil_Filter;
IF rOilFilterTauMs < 1.0     THEN rOilFilterTauMs := 1.0;     END_IF
IF rOilFilterTauMs > 10000.0 THEN rOilFilterTauMs := 10000.0; END_IF
tOilFilterTau := DWORD_TO_TIME(REAL_TO_DWORD(rOilFilterTauMs));

Oil_Pressure_Filter(in:= PP_Oil_ActualPressure, t:= tOilFilterTau);
GVL_PulsePressure.PP_Oil_ActualPressure := Oil_Pressure_Filter.out;

// ============================================================
// 1ms 分辨率压力缓冲 (供上位机以 10ms 通讯周期读取 10 个采样)
// ------------------------------------------------------------
// 本 PRG 在 1ms 任务里跑, 每周期向本地写缓冲追加一个采样;
// 累满 10 个 (即一个完整的 10ms 窗口) 后整体复制到 GVL 数组,
// 上位机 TCP 任务在 10ms 节拍上读到的是上一个窗口的完整 10 点序列, 无撕裂。
// 索引语义: rPress1msBuf_O[0] 是窗口起点 (t-9ms), [9] 是窗口终点 (t-0ms, 最新)
// ============================================================
rPress1msBuf_O[nMs1msIdx] := GVL_PulsePressure.PP_Oil_ActualPressure;
IF nMs1msIdx >= 9 THEN
    GVL_PulsePressure.PP_Oil_ActualPressure_1ms := rPress1msBuf_O;  // 整体快照
    nMs1msIdx := 0;
ELSE
    nMs1msIdx := nMs1msIdx + 1;
END_IF


//方向系数
PWMotion.FPGAData.Axis1.OutputCoefficient := 1;


// ============================================================
// 循环计数清零（上升沿检测，任何状态下都执行）
// PC写入CycleReset=1.0触发清零，清零后PC应写回0.0
// ============================================================
IF GVL_PulsePressure.PP_Oil_CycleReset = 1.0 AND NOT bOilCycleResetPrev THEN
    GVL_PulsePressure.PP_Oil_CyclesDone := 0.0;
    GVL_PulsePressure.PP_TotalCyclesDone := 0.0;
END_IF
bOilCycleResetPrev := (GVL_PulsePressure.PP_Oil_CycleReset = 1.0);

// ============================================================
// PC命令解析
// PP_SysCommand: 0=空闲 1=冲洗排气 2=运行 3=停止
// 命令变化时触发状态切换
// ============================================================
iCmd := REAL_TO_INT(GVL_PulsePressure.PP_SysCommand);
bCmdChanged := (iCmd <> iCmdPrev);
iCmdPrev := iCmd;

// 命令变化时执行状态切换
IF bCmdChanged THEN
    // 进入冲洗或运行前复位所有控制器 (原 InitializeControllers 方法)
    // - fbWaveGen_O 清相位累加器、计数器
    // - fbPID_O 清积分、微分
    // - fbILC_O 清学习历史
    IF iCmd = 1 OR iCmd = 2 THEN
        fbWaveGen_O(bReset := TRUE);
        fbPID_O(bReset := TRUE);
        fbILC_O(bReset := TRUE);
        rPeakPressure_O := 0.0;
        rStopRampVal_O := GVL_PulsePressure.PP_Oil_ActualPressure;
    END_IF

    CASE iCmd OF
        0: // 回空闲
            iState := 0;
        1: // 冲洗排气
            rFlushDuration := GVL_PulsePressure.PP_FlushDuration;
            rFlushOutput := GVL_PulsePressure.PP_FlushValveOutput;
            IF rFlushOutput < 0.5 THEN rFlushOutput := 2.0; END_IF
            IF rFlushOutput > 5.0 THEN rFlushOutput := 5.0; END_IF
            rFlushTimer := 0.0;
            iState := 1;
        2: // 运行（伺服阀直接控制压力，无需油缸到位检查/预加压）
		    rFlushTimer := 0.0;
            iState := 3;
        3: // 停止
            rStopRampVal_O := GVL_PulsePressure.PP_Oil_ActualPressure;
            iState := 4;
    END_CASE
    GVL_PulsePressure.PP_StateReady := 0.0;
END_IF

// ============================================================
// 通道选择（只有油路）
// 始终走剂侧测试: 油路通断阀 10.01/10.03 打开
// 实际硬件驱动由 PRG_DeviceControl（待重写）从 GVL_GPIO 直接读取
// ============================================================



// ============================================================
// 计算实际PMin（直接使用上位机设定值，0即为0MPa）
// ============================================================
rActualPMin_O := GVL_PulsePressure.PP_Oil_MinPressure;
IF rActualPMin_O < 0.0 THEN rActualPMin_O := 0.0; END_IF
IF rActualPMin_O >= GVL_PulsePressure.PP_Oil_TargetPressure THEN
    rActualPMin_O := GVL_PulsePressure.PP_Oil_TargetPressure * 0.9;
END_IF

// ============================================================
// 状态机
// ============================================================
CASE iState OF

// ------------------------------------------------------------
// 状态0: 空闲
// 所有控制输出清零，等待PC写入新命令
// ------------------------------------------------------------
0:
    bRunning := FALSE;
    rUTotal_O := 0.0;
    GVL_PulsePressure.PP_SysState := 0.0;  // 空闲
    GVL_PulsePressure.PP_FlushTimeRemaining := 0.0;
    GVL_PulsePressure.PP_StateReady := 0.0;

// ------------------------------------------------------------
// 状态1: 冲洗排气 — 低压循环排出管路中的空气
// PLC置StateReady=1通知PC冲洗完成，由PC决定何时发下一命令。
// ------------------------------------------------------------
1:
    bRunning := TRUE;
    GVL_PulsePressure.PP_SysState := 1.0;  // 冲洗排气

    // 冲洗计时
    rFlushTimer := rFlushTimer + rDt;
    GVL_PulsePressure.PP_FlushTimeRemaining := rFlushDuration - rFlushTimer;
    IF GVL_PulsePressure.PP_FlushTimeRemaining < 0.0 THEN
        GVL_PulsePressure.PP_FlushTimeRemaining := 0.0;
    END_IF

    // 直接伺服阀控制系统: 冲洗排气期间阀口保持小开度排气, 不做油缸往复
    PWMOTION.FPGAData.Axis1.Output_ManualSet := rFlushOutput * 10;

    // 冲洗时间到 → 置就绪标志，通知 PC 发下一命令
    IF rFlushTimer >= rFlushDuration THEN
        GVL_PulsePressure.PP_FlushTimeRemaining := 0.0;
        GVL_PulsePressure.PP_StateReady := 1.0;
    END_IF
// ------------------------------------------------------------
// 状态3: 运行 — MFF + ILC + PID 复合控制
// 此状态下执行完整的6步控制流水线:
//   1) 波形生成 → 2) 计算跟踪误差 → 3) MFF前馈
//   → 4) ILC前馈 → 5) PID反馈 → 6) 三路叠加
// ============================================================
3:
    bRunning := TRUE;
    GVL_PulsePressure.PP_SysState := 3.0;  // 运行

    // ==================== 油路控制 (ILC 修指令 + PID 反馈) ====================

    // ---- 1. 波形生成 (含 ARP1383C 误差包络) ----
    fbWaveGen_O(
        bEnable       := TRUE,
        rPMin         := rActualPMin_O,
        rPMax         := GVL_PulsePressure.PP_Oil_TargetPressure,
        rFrequency    := GVL_PulsePressure.PP_Oil_Frequency,
        iWaveType     := REAL_TO_INT(GVL_PulsePressure.PP_Oil_WaveType),
        rRisePct      := GVL_PulsePressure.PP_Oil_RisePct,
        rHoldPct      := GVL_PulsePressure.PP_Oil_HoldPct,
        rFallPct      := GVL_PulsePressure.PP_Oil_FallPct,
        rOvershoot    := GVL_PulsePressure.PP_Oil_Overshoot,
        rRingPct      := GVL_PulsePressure.PP_Oil_RingPct,
        rLowDwellPct  := GVL_PulsePressure.PP_Oil_LowDwellPct,
        rDt           := rDt,
        bReset        := FALSE,
        nMffLeadSteps := 0,    // 已移除 MFF, 不再需要超前相位
        rEnvPctP      := GVL_PulsePressure.PP_Oil_EnvPctP
    );

    GVL_PulsePressure.PP_Oil_SetpointPressure := fbWaveGen_O.rTarget;

    // ============================================================
    // ARP1383C 显示包络相位对齐 (仅显示, 不影响 ILC)
    // 实际压力相对指令有稳态滞后; 若把命令相位包络直接送 HMI, "形状/
    // 幅值合格但有滞后"的实际曲线会在边沿被画成越界。这里用整周期互
    // 相关在线估 actual 相对指令的滞后, 把命令相位包络在时间上延迟同
    // 样的量后送 HMI, 使容差带套住实际曲线。ILC 仍用命令相位包络
    // (fbWaveGen_O.rTargetUpper/Lower, 见下方调用), 继续主动消除滞后,
    // 控制行为不变。
    // 算法: 每周期把 actual / 指令按相位分箱 (ENV_NCORR 箱); 周期边界
    //       对两条均值曲线做去均值互相关, 取相关最大的整数滞后 kbest
    //       → 滞后占比 kbest/ENV_NCORR, 逐周期指数平滑; 显示包络 = 命令
    //       相位包络环形缓冲中延迟 round(lag·N) 个采样的值。
    // ============================================================
    iEnvN_O   := fbWaveGen_O.iPointsPerCycle;
    iEnvIdx_O := fbWaveGen_O.iPointIndex;

    IF fbWaveGen_O.bNewCycle THEN
        IF (iEnvN_O >= ENV_NCORR) AND (iEnvN_O <= ENV_MAXPPC) THEN
            // 分箱取均值 + 总体均值 (去均值用)
            rEnvMeanA_O := 0.0;
            rEnvMeanC_O := 0.0;
            FOR iEnvB_O := 0 TO ENV_NCORR - 1 DO
                IF iEnvBinCnt_O[iEnvB_O] > 0 THEN
                    rEnvActBin_O[iEnvB_O] := rEnvActBin_O[iEnvB_O] / INT_TO_REAL(iEnvBinCnt_O[iEnvB_O]);
                    rEnvCmdBin_O[iEnvB_O] := rEnvCmdBin_O[iEnvB_O] / INT_TO_REAL(iEnvBinCnt_O[iEnvB_O]);
                END_IF
                rEnvMeanA_O := rEnvMeanA_O + rEnvActBin_O[iEnvB_O];
                rEnvMeanC_O := rEnvMeanC_O + rEnvCmdBin_O[iEnvB_O];
            END_FOR
            rEnvMeanA_O := rEnvMeanA_O / INT_TO_REAL(ENV_NCORR);
            rEnvMeanC_O := rEnvMeanC_O / INT_TO_REAL(ENV_NCORR);

            // 去均值互相关, 搜索 k = 0..ENV_KMAX (actual 滞后 ⇒ 命令回移 k 对齐)
            iEnvBestK_O    := 0;
            rEnvBestCorr_O := -1.0E30;
            FOR iEnvK_O := 0 TO ENV_KMAX DO
                rEnvCorr_O := 0.0;
                FOR iEnvB_O := 0 TO ENV_NCORR - 1 DO
                    iEnvRd_O := iEnvB_O - iEnvK_O;
                    IF iEnvRd_O < 0 THEN iEnvRd_O := iEnvRd_O + ENV_NCORR; END_IF
                    rEnvCorr_O := rEnvCorr_O
                        + (rEnvActBin_O[iEnvB_O] - rEnvMeanA_O)
                        * (rEnvCmdBin_O[iEnvRd_O] - rEnvMeanC_O);
                END_FOR
                IF rEnvCorr_O > rEnvBestCorr_O THEN
                    rEnvBestCorr_O := rEnvCorr_O;
                    iEnvBestK_O    := iEnvK_O;
                END_IF
            END_FOR

            rEnvLagNew_O := INT_TO_REAL(iEnvBestK_O) / INT_TO_REAL(ENV_NCORR);
            rEnvLag_O    := rEnvLag_O + ENV_LAGSMOOTH * (rEnvLagNew_O - rEnvLag_O);
            iEnvKDelay_O := REAL_TO_INT(rEnvLag_O * INT_TO_REAL(iEnvN_O));
            IF iEnvKDelay_O < 0 THEN iEnvKDelay_O := 0; END_IF
            IF iEnvKDelay_O > iEnvN_O - 1 THEN iEnvKDelay_O := iEnvN_O - 1; END_IF
        ELSE
            rEnvLag_O    := 0.0;   // N 超范围: 退化为命令相位包络
            iEnvKDelay_O := 0;
        END_IF
        // 清空分箱, 开始累计新周期
        FOR iEnvB_O := 0 TO ENV_NCORR - 1 DO
            rEnvActBin_O[iEnvB_O] := 0.0;
            rEnvCmdBin_O[iEnvB_O] := 0.0;
            iEnvBinCnt_O[iEnvB_O] := 0;
        END_FOR
    END_IF

    // 本采样: 写命令相位包络环形缓冲 + 按相位分箱累加 actual/指令; 输出延迟后的显示包络
    IF (iEnvN_O >= ENV_NCORR) AND (iEnvN_O <= ENV_MAXPPC)
       AND (iEnvIdx_O >= 0) AND (iEnvIdx_O < iEnvN_O) THEN
        rEnvUpBuf_O[iEnvIdx_O] := fbWaveGen_O.rTargetUpper;
        rEnvLoBuf_O[iEnvIdx_O] := fbWaveGen_O.rTargetLower;
        iEnvBin_O := REAL_TO_INT(INT_TO_REAL(iEnvIdx_O) * INT_TO_REAL(ENV_NCORR) / INT_TO_REAL(iEnvN_O) - 0.5);
        IF iEnvBin_O < 0 THEN iEnvBin_O := 0; END_IF
        IF iEnvBin_O > ENV_NCORR - 1 THEN iEnvBin_O := ENV_NCORR - 1; END_IF
        rEnvActBin_O[iEnvBin_O] := rEnvActBin_O[iEnvBin_O] + GVL_PulsePressure.PP_Oil_ActualPressure;
        rEnvCmdBin_O[iEnvBin_O] := rEnvCmdBin_O[iEnvBin_O] + fbWaveGen_O.rTarget;
        iEnvBinCnt_O[iEnvBin_O] := iEnvBinCnt_O[iEnvBin_O] + 1;

        iEnvRd_O := iEnvIdx_O - iEnvKDelay_O;
        IF iEnvRd_O < 0 THEN iEnvRd_O := iEnvRd_O + iEnvN_O; END_IF
        GVL_PulsePressure.PP_Oil_TargetUpper := rEnvUpBuf_O[iEnvRd_O];
        GVL_PulsePressure.PP_Oil_TargetLower := rEnvLoBuf_O[iEnvRd_O];
    ELSE
        GVL_PulsePressure.PP_Oil_TargetUpper := fbWaveGen_O.rTargetUpper;
        GVL_PulsePressure.PP_Oil_TargetLower := fbWaveGen_O.rTargetLower;
    END_IF

    GVL_PulsePressure.PP_Oil_EnvPhaseLag  := rEnvLag_O * 100.0;  // actual 滞后 (周期 %), 仅显示遥测

    GVL_PulsePressure.PP_Oil_WavePhase    := fbWaveGen_O.rPhase * 360.0;
    GVL_PulsePressure.PP_Oil_Frequency_FB := GVL_PulsePressure.PP_Oil_Frequency;

    // 周期计数 + 峰值锁存
    IF fbWaveGen_O.bNewCycle THEN
        GVL_PulsePressure.PP_Oil_CyclesDone   := GVL_PulsePressure.PP_Oil_CyclesDone + 1.0;
        GVL_PulsePressure.PP_TotalCyclesDone  := GVL_PulsePressure.PP_TotalCyclesDone + 1.0;
        GVL_PulsePressure.PP_Oil_PeakPressure := rPeakPressure_O;
        rPeakPressure_O := 0.0;
    END_IF
    IF GVL_PulsePressure.PP_Oil_ActualPressure > rPeakPressure_O THEN
        rPeakPressure_O := GVL_PulsePressure.PP_Oil_ActualPressure;
    END_IF

    // ---- 2. ILC 指令修正 (MPa 域) ----
    // 新架构: ILC 不再作为电压前馈分量, 而是学习对目标指令本身的修正量,
    // 然后 PID 跟踪修正后的目标. 这样:
    //   - 单位一致: rOutput 是 MPa 级修正, 加到 rTarget (MPa) 上
    //   - 物理意义清晰: 学到的是 "为了让实际压力达到 rTarget, 阀控制器应该追的虚拟目标"
    //   - 闭环稳定性由 PID 单独保证, ILC 只是循环间慢学习
    // nWaveType 与 FB_WaveformGen 同编码: 0=正弦 / 1=梯形 / 2=水锤波
    // 段宽来自 fbWaveGen_O 已归一化的 rSegRise / rSegRing / rSegHold / rSegFall
    fbILC_O(
        bEnable         := (GVL_PulsePressure.PP_Oil_ILC_Enable >= 0.5),
        rTargetRaw      := fbWaveGen_O.rTarget,
        rActual         := GVL_PulsePressure.PP_Oil_ActualPressure,
        iPointIndex     := fbWaveGen_O.iPointIndex,
        iPointsPerCycle := fbWaveGen_O.iPointsPerCycle,
        bNewCycle       := fbWaveGen_O.bNewCycle,
        bReset          := FALSE,
        iMaxIterations  := REAL_TO_INT(GVL_PulsePressure.PP_Oil_ILC_MaxIter),
        rLearningRate   := GVL_PulsePressure.PP_Oil_ILC_LearningRate,
        iWaveTypeIn     := REAL_TO_INT(GVL_PulsePressure.PP_Oil_WaveType),
        rWHPMaxTarget   := GVL_PulsePressure.PP_Oil_TargetPressure,
        rWHRiseFrac     := fbWaveGen_O.rSegRise,
        rWHRingFrac     := fbWaveGen_O.rSegRing,
        rWHHoldFrac     := fbWaveGen_O.rSegHold,
        rWHFallFrac     := fbWaveGen_O.rSegFall,
        rEnvUpper       := fbWaveGen_O.rTargetUpper,  // ARP1383C 包络: 在包络内停学习, 越界才学习
        rEnvLower       := fbWaveGen_O.rTargetLower
    );
    rIlcCorrection_O := fbILC_O.rOutput;                                 // MPa
    rTargetCorrected_O := fbWaveGen_O.rTarget + rIlcCorrection_O;        // MPa
    GVL_PulsePressure.PP_Oil_ILC_Output    := rIlcCorrection_O;
    GVL_PulsePressure.PP_Oil_ILC_Iteration := INT_TO_REAL(fbILC_O.iIteration);

    // ---- 3. 跟踪误差 (基于 ILC 修正后的目标) ----
    rError_O := rTargetCorrected_O - GVL_PulsePressure.PP_Oil_ActualPressure;
    GVL_PulsePressure.PP_Oil_PressureError := rError_O;

    // ---- 4. PID 反馈 ----
    fbPID_O(
        bEnable := TRUE,
        rError  := rError_O,
        rDt     := rDt,
        bReset  := FALSE,
        rPID_Kp := GVL_PulsePressure.PP_Oil_PID_Kp,
        rPID_Ki := GVL_PulsePressure.PP_Oil_PID_Ki,
        rPID_Kd := GVL_PulsePressure.PP_Oil_PID_Kd
    );
    rUPid_O := fbPID_O.rOutput;
    GVL_PulsePressure.PP_Oil_PID_Output   := rUPid_O;
    GVL_PulsePressure.PP_Oil_PID_Integral := fbPID_O.rPID_I;

    // ---- 5. 阀控电压 = PID 输出 (无 MFF 前馈) ----
    rUTotal_O := rUPid_O;
    IF rUTotal_O >  10.0 THEN rUTotal_O :=  10.0; END_IF
    IF rUTotal_O < -10.0 THEN rUTotal_O := -10.0; END_IF

    PWMOTION.FPGAData.Axis1.Output_ManualSet := rUTotal_O * 10;

    // 检查目标循环数（到达后自动停止）
    IF GVL_PulsePressure.PP_Oil_TargetCycles > 0.0 THEN
        IF GVL_PulsePressure.PP_Oil_CyclesDone >= GVL_PulsePressure.PP_Oil_TargetCycles THEN
            rStopRampVal_O := GVL_PulsePressure.PP_Oil_ActualPressure;
            iState := 4;
        END_IF
    END_IF

// ------------------------------------------------------------
// 状态4: 停止中 — 缓慢卸压
// 停止斜坡机制说明:
//   进入状态4时 (命令 3) rStopRampVal_O 已在 CASE iCmd 中被初始化为当前实际压力。
//   每个控制周期(1ms)按 rStopRampRate=5MPa/s 递减目标值，
//   并用比例控制(rStopRampKp=2.0)跟踪递减目标值。
//   这实现了从当前压力到零的平滑下降，避免直接关闭阀门导致的
//   水锤效应或压力冲击。当实际压力降到0.5MPa以下时认为卸压完成，
//   返回空闲状态(状态0)。
// ------------------------------------------------------------
4:
    GVL_PulsePressure.PP_SysState := 4.0;  // 停止中

    // 油路卸压
    IF GVL_PulsePressure.PP_Oil_ActualPressure > 0.5 THEN
        // 斜坡目标值每ms递减 rStopRampRate*0.001 = 0.005MPa
        // 即5MPa/s的卸压速率
        rStopRampVal_O := rStopRampVal_O - rStopRampRate * rDt;
        IF rStopRampVal_O < 0.0 THEN rStopRampVal_O := 0.0; END_IF
        rStopRampErr_O := rStopRampVal_O - GVL_PulsePressure.PP_Oil_ActualPressure;
        PWMOTION.FPGAData.Axis1.Output_ManualSet := rUTotal_O := rStopRampKp * rStopRampErr_O;
    ELSE
        PWMOTION.FPGAData.Axis1.Output_ManualSet := rUTotal_O := 0.0;
    END_IF

    // 卸压完成 → 置就绪标志，通知PC（PC发命令0回空闲）
    IF GVL_PulsePressure.PP_Oil_ActualPressure < 0.5 THEN
        GVL_PulsePressure.PP_StateReady := 1.0;
    END_IF

// ------------------------------------------------------------
// 状态5: 故障
// 由高压保护触发，所有输出强制清零
// PC发命令0即可恢复到空闲状态
// ------------------------------------------------------------
5:
    rUTotal_O := 0.0;
    PWMOTION.FPGAData.Axis1.Output_ManualSet := 0;
    GVL_PulsePressure.PP_SysState := 5.0;  // 故障

END_CASE

// ============================================================
// 高压保护 — 任何状态下都执行，优先级高于状态机
// 说明: 当实际压力超过设定的限值(HighLimit)时，
//   1) 强制控制输出为0V，并打开回油阀快速泄压
//   2) 立即将状态机切换到故障状态(状态5)
//   此保护在CASE语句之后执行，因此会覆盖任何状态下的控制输出，
//   确保即使运行状态中出现超压也能立即响应。
//   高压保护条件: HighLimit > 0 且 实际压力 > HighLimit
//   HighLimit > 0的检查是为了防止未设定限值时误触发
// ============================================================
IF GVL_PulsePressure.PP_Oil_ActualPressure > GVL_PulsePressure.PP_Oil_HighLimit
   AND GVL_PulsePressure.PP_Oil_HighLimit > 0.0 THEN
    PWMOTION.FPGAData.Axis1.Output_ManualSet := rUTotal_O := 0.0;
	GVL_PulsePressure.PP_Dev_PneValve_YV7 := 1.0;  // 待 PRG_DeviceControl 驱动 YV7 硬件
    iState := 5;
ELSE
	GVL_PulsePressure.PP_Dev_PneValve_YV7 := 0.0;
END_IF

// ============================================================
// 急停保护 — 任何状态下都执行
// 急停时强制切到停止状态(状态4)进行斜坡卸压
// ============================================================
IF GVL_PulsePressure.PP_EmergencyStop = 1.0 AND iState <> 0 AND iState <> 4 AND iState <> 5 THEN
    rStopRampVal_O := GVL_PulsePressure.PP_Oil_ActualPressure;
    iState := 4;
END_IF

// ============================================================
// 输出到全局变量
// ============================================================
// 总控制输出限幅: ±10V 对应伺服阀最大驱动范围
IF rUTotal_O > 10.0 THEN rUTotal_O := 10.0; END_IF
IF rUTotal_O < -10.0 THEN rUTotal_O := -10.0; END_IF

GVL_PulsePressure.PP_Oil_ControlOutput := rUTotal_O;

END_PROGRAM