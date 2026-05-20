// Global Variable List: GVL_PulsePressure
VAR_GLOBAL
	PP_FrameCounter_PC : REAL; // 上位机帧计数器（心跳）
	PP_SysCommand : REAL; // 系统命令 0=空闲 1=冲洗排气 2=运行(自动预加压) 3=停止
	PP_TestMode : REAL; // 测试模式 0=水路脉冲 1=油路脉冲 2=水路爆破 3=油路爆破
	PP_AlarmReset : REAL; // 报警复位（上升沿有效）
	PP_Enable : REAL; // 系统使能
	PP_EmergencyStop : REAL; // 急停
	PP_HeartbeatTimeout : REAL; // 心跳超时时间(s)
	PP_FlushDuration : REAL; // 冲洗排气持续时间(s)
	PP_FlushValveOutput : REAL; // 冲洗排气阀门输出(V)
	PP_Water_TargetPressure : REAL; // 水路目标峰值压力(MPa) = PMax
	PP_Water_MinPressure : REAL; // 水路最低压力(MPa) = PMin
	PP_Water_Frequency : REAL; // 水路脉冲频率(Hz)
	PP_Water_WaveType : REAL; // 波形类型 0=正弦 1=方波 2=三角 3=梯形 4=自定义
	PP_Water_DutyCycle : REAL; // 方波占空比(%)
	PP_Water_RisePct : REAL; // 梯形波上升段占比
	PP_Water_HoldPct : REAL; // 梯形波保持段占比
	PP_Water_FallPct : REAL; // 梯形波下降段占比
	PP_Water_HighLimit : REAL; // 水路高压保护限值(MPa)
	PP_Water_TargetCycles : REAL; // 目标循环次数
	PP_Water_PID_Kp : REAL; // 水路 PID 比例增益 (V/MPa)
	PP_Water_PID_Ki : REAL; // 水路 PID 积分增益 (V/MPa/s)
	PP_Water_ILC_Enable : REAL; // 水路迭代学习控制使能
	PP_Water_ILC_MaxIter : REAL; // 水路ILC最大迭代次数
	PP_Water_ILC_LearningRate : REAL; // 水路ILC学习率(0~1)，0=使用容积自适应默认值
	PP_Water_RiseRate : REAL; // 水路爆破升压速率(MPa/s)
	PP_Water_BurstMaxLimit : REAL; // 水路爆破最大安全压力(MPa)；给定值到此停机，避免无限升压
	PP_Water_Burst_Kp : REAL; // 水路爆破 PID 比例增益(V/MPa)
	PP_Water_Burst_Ki : REAL; // 水路爆破 PID 积分增益(V/MPa/s)，仅保压段生效
	PP_Water_BurstHoldCount : REAL; // 水路爆破保压段数 1~10；越界自动钳到 [1,10]
	PP_Water_BurstHoldP : ARRAY[1..10] OF REAL; // 水路各保压段目标压力(MPa)
	PP_Water_BurstHoldT : ARRAY[1..10] OF REAL; // 水路各保压段保压时长(s)
	PP_Water_BurstResult : REAL; // 水路爆破压力记录(MPa)，0 表示尚未爆破
	PP_Water_BurstPhase : REAL; // 水路爆破相位 5=待机 0=升压 1=保压 2=续升 3=已爆破 4=到上限未爆破
	PP_Water_CycleReset : REAL; // 水路循环计数清零命令(上升沿有效)
	PP_Oil_TargetPressure : REAL; // 油路目标峰值压力(MPa) = PMax
	PP_Oil_MinPressure : REAL; // 油路最低压力(MPa) = PMin
	PP_Oil_Frequency : REAL; // 油路脉冲频率(Hz)
	PP_Oil_WaveType : REAL; // 波形类型
	PP_Oil_DutyCycle : REAL; // 方波占空比(%)
	PP_Oil_RisePct : REAL; // 梯形波上升段占比
	PP_Oil_HoldPct : REAL; // 梯形波保持段占比
	PP_Oil_FallPct : REAL; // 梯形波下降段占比
	PP_Oil_HighLimit : REAL; // 油路高压保护限值(MPa)
	PP_Oil_TargetCycles : REAL; // 目标循环次数
	PP_Oil_PID_Kp : REAL; // 油路 PID 比例增益 (V/MPa)
	PP_Oil_PID_Ki : REAL; // 油路 PID 积分增益 (V/MPa/s)
	PP_Oil_ILC_Enable : REAL; // 油路迭代学习控制使能
	PP_Oil_ILC_MaxIter : REAL; // 油路ILC最大迭代次数
	PP_Oil_ILC_LearningRate : REAL; // 油路ILC学习率(0~1)，0=使用容积自适应默认值
	PP_Oil_RiseRate : REAL; // 油路爆破升压速率(MPa/s)
	PP_Oil_BurstMaxLimit : REAL; // 油路爆破最大安全压力(MPa)；给定值到此停机，避免无限升压
	PP_Oil_Burst_Kp : REAL; // 油路爆破 PID 比例增益(V/MPa)
	PP_Oil_Burst_Ki : REAL; // 油路爆破 PID 积分增益(V/MPa/s)，仅保压段生效
	PP_Oil_BurstHoldCount : REAL; // 油路爆破保压段数 1~10；越界自动钳到 [1,10]
	PP_Oil_BurstHoldP : ARRAY[1..10] OF REAL; // 油路各保压段目标压力(MPa)
	PP_Oil_BurstHoldT : ARRAY[1..10] OF REAL; // 油路各保压段保压时长(s)
	PP_Oil_BurstResult : REAL; // 油路爆破压力记录(MPa)，0 表示尚未爆破
	PP_Oil_BurstPhase : REAL; // 油路爆破相位 5=待机 0=升压 1=保压 2=续升 3=已爆破 4=到上限未爆破
	PP_Oil_CycleReset : REAL; // 油路循环计数清零命令(上升沿有效)
	PP_Hydro_HighLimit : REAL; // 液压站高压保护限值(MPa)
	PP_Hydro_TempLimit : REAL; // 液压油温度保护限值(°C)
	PP_Hydro_PumpCmd : REAL; // 液压泵启停命令
	PP_Hydro_MotorSpeed : REAL; // 液压泵电机转速设定值(rpm)
	PP_IO_OutputBits : REAL; // 数字量输出控制
	PP_IO_WaterCircuitSel : REAL; // 水路选通
	PP_IO_OilCircuitSel : REAL; // 油路选通
	PP_FrameCounter_PLC : REAL; // PLC帧计数器（每10ms递增）
	PP_SysState : REAL; // 系统状态 0=空闲 1=冲洗排气 2=预加压 3=运行 4=停止中 5=故障
	PP_AlarmFlags : REAL; // 报警标志(32bit映射至REAL)
	PP_TotalCyclesDone : REAL; // 累计完成循环次数
	PP_RunningMode : REAL; // 当前运行模式
	PP_IO_InputBits : REAL; // 数字量输入状态
	PP_IO_OutputBits_FB : REAL; // 数字量输出状态回读
	PP_CommsState : REAL; // 通讯状态（内部使用）
	PP_FlushTimeRemaining : REAL; // 冲洗排气剩余时间(s)
	PP_StateReady : REAL; // 状态推进就绪标志
	PP_Water_ActualPressure : REAL; // 水路实际压力(MPa)
	PP_Water_SetpointPressure : REAL; // 水路当前给定压力(MPa)
	PP_Water_PressureError : REAL; // 水路压力偏差(MPa)
	PP_Water_ControlOutput : REAL; // 水路 PID 控制输出(V)
	PP_Water_ValveCurrent : REAL; // 水路比例阀电流(mA)
	PP_Water_CylinderPos : REAL; // 水路缸体位移(mm)
	PP_Water_CyclesDone : REAL; // 水路已完成循环次数
	PP_Water_Frequency_FB : REAL; // 水路实际频率回读(Hz)
	PP_Water_WavePhase : REAL; // 水路波形相位角(°)
	PP_Water_PeakPressure : REAL; // 水路本次脉冲峰值压力(MPa)
	PP_Water_PID_Output : REAL; // 水路 PID 反馈输出(V)
	PP_Water_ILC_Output : REAL; // 水路ILC学习输出(V)
	PP_Water_ILC_Iteration : REAL; // 水路ILC当前迭代次数
	PP_Water_ILC_Learning : REAL; // 水路ILC自学习中标志 1=学习中 0=空闲/已收敛
	PP_Oil_ActualPressure : REAL; // 油路实际压力(MPa)
	PP_Oil_SetpointPressure : REAL; // 油路当前给定压力(MPa)
	PP_Oil_PressureError : REAL; // 油路压力偏差(MPa)
	PP_Oil_ControlOutput : REAL; // 油路 PID 控制输出(V)
	PP_Oil_ValveCurrent : REAL; // 油路比例阀电流(mA)
	PP_Oil_CylinderPos : REAL; // 油路缸体位移(mm)
	PP_Oil_CyclesDone : REAL; // 油路已完成循环次数
	PP_Oil_Frequency_FB : REAL; // 油路实际频率回读(Hz)
	PP_Oil_WavePhase : REAL; // 油路波形相位角(°)
	PP_Oil_PeakPressure : REAL; // 油路本次脉冲峰值压力(MPa)
	PP_Oil_PID_Output : REAL; // 油路 PID 反馈输出(V)
	PP_Oil_ILC_Output : REAL; // 油路ILC学习输出(V)
	PP_Oil_ILC_Iteration : REAL; // 油路ILC当前迭代次数
	PP_Oil_ILC_Learning : REAL; // 油路ILC自学习中标志 1=学习中 0=空闲/已收敛
	PP_Hydro_Pressure : REAL; // 液压站系统压力(MPa)
	PP_Hydro_Temperature : REAL; // 液压油温度(°C)
	PP_Hydro_OilLevel : REAL; // 液位值(mm)
	PP_Hydro_PumpStatus : REAL; // 液压泵运行状态
	PP_Hydro_FilterStatus : REAL; // 过滤器状态
	PP_Hydro_PumpRunTime : REAL; // 液压泵累计运行时间(h)
	PP_WaveUpload_Channel : REAL; // 上传目标通道 0=水路 1=油路
	PP_WaveUpload_NumPoints : REAL; // 波形数据点数 (2~500)
	PP_WaveUpload_Commit : REAL; // 提交标志: 上升沿触发加载
	PP_WaveUpload_Status : REAL; // 状态回读: 0=空闲 1=已加载 2=错误
	PP_WaveUpload_Data : ARRAY[0..799] OF REAL; // 波形数据 (MPa)
	PP_PLC_ScanCycle : REAL; // PLC扫描周期实测值(ms)
	PP_TCPIP_CommCycle : REAL; // TCP/IP实际通讯周期(ms)
	PP_PLC_Timestamp_Low : REAL; // PLC时间戳低32位(ms)
	PP_PLC_Timestamp_High : REAL; // PLC时间戳高32位
END_VAR
