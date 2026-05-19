PROGRAM HR_Pump1_Control
VAR_INPUT
	HR_Pump1_Start : BOOL; // 换热泵1__启动
	HR_Pump1_Stop : BOOL; // 换热泵1__停止
	HR_Pump1_Rest : BOOL; // 换热泵1__故障复位
	HR_Pump1_Frequency_InPut : REAL; // 换热泵1_转速(频率)设定值
END_VAR
VAR_OUTPUT
	bOUT_1 : BOOL; // 换热泵1_故障
END_VAR
VAR
	HR_Pump1_Out : BOOL; // 换热泵1_使能
	HR_Pump1_FAULT : BOOL; // 换热泵1故障
	HR_Pump1_FAULT_1 : BOOL; // 换热泵1_故障1(启动超时)
	HR_Pump1_FAULT_2 : BOOL; // 换热泵1_故障2(外部输入)
	TON_150 : TON; // 换热泵1_启动超时定时器
	TON_150_ET : TIME;
	AnalogOutput_X1_300 : AnalogOutput_X1; // ----实例化1(换热泵1_转速(频率)设定输出)
END_VAR
END_PROGRAM
