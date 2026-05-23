PROGRAM TCP_PC_to_PLC
VAR
	HOLDING_REGISTER AT %IW0 : ARRAY[0..1999] OF WORD; // 上位机写入缓冲区
	TwoWord_to_Float : PWmotion.TwoWord_to_Float;
	i : DINT; // 寄存器地址索引（WORD索引）
END_VAR

// ============================================================
// 系统控制区（WORD地址 0–13）
// 解析上位机发送的7个系统控制变量
// 地址安排: 连续排列，每个变量2 WORD
// ============================================================
i := 0;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_FrameCounter_PC := TwoWord_to_Float.Output;   // 0-1: 上位机帧计数器
// 数据流: PC每10ms递增写入 → PLC读取，用于心跳检测
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_SysCommand := TwoWord_to_Float.Output;         // 2-3: 系统命令
// 数据流: PC写入命令值 → PRG_PressureControl边沿检测
i := i + 2;

// 4-5: 保留 (原 TestMode，V4.x 油路单通道后不再使用)
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_AlarmReset := TwoWord_to_Float.Output;         // 6-7: 报警复位
// 数据流: PC写入1.0复位 → PRG_PressureControl检测上升沿
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Enable := TwoWord_to_Float.Output;             // 8-9: 系统使能
// 数据流: PC写入使能状态 → PRG_PressureControl作为启动前提条件
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_EmergencyStop := TwoWord_to_Float.Output;      // 10-11: 急停
// 数据流: PC写入急停 → PRG_PressureControl最高优先级响应
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_HeartbeatTimeout := TwoWord_to_Float.Output;   // 12-13: 心跳超时
// 数据流: PC写入超时时间 → TCPIP_PulseServer用于心跳检测
i := i + 2;

// ============================================================
// 冲洗排气参数区（WORD地址 14–17）
// 解析冲洗排气阶段的持续时间和阀门输出电压
// ============================================================
TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_FlushDuration := TwoWord_to_Float.Output;      // 14-15: 冲洗排气持续时间(s)
// 数据流: PC写入 → PRG_PressureControl状态1(冲洗排气)使用
// 0.0=跳过冲洗直接进入预加压
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_FlushValveOutput := TwoWord_to_Float.Output;   // 16-17: 冲洗排气阀门输出(V)
// 数据流: PC写入 → PRG_PressureControl状态1(冲洗排气)使用
// 默认2.0V 有效范围: 0.5 ~ 5.0V
i := i + 2;

// ============================================================
// 水路控制参数区（WORD 20–67）—— V4.x 起仅油路，水路寄存器保留不解析
// ============================================================
// 20-67: 保留 (原水路参数区)

// ============================================================
// 油路控制参数区（WORD地址 68–115）
// V2.1: 阀样本参数替代Kv/TauValve
// ============================================================
i := 68;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_TargetPressure := TwoWord_to_Float.Output;   // 68-69: 油路目标压力
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_MinPressure := TwoWord_to_Float.Output;      // 70-71: 油路最低压力(PMin)
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_Frequency := TwoWord_to_Float.Output;        // 72-73: 油路频率
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_WaveType := TwoWord_to_Float.Output;         // 74-75: 波形类型
i := i + 2;

// 76-77: 保留 (原油路方波占空比，V4.x 不再使用)
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_RisePct := TwoWord_to_Float.Output;          // 78-79: 上升段占比
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_HoldPct := TwoWord_to_Float.Output;          // 80-81: 保持段占比
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_FallPct := TwoWord_to_Float.Output;          // 82-83: 下降段占比
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_HighLimit := TwoWord_to_Float.Output;        // 84-85: 油路高压限值
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_TargetCycles := TwoWord_to_Float.Output;     // 86-87: 目标循环次数
i := i + 2;

// --- MFF 系统参数 ---
TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_VBase := TwoWord_to_Float.Output;            // 88-89: 油路基础容积(m³)
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_VSpecimen := TwoWord_to_Float.Output;        // 90-91: 油路被试件容积(m³)
i := i + 2;

// --- V2.1: 阀样本参数（替代原Kv/TauValve）---
TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_ValveQnom := TwoWord_to_Float.Output;        // 92-93: 阀额定流量(L/min)
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_ValveDPnom := TwoWord_to_Float.Output;       // 94-95: 阀额定压降(bar)
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_ValveUmax := TwoWord_to_Float.Output;        // 96-97: 阀额定电压(V)
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_ValveDynMode := TwoWord_to_Float.Output;     // 98-99: 阀动态模式
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_ValveDynParam := TwoWord_to_Float.Output;    // 100-101: 阀动态参数
i := i + 2;

