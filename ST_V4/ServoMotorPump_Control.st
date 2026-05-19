PROGRAM ServoMotorPump_Control
VAR_INPUT
	SMP_Start : BOOL; // 伺服泵_启动
	SMP_Stop : BOOL; // 伺服泵_停止
	SMP_Rest : BOOL; // 伺服泵_故障复位
	SMP_Pressure_InPut : REAL; // 伺服泵_压力设定值
	SMP_Flow_InPut : REAL; // 伺服泵_流量设定值
END_VAR
VAR_OUTPUT
	bOUT_1 : BOOL; // 伺服泵_故障
	rOUT_1 : REAL; // 伺服泵_压力反馈
	rOUT_2 : REAL; // 伺服泵_转速反馈
	rOUT_3 : REAL; // 伺服泵_流量反馈
END_VAR
VAR
	SMP_Out : BOOL; // 伺服泵_使能
	SMP_FAULT : BOOL; // 伺服泵故障
	SMP_FAULT_1 : BOOL; // 伺服泵故障1(启动超时)
	SMP_FAULT_2 : BOOL; // 伺服泵故障2(外部输入)
	TON_100 : TON; // 伺服泵_启动超时定时器
	TON_100_ET : TIME;
	AnalogCollect_X1_100 : AnalogCollect_X1; // ----实例化1(伺服泵_压力反馈)
	AnalogCollect_X1_101 : AnalogCollect_X1; // ----实例化2(伺服泵_转速反馈)
	SMP_Pressure_Temp : REAL; // 伺服泵_压力反馈[bar]
	SMP_Pressure_Feedback : REAL; // 伺服泵_压力反馈[MPa]
	SMP_RPM_Feedback : REAL; // 伺服泵_转速反馈
	CalculateTemp : ARRAY[0..1] OF REAL; // 流量换算中间值
	SMP_Flow_Feedback : REAL; // 伺服泵_流量反馈
	SMP_PressurePV_Temp : REAL; // 压力给定中间值
	AnalogOutput_X1_200 : AnalogOutput_X1; // ----实例化3(伺服泵_压力设定输出)
	AnalogOutput_X1_201 : AnalogOutput_X1; // ----实例化4.1(伺服泵_流量设定输出)
	AnalogOutput_X1_202 : AnalogOutput_X1; // ----实例化4.2(伺服泵_流量设定输出)
	CalculateTemp_2 : INT; // 流量设定换算中间值
END_VAR
END_PROGRAM
