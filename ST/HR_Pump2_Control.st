PROGRAM HR_Pump2_Control
VAR
	HR_Pump2_Out : BOOL; // 换热泵2_使能
	HR_Pump2_FAULT : BOOL; // 换热泵2故障
	HR_Pump2_FAULT_1 : BOOL; // 换热泵2_故障1(启动超时)
	HR_Pump2_FAULT_2 : BOOL; // 换热泵2_故障2(外部输入)
	TON_151 : TON; // 换热泵2_启动超时定时器
	TON_151_ET : TIME;
	AnalogOutput_X1_301 : AnalogOutput_X1; // ----实例化1(换热泵2_转速(频率)设定输出)
END_VAR
VAR_INPUT
	HR_Pump2_Start : BOOL; // 换热泵2__启动
	HR_Pump2_Stop : BOOL; // 换热泵2__停止
	HR_Pump2_Rest : BOOL; // 换热泵2__故障复位
	HR_Pump2_Frequency_InPut : REAL; // 换热泵_转速(频率)设定值
END_VAR
VAR_OUTPUT
	bOUT_1 : BOOL; // 换热泵2_故障
END_VAR

// ========================================
// Auto-converted from Ladder Diagram (LD)
// ========================================

// --- 换热泵2_启动/停止 ---
HR_Pump2_Out := ((NOT HR_Pump2_FAULT AND HR_Pump2_Start) OR (NOT HR_Pump2_FAULT AND HR_Pump2_Out)) AND NOT HR_Pump2_Stop;

// --- 换热泵2_使能输出 ---
GVL_GPIO.CT_222F_1_DO_4 := HR_Pump2_Out;

// --- 换热泵2_启动超时 ---
// Block: TON_151 (TON)
TON_151(
	IN := HR_Pump2_Out AND NOT GVL_GPIO.CT_121F_DI_3,
	PT := T#5S
);
TON_151_ET := TON_151.ET;

HR_Pump2_FAULT_1 := TON_151.Q;

// --- 换热泵2_故障 ---
HR_Pump2_FAULT := ((HR_Pump2_FAULT_1) OR (HR_Pump2_FAULT)) AND NOT HR_Pump2_Rest;

// --- 换热泵2_故障FB输出 ---
bOUT_1 := HR_Pump2_FAULT;

// --- 换热泵2_故障复位 ---
GVL_GPIO.CT_222F_1_DO_5 := HR_Pump2_Rest;

// --- 换热泵2_转速(频率)给定 ---
// Block: AnalogOutput_X1_301 (AnalogOutput_X1)
AnalogOutput_X1_301(
	Input := HR_Pump2_Frequency_InPut,
	In_Hi_Limit := 50.0,
	In_Lo_Limit := 0.0,
	Out_Hi_Limit := 27648,
	Out_Lo_Limit := 0
);
GVL_GPIO.CT_4158_AO_3 := AnalogOutput_X1_301.OutPut;

END_PROGRAM