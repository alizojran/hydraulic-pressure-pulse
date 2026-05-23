PROGRAM PRG_PressureControl
VAR
	iState : INT := 0; // 0=空闲 1=冲洗排气 2=预加压 3=运行 4=停止中 5=故障
	bRunning : BOOL;
	iCmd : INT; // PC命令号 (0~3)
	iCmdPrev : INT; // 上一周期命令号（边沿检测用）
	bCmdChanged : BOOL; // 命令变化标志
	rCylinderPos : REAL; // 油缸位置(mm)
	rDt : REAL := 0.001; // 控制周期 1ms
	fbWaveGen_O : FB_WaveformGen;
	fbMFF_O : FB_ModelFeedforward;
	fbPID_O : FB_PID;
	fbILC_O : FB_ILC;
	rVTotal_O : REAL; // 油路总容积
	rPs_Pa : REAL; // 供油压力 (Pa)
	rError_O : REAL; // 油路跟踪误差
	rUTotal_O : REAL; // 油路总控制量
	rUMff_O : REAL;
	rUIlc_O : REAL;
	rUAdrc_O : REAL;
	rPrePressTarget_O : REAL;
	rPrePressKp : REAL := 2.0; // 预加压比例增益
	rPrePressErr_O : REAL;
	rFlushTimer : REAL; // 冲洗排气计时器(s)
	rFlushDuration : REAL; // 冲洗排气持续时间(s) 缓存
	rFlushOutput : REAL; // 冲洗排气阀门输出(V) 缓存
	rPeakPressure_O : REAL;
	rStopRampVal_O : REAL;
	rActualPMin_O : REAL; // 油路实际PMin
	rStopRampRate : REAL := 5.0; // 卸压速率 (MPa/s)
	bOilCycleResetPrev : BOOL; // 油路循环清零上升沿检测
	bFlushDirection : BOOL; // 冲洗排气往复方向 FALSE=正向 TRUE=反向
	rFlushToggleTimer : REAL; // 冲洗排气往复切换计时器(s)
	nMffLeadSteps : INT; // MFF超前步数(上位机设置)
	Oil_Pressure_Filter : PWControl.LowPassFilter_R;
	PP_Oil_ActualPressure : REAL;
END_VAR

{*
26.01为剂侧产品端低压力传感器
27.01为剂侧产品端15MPa高压力传感器
*}

//剂侧产品端压力 — 默认使用26.01低压传感器(可根据需要切换27.01)
PP_Oil_ActualPressure := GVL_PulsePressure.PP_Dev_Pressure_26_01;
Oil_Pressure_Filter(in:= PP_Oil_ActualPressure,t:= T#100MS);
GVL_PulsePressure.PP_Oil_ActualPressure := Oil_Pressure_Filter.out;


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
            iState := 2;  // 先进入预加压，内部自动推进到运行
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
// 计算系统参数
// 供油压力的单位换算: MPa → Pa，并设置安全下限
// 总容积 = 基础容积 + 被试件容积，并设置安全下限
// ============================================================
rPs_Pa := GVL_PulsePressure.PP_Hydro_WorkingPressure * 1.0E6;
IF rPs_Pa < 1.0E6 THEN rPs_Pa := 35.0E6; END_IF  // 默认35MPa

rVTotal_O := GVL_PulsePressure.PP_Oil_VBase + GVL_PulsePressure.PP_Oil_VSpecimen;
IF rVTotal_O < 1.0E-6 THEN rVTotal_O := 0.7E-3; END_IF  // 默认0.7L

// ============================================================
// 计算实际PMin（直接使用上位机设定值，0即为0MPa）
// ============================================================
rActualPMin_O := GVL_PulsePressure.PP_Oil_MinPressure;
IF rActualPMin_O < 0.0 THEN rActualPMin_O := 0.0; END_IF
IF rActualPMin_O >= GVL_PulsePressure.PP_Oil_TargetPressure THEN
    rActualPMin_O := GVL_PulsePressure.PP_Oil_TargetPressure * 0.9;
END_IF

// 获取油缸位置
rCylinderPos := GVL_PulsePressure.PP_Oil_CylinderPos;

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

    // 隔离缸往复运动（10秒切换方向）
	(*
    IF rFlushToggleTimer >= 10.0  THEN
        rFlushToggleTimer := 0.0;
        bFlushDirection := NOT bFlushDirection;
    END_IF
    *)
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
    // 检查油缸是否到位（< 30.0mm）
    IF rCylinderPos > 30.0 THEN
        // 油缸未到位，等待，不输出压力控制
        PWMOTION.FPGAData.Axis1.Output_ManualSet := -5;
    ELSE
        // 油缸到位，执行预加压
        rPrePressTarget_O := rActualPMin_O;
        rPrePressErr_O := rPrePressTarget_O - GVL_PulsePressure.PP_Oil_ActualPressure;
        rUTotal_O := rPrePressKp * rPrePressErr_O;
        IF rUTotal_O > 10.0 THEN rUTotal_O := 10.0; END_IF
        IF rUTotal_O < -10.0 THEN rUTotal_O := -10.0; END_IF
        PWMOTION.FPGAData.Axis1.Output_ManualSet := rUTotal_O * 10;

        // 预加压到位 → 自动进入运行
        IF ABS(rPrePressErr_O) < 0.2 THEN
            iState := 3;
        END_IF
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

    // ==================== 油路控制 ====================
    RunOilChannel();

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
//   进入状态4时，rStopRampVal已在InitializeControllers中被初始化为当前实际压力值。
//   每个控制周期(1ms)按 rStopRampRate=5MPa/s 递减目标值，
//   并用与预加压相同的比例控制(Kp=2.0)跟踪递减目标值。
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
        rPrePressErr_O := rStopRampVal_O - GVL_PulsePressure.PP_Oil_ActualPressure;
        PWMOTION.FPGAData.Axis1.Output_ManualSet := rUTotal_O := rPrePressKp * rPrePressErr_O;
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