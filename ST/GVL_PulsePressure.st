// Global Variable List: GVL_PulsePressure
// 仅油路 + 军标水锤波 (V4.x 简化版)
VAR_GLOBAL
	PP_FrameCounter_PC : REAL; // 上位机帧计数器（心跳）
	PP_SysCommand : REAL; // 系统命令 0=空闲 1=冲洗排气 2=运行 3=停止
	PP_AlarmReset : REAL; // 报警复位（上升沿有效）
	PP_Enable : REAL; // 系统使能
	PP_EmergencyStop : REAL; // 急停
	PP_HeartbeatTimeout : REAL; // 心跳超时时间(s)
	PP_FlushDuration : REAL; // 冲洗排气持续时间(s)
	PP_FlushValveOutput : REAL; // 冲洗排气阀门输出(V)
	PP_Oil_TargetPressure : REAL; // 油路目标峰值压力(MPa) = PMax
	PP_Oil_MinPressure : REAL; // 油路最低压力(MPa) = PMin
	PP_Oil_Frequency : REAL; // 油路脉冲频率(Hz)
	PP_Oil_WaveType : REAL; // 波形类型 0=正弦 1=梯形 2=ARP1383水锤波
	PP_Oil_RisePct : REAL; // 梯形/水锤波上升段占比
	PP_Oil_HoldPct : REAL; // 梯形/水锤波保持段占比
	PP_Oil_FallPct : REAL; // 梯形/水锤波下降段占比
	PP_Oil_Overshoot : REAL; // 油路水锤波过冲幅值占比(默认0.10)，按ARP1383 Fig.2 容差
	PP_Oil_RingPct : REAL; // 油路水锤波过冲后稳定段占比(默认0.07)，指令直接给PMax
	PP_Oil_LowDwellPct : REAL; // 油路水锤波低保持段时间占比(默认0.48)，5段相对权重内部归一化
	PP_Oil_HighLimit : REAL; // 油路高压保护限值(MPa)
	PP_Oil_TargetCycles : REAL; // 目标循环次数
	PP_Oil_VBase : REAL; // 油路基础容积(m³) — 管路+缸体
	PP_Oil_VSpecimen : REAL; // 油路被试件容积(m³)
	PP_Oil_Kv : REAL; // 油路阀流量增益(m³/s/V/√Pa) — 由样本参数反推(诊断回读)
	PP_Oil_TauValve : REAL; // 油路阀时间常数(s) — 由样本参数反推(诊断回读)
	PP_Oil_ValveQnom : REAL; // 油路阀额定流量(L/min)，查阀样本
	PP_Oil_ValveDPnom : REAL; // 油路阀额定压降(bar/每节流边)，查阀样本
	PP_Oil_ValveUmax : REAL; // 油路阀额定信号最大值(V)
	PP_Oil_ValveDynMode : REAL; // 油路阀动态参数模式: 0=频响频率(Hz), 1=阶跃时间(ms)
	PP_Oil_ValveDynParam : REAL; // 油路阀动态参数: 模式0为-3dB频率(Hz), 模式1为阶跃时间(ms)
	PP_Oil_ILC_Enable : REAL; // 油路迭代学习控制使能
	PP_Oil_ILC_MaxIter : REAL; // 油路ILC最大迭代次数
	PP_Oil_ILC_LearningRate : REAL; // 油路ILC学习率(0~1)，0=使用容积自适应默认值
	PP_Oil_PID_Kp : REAL := 2.0; // 油路 PID 比例增益 (V/MPa)
	PP_Oil_PID_Ki : REAL := 0.5; // 油路 PID 积分增益 (V/MPa/s)
	PP_Oil_PID_Kd : REAL := 0.005; // 油路 PID 微分增益 (V·s/MPa)
	PP_Oil_CycleReset : REAL; // 油路循环计数清零命令(上升沿有效)
	PP_Hydro_HighLimit : REAL; // 液压站高压保护限值(MPa)
	PP_Hydro_TempLimit : REAL; // 液压油温度保护限值(°C)
	PP_Hydro_WorkingPressure : REAL; // 液压站工作压力设定值(MPa)，即供油压力Ps
	PP_Hydro_PumpCmd : REAL; // 液压泵启停命令
	PP_Hydro_MotorSpeed : REAL; // 液压泵电机转速设定值(rpm)
	PP_Sys_BetaE : REAL; // 液压油体积弹性模量(Pa)，默认1.4e9
	PP_Sys_CLeak : REAL; // 系统泄漏系数，默认1.0e-12
	PP_IO_OutputBits : REAL; // 数字量输出控制
	PP_IO_OilCircuitSel : REAL; // 油路选通
	PP_FrameCounter_PLC : REAL; // PLC帧计数器（每10ms递增）
	PP_SysState : REAL; // 系统状态 0=空闲 1=冲洗排气 3=运行 4=停止中 5=故障 (无 2: 直接控制无预加压)
	PP_AlarmFlags : REAL; // 报警标志(32bit映射至REAL)
	PP_TotalCyclesDone : REAL; // 累计完成循环次数
	PP_IO_InputBits : REAL; // 数字量输入状态
	PP_IO_OutputBits_FB : REAL; // 数字量输出状态回读
	PP_CommsState : REAL; // 通讯状态（内部使用）
	PP_FlushTimeRemaining : REAL; // 冲洗排气剩余时间(s)
	PP_StateReady : REAL; // 状态推进就绪标志
	PP_Oil_ActualPressure : REAL; // 油路实际压力(MPa)
	PP_Oil_SetpointPressure : REAL; // 油路当前给定压力(MPa)
	PP_Oil_PressureError : REAL; // 油路压力偏差(MPa)
	PP_Oil_ControlOutput : REAL; // 油路 MFF+ILC+PID 总控制输出(V)
	PP_Oil_ValveCurrent : REAL; // 油路比例阀电流(mA)
	PP_Oil_CyclesDone : REAL; // 油路已完成循环次数
	PP_Oil_Frequency_FB : REAL; // 油路实际频率回读(Hz)
	PP_Oil_WavePhase : REAL; // 油路波形相位角(°)
	PP_Oil_PeakPressure : REAL; // 油路本次脉冲峰值压力(MPa)
	PP_Oil_TargetUpper : REAL; // 油路 ARP1383C 上包络 (MPa) — 实际压力允许上限
	PP_Oil_TargetLower : REAL; // 油路 ARP1383C 下包络 (MPa) — 实际压力允许下限
	PP_Oil_EnvPctP : REAL; // ARP1383C 包络压力容差 ×PMax (默认 0.05 = 5%)
	PP_Oil_EnvPctT : REAL; // ARP1383C 包络时间容差 ×周期 (默认 0.10 = 10%)
	PP_Oil_MFF_Output : REAL; // 油路模型前馈输出(V)
	PP_Oil_ILC_Output : REAL; // 油路ILC学习输出(V)
	PP_Oil_ILC_Iteration : REAL; // 油路ILC当前迭代次数
	PP_Oil_PID_Output : REAL; // 油路 PID 反馈输出(V)
	PP_Oil_PID_Integral : REAL; // 油路 PID 积分项(V) (诊断)
	PP_Hydro_Pressure : REAL; // 液压站系统压力(MPa)
	PP_Hydro_Temperature : REAL; // 液压油温度(°C)
	PP_Hydro_OilLevel : REAL; // 液位值(mm)
	PP_Hydro_PumpStatus : REAL; // 液压泵运行状态
	PP_Hydro_FilterStatus : REAL; // 过滤器状态
	PP_Hydro_PumpRunTime : REAL; // 液压泵累计运行时间(h)
	PP_PLC_ScanCycle : REAL; // PLC扫描周期实测值(ms)
	PP_TCPIP_CommCycle : REAL; // TCP/IP实际通讯周期(ms)
	PP_PLC_Timestamp_Low : REAL; // PLC时间戳低32位(ms)
	PP_PLC_Timestamp_High : REAL; // PLC时间戳高32位

	// =========================================================
	// 设备控制接口占位 (PRG_DeviceControl 待重写后填充)
	// 这些 GVL 变量取代了原 PRG_DeviceControl 的 toPC_*/fromPC_* 接口，
	// 由具体的设备驱动程序（待写）负责读写。
	// =========================================================
	PP_Dev_Pressure_26_01 : REAL; // 油路低压传感器(MPa) ← 由 HydraulicUnit_Control 写入
	PP_Dev_Pressure_27_01 : REAL; // 油路高压传感器(MPa) ← 由 HydraulicUnit_Control 写入
	PP_Dev_PneValve_YV7 : REAL; // 油路高压保护阀指令 → 待新 PRG_DeviceControl 读取并驱动硬件
END_VAR
