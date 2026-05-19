PROGRAM PRG_PressureControl
VAR
	iState : INT := 0; // 0=空闲 1=冲洗排气 2=预加压 3=运行 4=停止中 5=故障
	bRunning : BOOL;
	iCmd : INT; // PC命令号 (0~3)
	iCmdPrev : INT; // 上一周期命令号（边沿检测用）
	bCmdChanged : BOOL; // 命令变化标志
	rCylinderPos : REAL; // 当前激活通道的油缸位置(mm)
	rDt : REAL := 0.001; // 控制周期 1ms
	fbWaveGen_W : FB_WaveformGen;
	fbPID_W : FB_HydraulicPID;
	fbILC_W : FB_ILC;
	fbWaveGen_O : FB_WaveformGen;
	fbPID_O : FB_HydraulicPID;
	fbILC_O : FB_ILC;
	rError_W : REAL; // 水路跟踪误差
	rError_O : REAL; // 油路跟踪误差
	rUTotal_W : REAL; // 水路总控制量
	rUTotal_O : REAL; // 油路总控制量
	rUIlc_W : REAL; // 水路 ILC 修正量 (V)，仅诊断不参与汇总
	rUPid_W : REAL; // 水路 PID 反馈分量 (V)
	rTargetCorrected_W : REAL; // 水路 ILC 修正后的目标 (MPa)
	rUIlc_O : REAL;
	rUPid_O : REAL;
	rTargetCorrected_O : REAL;
	bWaterActive : BOOL; // 水路激活
	bOilActive : BOOL; // 油路激活
	rPrePressTarget_W : REAL; // 水路预加压目标
	rPrePressTarget_O : REAL;
	rPrePressKp : REAL := 2.0; // 预加压比例增益
	rPrePressErr_W : REAL;
	rPrePressErr_O : REAL;
	rFlushTimer : REAL; // 冲洗排气计时器(s)
	rFlushDuration : REAL; // 冲洗排气持续时间(s) 缓存
	rFlushOutput : REAL; // 冲洗排气阀门输出(V) 缓存
	rPeakPressure_W : REAL;
	rPeakPressure_O : REAL;
	rStopRampVal_W : REAL;
	rStopRampVal_O : REAL;
	rActualPMin_W : REAL; // 水路实际PMin
	rActualPMin_O : REAL; // 油路实际PMin
	rStopRampRate : REAL := 5.0; // 卸压速率 (MPa/s)
	bCommitPrev : BOOL; // 上升沿检测
	bWaterCycleResetPrev : BOOL; // 水路循环清零上升沿检测
	bOilCycleResetPrev : BOOL; // 油路循环清零上升沿检测
	bFlushDirection : BOOL; // 冲洗排气往复方向 FALSE=正向 TRUE=反向
	rFlushToggleTimer : REAL; // 冲洗排气往复切换计时器(s)
	nPts : INT; // 波形上传点数
	iCh : INT; // 波形上传通道
	Water_Pressure_Filter : PWControl.LowPassFilter_R;
	PP_Water_ActualPressure : REAL;
	Oil_Pressure_Filter : PWControl.LowPassFilter_R;
	PP_Oil_ActualPressure : REAL;
	bBurstMode : BOOL; // 当前周期是否为爆破模式 (TestMode=2 或 3)
	// 爆破: 水路
	iBurstPhase_W : INT; // 0=升压 1=保压 2=续升 3=已爆破
	rBurstSetpoint_W : REAL; // 给定压力(MPa)
	rBurstRate1_W : REAL; // 升压速率(MPa/s)，取自 PP_Water_RiseRate（升压+续升共用）
	rBurstHoldTimer_W : REAL; // 保压计时器(s)
	rBurstPeak_W : REAL; // 运行最大压力(MPa)
	rBurstPrev_W : REAL; // 上周期压力(MPa)，用于跌速判定
	rBurstDropRate_W : REAL; // 当前压力跌速(MPa/s)
	// 爆破: 油路
	iBurstPhase_O : INT;
	rBurstSetpoint_O : REAL;
	rBurstRate1_O : REAL;
	rBurstHoldTimer_O : REAL;
	rBurstPeak_O : REAL;
	rBurstPrev_O : REAL;
	rBurstDropRate_O : REAL;
	// 爆破检测参数
	rBurstDropPct : REAL := 0.7;   // 跌至峰值×0.7以下判定爆破
	rBurstDropRateLim : REAL := -20.0; // 跌速门限(MPa/s)，低于此值判定爆破
END_VAR
{*
25.01为水侧产品端压力
  
26.01为剂侧产品端低压力传感器，用于低压测试
27.01为剂侧产品端15MPa压力传感器，用于爆破实验
*}

