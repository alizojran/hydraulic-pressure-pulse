PROGRAM XH_OilPump_Control
VAR_INPUT
	XH_OilPump_Start : BOOL; // 循环泵_启动
	XH_OilPump_Stop : BOOL; // 循环泵_停止
	XH_OilPump_Rest : BOOL; // 循环泵_故障复位
END_VAR
VAR_OUTPUT
	bOUT_1 : BOOL; // 循环泵_故障
END_VAR
VAR
	XH_OilPump_Out : BOOL; // 循环泵_使能
	XH_OilPump_FAULT : BOOL; // 循环泵故障
	XH_OilPump_FAULT_1 : BOOL; // 循环泵故障1(启动超时)
	XH_OilPump_FAULT_2 : BOOL; // 循环泵故障2(外部输入)
	TON_130 : TON; // 循环泵_启动超时定时器
	TON_130_ET : TIME;
END_VAR
END_PROGRAM
