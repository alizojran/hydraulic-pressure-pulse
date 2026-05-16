PROGRAM HR_Pump1_Control
VAR
	HR_Pump1_Out : BOOL; // 换热泵1_使能
	HR_Pump1_FAULT : BOOL; // 换热泵1故障
	HR_Pump1_FAULT_1 : BOOL; // 换热泵1_故障1(启动超时)
	HR_Pump1_FAULT_2 : BOOL; // 换热泵1_故障2(外部输入)
	TON_150 : TON; // 换热泵1_启动超时定时器
	TON_150_ET : TIME;
	AnalogOutput_X1_300 : AnalogOutput_X1; // ----实例化1(换热泵1_转速(频率)设定输出)
END_VAR
VAR_INPUT
	HR_Pump1_Start : BOOL; // 换热泵1__启动
	HR_Pump1_Stop : BOOL; // 换热泵1__停止
	HR_Pump1_Rest : BOOL; // 换热泵1__故障复位
	HR_Pump1_Frequency_InPut : REAL; // 换热泵1_转速(频率)设定值
END_VAR
VAR_OUTPUT
	bOUT_1 : BOOL; // 换热泵1_故障
END_VAR

// ========================================
// Auto-converted from Ladder Diagram (LD)
// ========================================

// --- 换热泵1_启动/停止 ---
HR_Pump1_Out := ((NOT HR_Pump1_FAULT AND HR_Pump1_Start) OR (NOT HR_Pump1_FAULT AND HR_Pump1_Out)) AND NOT HR_Pump1_Stop;

// --- 换热泵1_使能输出 ---
GVL_GPIO.CT_222F_1_DO_2 := HR_Pump1_Out;

// --- 换热泵1_启动超时 ---
// Block: TON_150 (TON)
TON_150(
	IN := HR_Pump1_Out AND NOT GVL_GPIO.CT_121F_DI_2,
	PT := T#5S
);
TON_150_ET := TON_150.ET;

HR_Pump1_FAULT_1 := TON_150.Q;

// --- 换热泵1_故障 ---
HR_Pump1_FAULT := ((HR_Pump1_FAULT_1) OR (HR_Pump1_FAULT)) AND NOT HR_Pump1_Rest;

// --- 换热泵1_故障FB输出 ---
bOUT_1 := HR_Pump1_FAULT;

// --- 换热泵1_故障复位 ---
GVL_GPIO.CT_222F_1_DO_3 := HR_Pump1_Rest;

// --- 换热泵1_转速(频率)给定 ---
// Block: AnalogOutput_X1_300 (AnalogOutput_X1)
AnalogOutput_X1_300(
	Input := HR_Pump1_Frequency_InPut,
	In_Hi_Limit := 50.0,
	In_Lo_Limit := 0.0,
	Out_Hi_Limit := 27648,
	Out_Lo_Limit := 0
);
GVL_GPIO.CT_4158_AO_2 := AnalogOutput_X1_300.OutPut;

END_PROGRAM