//水侧产品端压力
PP_Water_ActualPressure := PRG_DeviceControl.toPC_Pressure_25_01;
Water_Pressure_Filter(in:= PP_Water_ActualPressure,t:= T#20MS);
GVL_PulsePressure.PP_Water_ActualPressure := Water_Pressure_Filter.out;
{*
   测试模式 0=水路脉冲 1=油路(剂侧)脉冲 2=水路爆破 3=油路(剂侧)爆破
*}

//剂侧产品端压力
IF PP_TestMode=1 THEN 
  PP_Oil_ActualPressure:=PRG_DeviceControl.toPC_Pressure_26_01; //低压
ELSIF PP_TestMode=3 THEN
   PP_Oil_ActualPressure:=PRG_DeviceControl.toPC_Pressure_27_01; //高压
END_IF
Oil_Pressure_Filter(in:= PP_Oil_ActualPressure,t:= T#50MS);
GVL_PulsePressure.PP_Oil_ActualPressure := Oil_Pressure_Filter.out;


//方向系数
PWMotion.FPGAData.Axis1.OutputCoefficient := 1;


// ============================================================
// 自定义波形上传处理 (任何状态下都执行)
// 上升沿检测：当Upload_Commit从0→1时触发加载
// 加载后状态回写：1=成功 2=点数非法
// ============================================================
IF GVL_PulsePressure.PP_WaveUpload_Commit = 1.0 AND NOT bCommitPrev THEN
    nPts := REAL_TO_INT(GVL_PulsePressure.PP_WaveUpload_NumPoints);
    iCh  := REAL_TO_INT(GVL_PulsePressure.PP_WaveUpload_Channel);

    IF nPts >= 2 AND nPts <= 2000 THEN
        IF iCh = 0 THEN
            // 水路
            fbWaveGen_W.LoadCustomWaveform(
                pData   := ADR(GVL_PulsePressure.PP_WaveUpload_Data),
                nPoints := nPts
            );
        ELSE
            // 油路
            fbWaveGen_O.LoadCustomWaveform(
                pData   := ADR(GVL_PulsePressure.PP_WaveUpload_Data),
                nPoints := nPts
            );
        END_IF
        GVL_PulsePressure.PP_WaveUpload_Status := 1.0;  // 已加载
    ELSE
        GVL_PulsePressure.PP_WaveUpload_Status := 2.0;  // 错误
    END_IF
END_IF
bCommitPrev := (GVL_PulsePressure.PP_WaveUpload_Commit = 1.0);


// ============================================================
// 循环计数清零（上升沿检测，任何状态下都执行）
// PC写入CycleReset=1.0触发清零，清零后PC应写回0.0
// ============================================================
IF GVL_PulsePressure.PP_Water_CycleReset = 1.0 AND NOT bWaterCycleResetPrev THEN
    GVL_PulsePressure.PP_Water_CyclesDone := 0.0;
    GVL_PulsePressure.PP_TotalCyclesDone := 0.0;
END_IF
bWaterCycleResetPrev := (GVL_PulsePressure.PP_Water_CycleReset = 1.0);

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
    CASE iCmd OF
        0: // 回空闲
            iState := 0;
        1: // 冲洗排气
            InitializeControllers();
            rFlushDuration := GVL_PulsePressure.PP_FlushDuration;
            rFlushOutput := GVL_PulsePressure.PP_FlushValveOutput;
            IF rFlushOutput < 0.5 THEN rFlushOutput := 2.0; END_IF
            IF rFlushOutput > 5.0 THEN rFlushOutput := 5.0; END_IF
            rFlushTimer := 0.0;
            iState := 1;
        2: // 运行（自动序列：油缸检查→预加压→运行）
		    rFlushTimer := 0.0;
            InitializeControllers();
            // 爆破模式：清零结果与相位，重新开始一次爆破试验
            IF GVL_PulsePressure.PP_TestMode = 2.0 THEN
                iBurstPhase_W := 0;
                rBurstSetpoint_W := 0.0;
                rBurstHoldTimer_W := 0.0;
                rBurstPeak_W := 0.0;
                rBurstPrev_W := GVL_PulsePressure.PP_Water_ActualPressure;
                rBurstDropRate_W := 0.0;
                GVL_PulsePressure.PP_Water_BurstResult := 0.0;
                GVL_PulsePressure.PP_Water_BurstPhase := 0.0;
            ELSIF GVL_PulsePressure.PP_TestMode = 3.0 THEN
                iBurstPhase_O := 0;
                rBurstSetpoint_O := 0.0;
                rBurstHoldTimer_O := 0.0;
                rBurstPeak_O := 0.0;
                rBurstPrev_O := GVL_PulsePressure.PP_Oil_ActualPressure;
                rBurstDropRate_O := 0.0;
                GVL_PulsePressure.PP_Oil_BurstResult := 0.0;
                GVL_PulsePressure.PP_Oil_BurstPhase := 0.0;
            END_IF
            iState := 2;  // 先进入预加压，内部自动推进到运行
        3: // 停止
            rStopRampVal_W := GVL_PulsePressure.PP_Water_ActualPressure;
            rStopRampVal_O := GVL_PulsePressure.PP_Oil_ActualPressure;
            iState := 4;
    END_CASE
    GVL_PulsePressure.PP_StateReady := 0.0;
END_IF

// ============================================================
// 通道选择（互斥：水路和油路不能同时激活）
// 互斥逻辑说明:
//   TestMode=0 → 水路脉冲 → bWaterActive=TRUE, bOilActive=FALSE
//   TestMode=1 → 油路脉冲 → bWaterActive=FALSE, bOilActive=TRUE
//   TestMode=2 → 水路爆破 → bWaterActive=TRUE, bOilActive=FALSE
//   TestMode=3 → 油路爆破 → bWaterActive=FALSE, bOilActive=TRUE
// 安全保护: 若参数异常导致两路同时激活，强制关闭油路仅保留水路
// 这样可避免两路同时输出控制量导致液压冲突
// ============================================================
bWaterActive := (GVL_PulsePressure.PP_TestMode = 0.0 OR GVL_PulsePressure.PP_TestMode = 2.0);
bOilActive   := (GVL_PulsePressure.PP_TestMode = 1.0 OR GVL_PulsePressure.PP_TestMode = 3.0);
bBurstMode   := (GVL_PulsePressure.PP_TestMode = 2.0 OR GVL_PulsePressure.PP_TestMode = 3.0);

//1.水侧测试：开启10.02、10.04，关闭10.01、10.03
IF bWaterActive=TRUE THEN
	PRG_DeviceControl.fromPC_TD_Valve_10_01 := FALSE;
	PRG_DeviceControl.fromPC_TD_Valve_10_02 := TRUE;
	PRG_DeviceControl.fromPC_TD_Valve_10_03 := FALSE;
	PRG_DeviceControl.fromPC_TD_Valve_10_04 := TRUE;
END_IF

//2.剂测测试：开启10.01、10.03，关闭10.02、10.04
IF bOilActive=TRUE THEN
	PRG_DeviceControl.fromPC_TD_Valve_10_01 := TRUE;
	PRG_DeviceControl.fromPC_TD_Valve_10_02 := FALSE;
	PRG_DeviceControl.fromPC_TD_Valve_10_03 := TRUE;
	PRG_DeviceControl.fromPC_TD_Valve_10_04 := FALSE;
END_IF

// 互斥保护：如果因参数异常导致两路同时激活，强制只保留水路
IF bWaterActive AND bOilActive THEN
    bOilActive := FALSE;
END_IF



// ============================================================
// 计算实际PMin（直接使用上位机设定值，0即为0MPa）
// ============================================================
rActualPMin_W := GVL_PulsePressure.PP_Water_MinPressure;
IF rActualPMin_W < 0.0 THEN rActualPMin_W := 0.0; END_IF
IF rActualPMin_W >= GVL_PulsePressure.PP_Water_TargetPressure THEN
    rActualPMin_W := GVL_PulsePressure.PP_Water_TargetPressure * 0.9;
END_IF

rActualPMin_O := GVL_PulsePressure.PP_Oil_MinPressure;
IF rActualPMin_O < 0.0 THEN rActualPMin_O := 0.0; END_IF
IF rActualPMin_O >= GVL_PulsePressure.PP_Oil_TargetPressure THEN
    rActualPMin_O := GVL_PulsePressure.PP_Oil_TargetPressure * 0.9;
END_IF

// 获取当前激活通道的油缸位置
IF bWaterActive THEN
   rCylinderPos := PRG_HydraulicUnit_Control.Water_CylinderPos;
ELSIF bOilActive THEN
   rCylinderPos := PRG_HydraulicUnit_Control.Oil_CylinderPos;
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
    rUTotal_W := 0.0;
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

    // 隔离缸往复运动（10秒切换方向）
	(*
    IF rFlushToggleTimer >= 10.0  THEN
        rFlushToggleTimer := 0.0;
        bFlushDirection := NOT bFlushDirection;
    END_IF
    *)
	
    //水侧隔离缸往复排气
    IF bWaterActive=TRUE THEN	
	
       IF  rCylinderPos >= 95.0 AND NOT bFlushDirection THEN
           bFlushDirection := NOT bFlushDirection;
       END_IF

       IF  rCylinderPos <= 5.0 AND  bFlushDirection THEN
           bFlushDirection := NOT bFlushDirection;
       END_IF
	
       IF NOT bFlushDirection THEN
           PWMOTION.FPGAData.Axis1.Output_ManualSet := 5;   // 正向
       ELSE
           PWMOTION.FPGAData.Axis1.Output_ManualSet := -5;  // 反向
       END_IF
	
    END_IF    
	
	//剂侧隔离缸往复排气
	IF bOilActive=TRUE THEN
		
	   IF  rCylinderPos >= 95.0 AND NOT bFlushDirection THEN
           bFlushDirection := NOT bFlushDirection;
       END_IF

       IF  rCylinderPos <= 5.0 AND  bFlushDirection THEN
           bFlushDirection := NOT bFlushDirection;
       END_IF
	
       IF NOT bFlushDirection THEN
           PWMOTION.FPGAData.Axis1.Output_ManualSet := 3;   // 正向
       ELSE
           PWMOTION.FPGAData.Axis1.Output_ManualSet := -0.5;  // 反向
       END_IF
	
	END_IF
	
    // 冲洗时间到 → 置就绪标志，通知PC
	(*
    IF rFlushTimer >= rFlushDuration THEN
        GVL_PulsePressure.PP_FlushTimeRemaining := 0.0;
        GVL_PulsePressure.PP_StateReady := 1.0;
    END_IF
*)
// ------------------------------------------------------------
// 状态2: 预加压 — 自动序列：检查油缸到位→预加压→自动进入运行
// 油缸到位条件：位移 < 2.0mm
// 预加压到位条件：误差 < 0.2MPa，到位后自动推进到状态3(运行)
// ------------------------------------------------------------
2:
    bRunning := TRUE;
    GVL_PulsePressure.PP_SysState := 2.0;  // 预加压

    rFlushTimer := rFlushTimer + rDt;
    // 检查油缸是否到位（< 2.0mm）
    IF rCylinderPos > 30.0 THEN
        // 油缸未到位，等待，不输出压力控制
        PWMOTION.FPGAData.Axis1.Output_ManualSet := -5;
    ELSIF bBurstMode THEN
        // 爆破模式：不做预加压，从 0 MPa 起斜坡，直接进入运行
        rUTotal_W := 0.0;
        rUTotal_O := 0.0;
        PWMOTION.FPGAData.Axis1.Output_ManualSet := 0;
        iState := 3;
    ELSE
        // 油缸到位，执行预加压
        // 水路预加压
        IF bWaterActive THEN
            rPrePressTarget_W := rActualPMin_W;
            rPrePressErr_W := rPrePressTarget_W - GVL_PulsePressure.PP_Water_ActualPressure;
            rUTotal_W := rPrePressKp * rPrePressErr_W;
            IF rUTotal_W > 10.0 THEN rUTotal_W := 10.0; END_IF
            IF rUTotal_W < -10.0 THEN rUTotal_W := -10.0; END_IF

            IF rUTotal_W > 0 THEN
                PWMOTION.FPGAData.Axis1.Output_ManualSet := rUTotal_W*10 ;
            END_IF
            IF rUTotal_W < 0 THEN
                PWMOTION.FPGAData.Axis1.Output_ManualSet := rUTotal_W*10 ;
            END_IF

            // 预加压到位 → 自动进入运行
            IF ABS(rPrePressErr_W) < 0.2 THEN
                iState := 3;
            END_IF
        ELSE
            rUTotal_W := 0.0;
        END_IF

        // 油路预加压
        IF bOilActive THEN
            rPrePressTarget_O := rActualPMin_O;
            rPrePressErr_O := rPrePressTarget_O - GVL_PulsePressure.PP_Oil_ActualPressure;
            rUTotal_O := rPrePressKp * rPrePressErr_O;
            IF rUTotal_O > 10.0 THEN rUTotal_O := 10.0; END_IF
            IF rUTotal_O < -10.0 THEN rUTotal_O := -10.0; END_IF

            IF rUTotal_O > 0 THEN
                PWMOTION.FPGAData.Axis1.Output_ManualSet := rUTotal_O*10;
            END_IF
            IF rUTotal_O < 0 THEN
                PWMOTION.FPGAData.Axis1.Output_ManualSet := rUTotal_O*10;
            END_IF

            // 预加压到位 → 自动进入运行
            IF ABS(rPrePressErr_O) < 0.2 THEN
                iState := 3;
            END_IF
        ELSE
            rUTotal_O := 0.0;
        END_IF
    END_IF

// ------------------------------------------------------------
// 状态3: 运行 — PID 反馈控制 (ILC 仅诊断)
// 此状态下执行控制流水线:
//   1) 波形生成 → 2) ILC 修正目标 (诊断, 不汇总) → 3) 跟踪误差
//   → 4) PID 反馈输出
// ============================================================
3:
    bRunning := TRUE;
    GVL_PulsePressure.PP_SysState := 3.0;  // 运行

IF bBurstMode THEN
    // ================================================================
    // 爆破试验流程
    //   相位0(升压):  以 rate1=PP_*_RiseRate 从 0 升至 BurstPressure
    //   相位1(保压):  在 BurstPressure 上保持 HoldTime
    //   相位2(续升):  沿用 rate1=PP_*_RiseRate 继续升压
    //   相位3(已爆破): 已记录峰值，进入状态4停机
    // 爆破判据(仅在相位2评估):
    //   (a) 实际压力 < 峰值 × rBurstDropPct(0.7)
    //   (b) 跌速 < rBurstDropRateLim(-20 MPa/s)
    // ================================================================

    // ==================== 水路爆破 ====================
    IF bWaterActive THEN
        // 速率参数(每周期重算，允许在线调整)
        rBurstRate1_W := GVL_PulsePressure.PP_Water_RiseRate;
        IF rBurstRate1_W <= 0.0 THEN
            rBurstRate1_W := 0.01;  // 安全兜底 0.01 MPa/s
        END_IF

        // 给定值递推
        CASE iBurstPhase_W OF
            0:
                rBurstSetpoint_W := rBurstSetpoint_W + rBurstRate1_W * rDt;
                IF rBurstSetpoint_W >= GVL_PulsePressure.PP_Water_BurstPressure THEN
                    rBurstSetpoint_W := GVL_PulsePressure.PP_Water_BurstPressure;
                    rBurstHoldTimer_W := 0.0;
                    iBurstPhase_W := 1;
                END_IF
            1:
                rBurstHoldTimer_W := rBurstHoldTimer_W + rDt;
                IF rBurstHoldTimer_W >= GVL_PulsePressure.PP_Water_HoldTime THEN
                    iBurstPhase_W := 2;
                END_IF
            2:
                rBurstSetpoint_W := rBurstSetpoint_W + rBurstRate1_W * rDt;
                // 安全上限：给定值到 BurstMaxLimit 仍未检测到爆破 → 停机
                IF GVL_PulsePressure.PP_Water_BurstMaxLimit > 0.0
                   AND rBurstSetpoint_W >= GVL_PulsePressure.PP_Water_BurstMaxLimit THEN
                    rBurstSetpoint_W := GVL_PulsePressure.PP_Water_BurstMaxLimit;
                    iBurstPhase_W := 4;  // 到上限未爆破
                    rStopRampVal_W := GVL_PulsePressure.PP_Water_ActualPressure;
                    rStopRampVal_O := GVL_PulsePressure.PP_Oil_ActualPressure;
                    iState := 4;
                END_IF
        END_CASE

        // 跟峰
        IF GVL_PulsePressure.PP_Water_ActualPressure > rBurstPeak_W THEN
            rBurstPeak_W := GVL_PulsePressure.PP_Water_ActualPressure;
        END_IF
        // 跌速估计
        rBurstDropRate_W := (GVL_PulsePressure.PP_Water_ActualPressure - rBurstPrev_W) / rDt;
        rBurstPrev_W := GVL_PulsePressure.PP_Water_ActualPressure;

        // 爆破检测(仅相位2)
        IF iBurstPhase_W = 2 THEN
            IF (GVL_PulsePressure.PP_Water_ActualPressure < rBurstPeak_W * rBurstDropPct)
               OR (rBurstDropRate_W < rBurstDropRateLim) THEN
                GVL_PulsePressure.PP_Water_BurstResult := rBurstPeak_W;
                iBurstPhase_W := 3;
                rStopRampVal_W := GVL_PulsePressure.PP_Water_ActualPressure;
                rStopRampVal_O := GVL_PulsePressure.PP_Oil_ActualPressure;
                iState := 4;
            END_IF
        END_IF

        // P 跟踪给定值
        rPrePressErr_W := rBurstSetpoint_W - GVL_PulsePressure.PP_Water_ActualPressure;
        rUTotal_W := rPrePressKp * rPrePressErr_W;
        IF rUTotal_W > 10.0 THEN rUTotal_W := 10.0; END_IF
        IF rUTotal_W < -10.0 THEN rUTotal_W := -10.0; END_IF
        PWMOTION.FPGAData.Axis1.Output_ManualSet := rUTotal_W * 10;

        // 回写诊断
        GVL_PulsePressure.PP_Water_SetpointPressure := rBurstSetpoint_W;
        GVL_PulsePressure.PP_Water_PressureError := rPrePressErr_W;
        GVL_PulsePressure.PP_Water_PeakPressure := rBurstPeak_W;
        GVL_PulsePressure.PP_Water_BurstPhase := INT_TO_REAL(iBurstPhase_W);
    ELSE
        rUTotal_W := 0.0;
    END_IF

    // ==================== 油路爆破 ====================
    IF bOilActive THEN
        rBurstRate1_O := GVL_PulsePressure.PP_Oil_RiseRate;
        IF rBurstRate1_O <= 0.0 THEN
            rBurstRate1_O := 0.01;
        END_IF

        CASE iBurstPhase_O OF
            0:
                rBurstSetpoint_O := rBurstSetpoint_O + rBurstRate1_O * rDt;
                IF rBurstSetpoint_O >= GVL_PulsePressure.PP_Oil_BurstPressure THEN
                    rBurstSetpoint_O := GVL_PulsePressure.PP_Oil_BurstPressure;
                    rBurstHoldTimer_O := 0.0;
                    iBurstPhase_O := 1;
                END_IF
            1:
                rBurstHoldTimer_O := rBurstHoldTimer_O + rDt;
                IF rBurstHoldTimer_O >= GVL_PulsePressure.PP_Oil_HoldTime THEN
                    iBurstPhase_O := 2;
                END_IF
            2:
                rBurstSetpoint_O := rBurstSetpoint_O + rBurstRate1_O * rDt;
                IF GVL_PulsePressure.PP_Oil_BurstMaxLimit > 0.0
                   AND rBurstSetpoint_O >= GVL_PulsePressure.PP_Oil_BurstMaxLimit THEN
                    rBurstSetpoint_O := GVL_PulsePressure.PP_Oil_BurstMaxLimit;
                    iBurstPhase_O := 4;
                    rStopRampVal_W := GVL_PulsePressure.PP_Water_ActualPressure;
                    rStopRampVal_O := GVL_PulsePressure.PP_Oil_ActualPressure;
                    iState := 4;
                END_IF
        END_CASE

        IF GVL_PulsePressure.PP_Oil_ActualPressure > rBurstPeak_O THEN
            rBurstPeak_O := GVL_PulsePressure.PP_Oil_ActualPressure;
        END_IF
        rBurstDropRate_O := (GVL_PulsePressure.PP_Oil_ActualPressure - rBurstPrev_O) / rDt;
        rBurstPrev_O := GVL_PulsePressure.PP_Oil_ActualPressure;

        IF iBurstPhase_O = 2 THEN
            IF (GVL_PulsePressure.PP_Oil_ActualPressure < rBurstPeak_O * rBurstDropPct)
               OR (rBurstDropRate_O < rBurstDropRateLim) THEN
                GVL_PulsePressure.PP_Oil_BurstResult := rBurstPeak_O;
                iBurstPhase_O := 3;
                rStopRampVal_W := GVL_PulsePressure.PP_Water_ActualPressure;
                rStopRampVal_O := GVL_PulsePressure.PP_Oil_ActualPressure;
                iState := 4;
            END_IF
        END_IF

        rPrePressErr_O := rBurstSetpoint_O - GVL_PulsePressure.PP_Oil_ActualPressure;
        rUTotal_O := rPrePressKp * rPrePressErr_O;
        IF rUTotal_O > 10.0 THEN rUTotal_O := 10.0; END_IF
        IF rUTotal_O < -10.0 THEN rUTotal_O := -10.0; END_IF
        PWMOTION.FPGAData.Axis1.Output_ManualSet := rUTotal_O * 10;

        GVL_PulsePressure.PP_Oil_SetpointPressure := rBurstSetpoint_O;
        GVL_PulsePressure.PP_Oil_PressureError := rPrePressErr_O;
        GVL_PulsePressure.PP_Oil_PeakPressure := rBurstPeak_O;
        GVL_PulsePressure.PP_Oil_BurstPhase := INT_TO_REAL(iBurstPhase_O);
    ELSE
        rUTotal_O := 0.0;
    END_IF

ELSE
    // ==================== 脉冲模式（原逻辑） ====================
    // ==================== 水路控制 ====================
    IF bWaterActive THEN
        RunWaterChannel();
    ELSE
        rUTotal_W := 0.0;
    END_IF

    // ==================== 油路控制 ====================
    IF bOilActive THEN
        RunOilChannel();
    ELSE
        rUTotal_O := 0.0;
    END_IF

    // 检查目标循环数（到达后自动停止；爆破模式不适用）
    IF bWaterActive AND GVL_PulsePressure.PP_Water_TargetCycles > 0.0 THEN
        IF GVL_PulsePressure.PP_Water_CyclesDone >= GVL_PulsePressure.PP_Water_TargetCycles THEN
            rStopRampVal_W := GVL_PulsePressure.PP_Water_ActualPressure;
            rStopRampVal_O := GVL_PulsePressure.PP_Oil_ActualPressure;
            iState := 4;
        END_IF
    END_IF
    IF bOilActive AND GVL_PulsePressure.PP_Oil_TargetCycles > 0.0 THEN
        IF GVL_PulsePressure.PP_Oil_CyclesDone >= GVL_PulsePressure.PP_Oil_TargetCycles THEN
            rStopRampVal_W := GVL_PulsePressure.PP_Water_ActualPressure;
            rStopRampVal_O := GVL_PulsePressure.PP_Oil_ActualPressure;
            iState := 4;
        END_IF
    END_IF
END_IF

// ------------------------------------------------------------
// 状态4: 停止中 — 缓慢卸压
// 停止斜坡机制说明:
//   进入状态4时，rStopRampVal已在InitializeControllers中被初始化为当前实际压力值。
//   每个控制周期(1ms)按 rStopRampRate=5MPa/s 递减目标值，
//   并用与预加压相同的比例控制(Kp=2.0)跟踪递减目标值。
//   这实现了从当前压力到零的平滑下降，避免直接关闭阀门导致的
//   水锤效应或压力冲击。当实际压力降到0.5MPa以下时认为卸压完成，
//   返回空闲状态(状态0)。
// ------------------------------------------------------------
4:
    GVL_PulsePressure.PP_SysState := 4.0;  // 停止中

    // 水路卸压（仅对激活通道执行）
    IF bWaterActive THEN
        IF GVL_PulsePressure.PP_Water_ActualPressure > 0.5 THEN
            // 斜坡目标值每ms递减 rStopRampRate*0.001 = 0.005MPa
            // 即5MPa/s的卸压速率
            rStopRampVal_W := rStopRampVal_W - rStopRampRate * rDt;
            IF rStopRampVal_W < 0.0 THEN rStopRampVal_W := 0.0; END_IF
            rPrePressErr_W := rStopRampVal_W - GVL_PulsePressure.PP_Water_ActualPressure;
            PWMOTION.FPGAData.Axis1.Output_ManualSet := rUTotal_W := rPrePressKp * rPrePressErr_W;
        ELSE
            PWMOTION.FPGAData.Axis1.Output_ManualSet := rUTotal_W := 0.0;
        END_IF
    END_IF

    // 油路卸压（仅对激活通道执行）
    IF bOilActive THEN
        IF GVL_PulsePressure.PP_Oil_ActualPressure > 0.5 THEN
            // 与水路相同的斜坡卸压机制
            rStopRampVal_O := rStopRampVal_O - rStopRampRate * rDt;
            IF rStopRampVal_O < 0.0 THEN rStopRampVal_O := 0.0; END_IF
            rPrePressErr_O := rStopRampVal_O - GVL_PulsePressure.PP_Oil_ActualPressure;
            PWMOTION.FPGAData.Axis1.Output_ManualSet:= rUTotal_O := rPrePressKp * rPrePressErr_O;
        ELSE
            PWMOTION.FPGAData.Axis1.Output_ManualSet := rUTotal_O := 0.0;
        END_IF
    END_IF

    // 激活通道卸压完成 → 置就绪标志，通知PC（PC发命令0回空闲）
    IF bWaterActive AND GVL_PulsePressure.PP_Water_ActualPressure < 0.5 THEN
        GVL_PulsePressure.PP_StateReady := 1.0;
    ELSIF bOilActive AND GVL_PulsePressure.PP_Oil_ActualPressure < 0.5 THEN
        GVL_PulsePressure.PP_StateReady := 1.0;
    END_IF

// ------------------------------------------------------------
// 状态5: 故障
// 由高压保护触发，所有输出强制清零
// PC发命令0即可恢复到空闲状态
// ------------------------------------------------------------
5:
    rUTotal_W := 0.0;
    rUTotal_O := 0.0;
    PWMOTION.FPGAData.Axis1.Output_ManualSet := 0;
    GVL_PulsePressure.PP_SysState := 5.0;  // 故障

END_CASE

// ============================================================
// 高压保护 — 任何状态下都执行，优先级高于状态机
// 说明: 当实际压力超过设定的限值(HighLimit)时，
//   1) 强制控制输出为-5V(最大回油方向)，打开回油阀快速泄压
//   2) 立即将状态机切换到故障状态(状态5)
//   此保护在CASE语句之后执行，因此会覆盖任何状态下的控制输出，
//   确保即使运行状态中出现超压也能立即响应。
//   高压保护条件: HighLimit > 0 且 实际压力 > HighLimit
//   HighLimit > 0的检查是为了防止未设定限值时误触发
// ============================================================
IF bWaterActive AND GVL_PulsePressure.PP_Water_ActualPressure > GVL_PulsePressure.PP_Water_HighLimit
   AND GVL_PulsePressure.PP_Water_HighLimit > 0.0 THEN
    PWMOTION.FPGAData.Axis1.Output_ManualSet := rUTotal_W := 0.0;  // 强制回油
	PRG_DeviceControl.fromPC_Pne_Valve_YV1 := TRUE;
    iState := 5;
ELSE
    PRG_DeviceControl.fromPC_Pne_Valve_YV1 := FALSE;
END_IF

IF bOilActive AND GVL_PulsePressure.PP_Oil_ActualPressure > GVL_PulsePressure.PP_Oil_HighLimit
   AND GVL_PulsePressure.PP_Oil_HighLimit > 0.0 THEN
    PWMOTION.FPGAData.Axis1.Output_ManualSet := rUTotal_O := 0.0;
	PRG_DeviceControl.fromPC_Pne_Valve_YV7 := TRUE;
    iState := 5;
ELSE
	PRG_DeviceControl.fromPC_Pne_Valve_YV7 := FALSE;
END_IF

// ============================================================
// 急停保护 — 任何状态下都执行
// 急停时强制切到停止状态(状态4)进行斜坡卸压
// ============================================================
IF GVL_PulsePressure.PP_EmergencyStop = 1.0 AND iState <> 0 AND iState <> 4 AND iState <> 5 THEN
    rStopRampVal_W := GVL_PulsePressure.PP_Water_ActualPressure;
    rStopRampVal_O := GVL_PulsePressure.PP_Oil_ActualPressure;
    iState := 4;
END_IF

// ============================================================
// 输出到全局变量
// ============================================================
// 总控制输出限幅: ±10V 对应伺服阀最大驱动范围
IF rUTotal_W > 10.0 THEN rUTotal_W := 10.0; END_IF
IF rUTotal_W < -10.0 THEN rUTotal_W := -10.0; END_IF
IF rUTotal_O > 10.0 THEN rUTotal_O := 10.0; END_IF
IF rUTotal_O < -10.0 THEN rUTotal_O := -10.0; END_IF

GVL_PulsePressure.PP_Water_ControlOutput := rUTotal_W;
GVL_PulsePressure.PP_Oil_ControlOutput := rUTotal_O;
METHOD InitializeControllers

// 重置所有功能块
fbWaveGen_W(bReset := TRUE);
fbPID_W(bReset := TRUE);
fbILC_W(bReset := TRUE);

fbWaveGen_O(bReset := TRUE);
fbPID_O(bReset := TRUE);
fbILC_O(bReset := TRUE);

// 重置峰值检测器
rPeakPressure_W := 0.0;
rPeakPressure_O := 0.0;

// 初始化卸压斜坡值（停止时从当前压力开始递减）
rStopRampVal_W := GVL_PulsePressure.PP_Water_ActualPressure;
rStopRampVal_O := GVL_PulsePressure.PP_Oil_ActualPressure;
END_METHOD

METHOD RunWaterChannel
// ---- 1. 波形生成 ----
fbWaveGen_W(
    bEnable    := TRUE,
    rPMin      := rActualPMin_W,
    rPMax      := GVL_PulsePressure.PP_Water_TargetPressure,
    rFrequency := GVL_PulsePressure.PP_Water_Frequency,
    iWaveType  := REAL_TO_INT(GVL_PulsePressure.PP_Water_WaveType),
    rDutyCycle := GVL_PulsePressure.PP_Water_DutyCycle / 100.0,
    rRisePct   := GVL_PulsePressure.PP_Water_RisePct,
    rHoldPct   := GVL_PulsePressure.PP_Water_HoldPct,
    rFallPct   := GVL_PulsePressure.PP_Water_FallPct,
    rDt        := rDt,
    bReset     := FALSE
);

GVL_PulsePressure.PP_Water_SetpointPressure := fbWaveGen_W.rTarget;
GVL_PulsePressure.PP_Water_WavePhase := fbWaveGen_W.rPhase * 360.0;
GVL_PulsePressure.PP_Water_Frequency_FB := GVL_PulsePressure.PP_Water_Frequency;

// 周期计数 + 峰值锁存
IF fbWaveGen_W.bNewCycle THEN
    GVL_PulsePressure.PP_Water_CyclesDone := GVL_PulsePressure.PP_Water_CyclesDone + 1.0;
    GVL_PulsePressure.PP_TotalCyclesDone := GVL_PulsePressure.PP_TotalCyclesDone + 1.0;
    GVL_PulsePressure.PP_Water_PeakPressure := rPeakPressure_W;
    rPeakPressure_W := 0.0;
END_IF
IF GVL_PulsePressure.PP_Water_ActualPressure > rPeakPressure_W THEN
    rPeakPressure_W := GVL_PulsePressure.PP_Water_ActualPressure;
END_IF

// ---- 2. ILC 计算（仅诊断，不参与控制量汇总）----
// ILC 内部维护学习存储；其虚拟目标供诊断观察，但 rError 仍按原始目标算。
fbILC_W(
    bEnable         := (GVL_PulsePressure.PP_Water_ILC_Enable = 1.0),
    rTargetRaw      := fbWaveGen_W.rTarget,
    rActual         := GVL_PulsePressure.PP_Water_ActualPressure,
    iPointIndex     := fbWaveGen_W.iPointIndex,
    iPointsPerCycle := fbWaveGen_W.iPointsPerCycle,
    bNewCycle       := fbWaveGen_W.bNewCycle,
    bReset          := FALSE,
    iMaxIterations  := REAL_TO_INT(GVL_PulsePressure.PP_Water_ILC_MaxIter),
    rLearningRate   := GVL_PulsePressure.PP_Water_ILC_LearningRate,
    rAlphaLR        := 0.4,
    bAlphaEnable    := TRUE,
    nWarmupCycles   := 5
);
rUIlc_W := fbILC_W.rOutput;
GVL_PulsePressure.PP_Water_ILC_Output := rUIlc_W;
GVL_PulsePressure.PP_Water_ILC_Iteration := DINT_TO_REAL(fbILC_W.iIteration);

// 修正后的目标：ILC 使能时用其预畸变目标，否则透传原始波形目标
// （FB_ILC 在 bEnable=FALSE 时 rVirtualTarget=0，必须回退）
IF GVL_PulsePressure.PP_Water_ILC_Enable = 1.0 THEN
    rTargetCorrected_W := fbILC_W.rVirtualTarget;
ELSE
    rTargetCorrected_W := fbWaveGen_W.rTarget;
END_IF

// ---- 3. 跟踪误差 (基于 ILC 修正后的目标) ----
rError_W := rTargetCorrected_W - GVL_PulsePressure.PP_Water_ActualPressure;
GVL_PulsePressure.PP_Water_PressureError := rError_W;

// ---- 4. PID 反馈 ----
fbPID_W(
    bEnable := TRUE,
    rError  := rError_W,
    rDt     := rDt,
    bReset  := FALSE,
    rPID_Kp := GVL_PulsePressure.PP_Water_PID_Kp,
    rPID_Ki := GVL_PulsePressure.PP_Water_PID_Ki
);
rUPid_W := fbPID_W.rOutput;
GVL_PulsePressure.PP_Water_PID_Output := rUPid_W;

// ---- 5. 输出（仅 PID，不汇总 ILC）----
rUTotal_W := rUPid_W;
IF rUTotal_W > 10.0 THEN rUTotal_W := 10.0; END_IF
IF rUTotal_W < -10.0 THEN rUTotal_W := -10.0; END_IF
PWMOTION.FPGAData.Axis1.Output_ManualSet := rUTotal_W * 10;
END_METHOD

METHOD RunOilChannel
// ---- 1. 波形生成 ----
fbWaveGen_O(
    bEnable    := TRUE,
    rPMin      := rActualPMin_O,
    rPMax      := GVL_PulsePressure.PP_Oil_TargetPressure,
    rFrequency := GVL_PulsePressure.PP_Oil_Frequency,
    iWaveType  := REAL_TO_INT(GVL_PulsePressure.PP_Oil_WaveType),
    rDutyCycle := GVL_PulsePressure.PP_Oil_DutyCycle / 100.0,
    rRisePct   := GVL_PulsePressure.PP_Oil_RisePct,
    rHoldPct   := GVL_PulsePressure.PP_Oil_HoldPct,
    rFallPct   := GVL_PulsePressure.PP_Oil_FallPct,
    rDt        := rDt,
    bReset     := FALSE
);

GVL_PulsePressure.PP_Oil_SetpointPressure := fbWaveGen_O.rTarget;
GVL_PulsePressure.PP_Oil_WavePhase := fbWaveGen_O.rPhase * 360.0;
GVL_PulsePressure.PP_Oil_Frequency_FB := GVL_PulsePressure.PP_Oil_Frequency;

IF fbWaveGen_O.bNewCycle THEN
    GVL_PulsePressure.PP_Oil_CyclesDone := GVL_PulsePressure.PP_Oil_CyclesDone + 1.0;
    GVL_PulsePressure.PP_TotalCyclesDone := GVL_PulsePressure.PP_TotalCyclesDone + 1.0;
    GVL_PulsePressure.PP_Oil_PeakPressure := rPeakPressure_O;
    rPeakPressure_O := 0.0;
END_IF
IF GVL_PulsePressure.PP_Oil_ActualPressure > rPeakPressure_O THEN
    rPeakPressure_O := GVL_PulsePressure.PP_Oil_ActualPressure;
END_IF

// ---- 2. ILC 计算（仅诊断，不参与控制量汇总）----
fbILC_O(
    bEnable         := (GVL_PulsePressure.PP_Oil_ILC_Enable = 1.0),
    rTargetRaw      := fbWaveGen_O.rTarget,
    rActual         := GVL_PulsePressure.PP_Oil_ActualPressure,
    iPointIndex     := fbWaveGen_O.iPointIndex,
    iPointsPerCycle := fbWaveGen_O.iPointsPerCycle,
    bNewCycle       := fbWaveGen_O.bNewCycle,
    bReset          := FALSE,
    iMaxIterations  := REAL_TO_INT(GVL_PulsePressure.PP_Oil_ILC_MaxIter),
    rLearningRate   := GVL_PulsePressure.PP_Oil_ILC_LearningRate,
    rAlphaLR        := 0.4,
    bAlphaEnable    := TRUE,
    nWarmupCycles   := 5
);
rUIlc_O := fbILC_O.rOutput;
GVL_PulsePressure.PP_Oil_ILC_Output := rUIlc_O;
GVL_PulsePressure.PP_Oil_ILC_Iteration := DINT_TO_REAL(fbILC_O.iIteration);

// 修正后的目标：ILC 使能时用其预畸变目标，否则透传原始波形目标
IF GVL_PulsePressure.PP_Oil_ILC_Enable = 1.0 THEN
    rTargetCorrected_O := fbILC_O.rVirtualTarget;
ELSE
    rTargetCorrected_O := fbWaveGen_O.rTarget;
END_IF

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
    rPID_Ki := GVL_PulsePressure.PP_Oil_PID_Ki
);
rUPid_O := fbPID_O.rOutput;
GVL_PulsePressure.PP_Oil_PID_Output := rUPid_O;

// ---- 5. 输出（仅 PID，不汇总 ILC）----
rUTotal_O := rUPid_O;
IF rUTotal_O > 10.0 THEN rUTotal_O := 10.0; END_IF
IF rUTotal_O < -10.0 THEN rUTotal_O := -10.0; END_IF
PWMOTION.FPGAData.Axis1.Output_ManualSet := rUTotal_O * 10;
END_METHOD
END_PROGRAM