// --- ILC 参数 ---
TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_ILC_Enable := TwoWord_to_Float.Output;       // 102-103: 油路ILC使能
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_ILC_MaxIter := TwoWord_to_Float.Output;      // 104-105: 油路ILC最大迭代次数
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_ILC_LearningRate := TwoWord_to_Float.Output; // 106-107: 油路ILC学习率
i := i + 2;

// 108-113: 保留 (原油路爆破参数 BurstPressure / RiseTime / HoldTime，V4.x 不再使用)
i := i + 6;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_CycleReset := TwoWord_to_Float.Output;       // 114-115: 油路循环计数清零命令
i := i + 2;

// ============================================================
// 液压站参数区（WORD地址 112–121）
// ============================================================
i := 116;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Hydro_HighLimit := TwoWord_to_Float.Output;      // 116-117: 液压站高压限值
// 数据流: PC写入 → 液压站安全保护
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Hydro_TempLimit := TwoWord_to_Float.Output;      // 118-119: 温度保护限值
// 数据流: PC写入 → 温度超限报警保护
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Hydro_WorkingPressure := TwoWord_to_Float.Output; // 120-121: 液压站工作压力(Ps)
// 数据流: PC写入 → PRG_PressureControl MFF前馈中供油压力Ps使用
//         换算: rPs_Pa = PP_Hydro_WorkingPressure × 1E6
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Hydro_PumpCmd := TwoWord_to_Float.Output;        // 122-123: 液压泵命令
// 数据流: PC写入 → 液压泵启停控制
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Hydro_MotorSpeed := TwoWord_to_Float.Output;     // 124-125: 电机转速设定
// 数据流: PC写入 → 变频器转速控制
i := i + 2;

// ============================================================
// MFF系统参数区（WORD地址 124–127）
// 水路和油路共用的物理参数
// ============================================================
i := 128;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Sys_BetaE := TwoWord_to_Float.Output;            // 128-129: 体积弹性模量(Pa)
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Sys_CLeak := TwoWord_to_Float.Output;            // 130-131: 泄漏系数
i := i + 2;

// ============================================================
// IO 控制区（WORD地址 130–137）
// ============================================================
i := 134;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_IO_OutputBits := TwoWord_to_Float.Output;        // 134-135: 数字量输出控制
// 数据流: PC写入 → 硬件DO映射
i := i + 2;

// 136-137: 保留 (原水路选通)
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_IO_OilCircuitSel := TwoWord_to_Float.Output;     // 138-139: 油路选通
// 数据流: PC写入 → 油路电磁阀硬件选通

// 140-199: 
i := i + 2;
//-{140}
PRG_DeviceControl.fromPC_SMP_Start := HOLDING_REGISTER[i].0; //伺服泵_启动
PRG_DeviceControl.fromPC_SMP_Stop := HOLDING_REGISTER[i].1; //伺服泵_停止
PRG_DeviceControl.fromPC_SMP_Rest := HOLDING_REGISTER[i].2; //伺服泵_故障复位
PRG_DeviceControl.fromPC_XH_OilPump_Start := HOLDING_REGISTER[i].3;

PRG_DeviceControl.fromPC_XH_OilPump_Stop := HOLDING_REGISTER[i].4;
PRG_DeviceControl.fromPC_XH_OilPump_Rest := HOLDING_REGISTER[i].5;
PRG_DeviceControl.fromPC_HR_Pump1_Start := HOLDING_REGISTER[i].6;
PRG_DeviceControl.fromPC_HR_Pump1_Stop := HOLDING_REGISTER[i].7;

PRG_DeviceControl.fromPC_HR_Pump1_Rest := HOLDING_REGISTER[i].8;
PRG_DeviceControl.fromPC_HR_Pump2_Start := HOLDING_REGISTER[i].9;
PRG_DeviceControl.fromPC_HR_Pump2_Stop := HOLDING_REGISTER[i].10;
PRG_DeviceControl.fromPC_HR_Pump2_Rest := HOLDING_REGISTER[i].11;

//PRG_DeviceControl.fromPC_TD_Valve_10_01 := HOLDING_REGISTER[i].12; //-----剂侧油缸
//PRG_DeviceControl.fromPC_TD_Valve_10_02 := HOLDING_REGISTER[i].13; //水侧油缸
//PRG_DeviceControl.fromPC_TD_Valve_10_03 := HOLDING_REGISTER[i].14; //-----剂侧油缸
//PRG_DeviceControl.fromPC_TD_Valve_10_04 := HOLDING_REGISTER[i].15; //水侧油缸

