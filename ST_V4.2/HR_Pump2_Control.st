PROGRAM HR_Pump2_Control
VAR_INPUT
	HR_Pump2_Start : BOOL; // 换热泵2__启动
	HR_Pump2_Stop : BOOL; // 换热泵2__停止
	HR_Pump2_Rest : BOOL; // 换热泵2__故障复位
	HR_Pump2_Frequency_InPut : REAL; // 换热泵_转速(频率)设定值
END_VAR
VAR_OUTPUT
	bOUT_1 : BOOL; // 换热泵2_故障
END_VAR
VAR
	HR_Pump2_Out : BOOL; // 换热泵2_使能
	HR_Pump2_FAULT : BOOL; // 换热泵2故障
	HR_Pump2_FAULT_1 : BOOL; // 换热泵2_故障1(启动超时)
	HR_Pump2_FAULT_2 : BOOL; // 换热泵2_故障2(外部输入)
	TON_151 : TON; // 换热泵2_启动超时定时器
	TON_151_ET : TIME;
	AnalogOutput_X1_301 : AnalogOutput_X1; // ----实例化1(换热泵2_转速(频率)设定输出)
END_VAR
END_PROGRAM