//-{141}
//PRG_DeviceControl.fromPC_TD_Valve_24_01 := HOLDING_REGISTER[i+1].0;
//PRG_DeviceControl.fromPC_TD_Valve_30_01 := HOLDING_REGISTER[i+1].1;
PRG_DeviceControl.fromPC_Pne_Valve_YV1 := HOLDING_REGISTER[i+1].2;
PRG_DeviceControl.fromPC_Pne_Valve_YV2 := HOLDING_REGISTER[i+1].3;

PRG_DeviceControl.fromPC_Pne_Valve_YV3 := HOLDING_REGISTER[i+1].4;
PRG_DeviceControl.fromPC_Pne_Valve_YV4 := HOLDING_REGISTER[i+1].5;
PRG_DeviceControl.fromPC_Pne_Valve_YV5 := HOLDING_REGISTER[i+1].6;
PRG_DeviceControl.fromPC_Pne_Valve_YV6 := HOLDING_REGISTER[i+1].7;

PRG_DeviceControl.fromPC_Pne_Valve_YV7 := HOLDING_REGISTER[i+1].8;
PRG_DeviceControl.fromPC_Pne_Valve_YV8 := HOLDING_REGISTER[i+1].9;
PRG_DeviceControl.fromPC_Pne_Valve_YV9 := HOLDING_REGISTER[i+1].10;
PRG_DeviceControl.fromPC_Pne_Valve_YV10 := HOLDING_REGISTER[i+1].11;

PRG_DeviceControl.fromPC_Pne_Valve_YV11 := HOLDING_REGISTER[i+1].12;
PRG_DeviceControl.fromPC_Pne_Valve_YV12 := HOLDING_REGISTER[i+1].13;
PRG_DeviceControl.fromPC_Pne_Valve_YV13 := HOLDING_REGISTER[i+1].14;
// := HOLDING_REGISTER[i+1].15;

i := i + 2;  //142-143
//-{142}
// := HOLDING_REGISTER[i].0; 
// := HOLDING_REGISTER[i].1; 
// := HOLDING_REGISTER[i].2; 
// := HOLDING_REGISTER[i].3;

// := HOLDING_REGISTER[i].4;
// := HOLDING_REGISTER[i].5;
// := HOLDING_REGISTER[i].6;
// := HOLDING_REGISTER[i].7;

// := HOLDING_REGISTER[i].8;
// := HOLDING_REGISTER[i].9;
// := HOLDING_REGISTER[i].10;
// := HOLDING_REGISTER[i].11;

// := HOLDING_REGISTER[i].12;
// := HOLDING_REGISTER[i].13;
// := HOLDING_REGISTER[i].14;
// := HOLDING_REGISTER[i].15;

//-{143}
// := HOLDING_REGISTER[i+1].0;
// := HOLDING_REGISTER[i+1].1;
// := HOLDING_REGISTER[i+1].2;
// := HOLDING_REGISTER[i+1].3;

// := HOLDING_REGISTER[i+1].4;
// := HOLDING_REGISTER[i+1].5;
// := HOLDING_REGISTER[i+1].6;
// := HOLDING_REGISTER[i+1].7;

// := HOLDING_REGISTER[i+1].8;
// := HOLDING_REGISTER[i+1].9;
// := HOLDING_REGISTER[i+1].10;
// := HOLDING_REGISTER[i+1].11;

// := HOLDING_REGISTER[i+1].12;
// := HOLDING_REGISTER[i+1].13;
// := HOLDING_REGISTER[i+1].14;
// := HOLDING_REGISTER[i+1].15;


i := i + 2;  
TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
PRG_DeviceControl.fromPC_SMP_Pressure_InPut := TwoWord_to_Float.Output;      //144-145(伺服泵_压力设定)

i := i + 2;  
TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
PRG_DeviceControl.fromPC_SMP_Flow_InPut := TwoWord_to_Float.Output;         //146-147(伺服泵_流量设定)

i := i + 2;
TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
PRG_DeviceControl.fromPC_HR_Pump1_Frequency_InPut := TwoWord_to_Float.Output;      // 148-149(换热泵1_频率(转速)设定)

i := i+2;
TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
PRG_DeviceControl.fromPC_HR_Pump2_Frequency_InPut := TwoWord_to_Float.Output;      // 150-151(换热泵2_频率(转速)设定)

//152-169，保留




// 170-1999: 保留 (原波形上传 + 自定义波形数据区，V4.x 删除自定义LUT后不再使用)

END_PROGRAM