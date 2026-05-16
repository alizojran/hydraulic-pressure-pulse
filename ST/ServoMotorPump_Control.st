PROGRAM ServoMotorPump_Control
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

// ========================================
// Auto-converted from Ladder Diagram (LD)
// ========================================

// --- 伺服泵_启动/停止 ---
SMP_Out := ((NOT SMP_FAULT AND SMP_Start) OR (NOT SMP_FAULT AND SMP_Out)) AND NOT SMP_Stop;

// --- 伺服泵_使能输出 ---
GVL_GPIO.CT_222F_1_DO_0 := SMP_Out;

// --- 伺服泵_启动超时故障 ---
// Block: TON_100 (TON)
TON_100(
	IN := SMP_Out AND NOT GVL_GPIO.CT_121F_DI_0,
	PT := T#3S
);
TON_100_ET := TON_100.ET;

SMP_FAULT_1 := TON_100.Q;

// --- 伺服泵_外部输入故障 ---
SMP_FAULT_2 := GVL_GPIO.CT_121F_DI_1;

// --- 伺服泵故障 ---
SMP_FAULT := ((SMP_FAULT_1) OR (SMP_FAULT_2) OR (SMP_FAULT)) AND NOT SMP_Rest;

// --- 伺服泵故障_FB输出 ---
bOUT_1 := SMP_FAULT;

// --- 伺服泵_故障复位 ---
GVL_GPIO.CT_222F_1_DO_1 := SMP_Rest;

// --- 伺服泵_压力反馈 ---
rOUT_1 := MOVE(SMP_Pressure_Feedback);

SMP_Pressure_Feedback := DIV(SMP_Pressure_Temp, 10.0);

// Block: AnalogCollect_X1_100 (AnalogCollect_X1)
AnalogCollect_X1_100(
	Input := GVL_GPIO.CT_3168_AI_0,
	In_Hi_Limit := 27648,
	In_Lo_Limit := 0,
	Out_Hi_Limit := 250.0,
	Out_Lo_Limit := 0.0
);
SMP_Pressure_Temp := AnalogCollect_X1_100.Collect_Out;

// --- 伺服泵_转速反馈 ---
rOUT_2 := MOVE(SMP_RPM_Feedback);

// Block: AnalogCollect_X1_101 (AnalogCollect_X1)
AnalogCollect_X1_101(
	Input := GVL_GPIO.CT_3168_AI_1,
	In_Hi_Limit := 27648,
	In_Lo_Limit := 0,
	Out_Hi_Limit := 1500.0,
	Out_Lo_Limit := 0.0
);
SMP_RPM_Feedback := AnalogCollect_X1_101.Collect_Out;

// --- 伺服泵_流量反馈(理论计算值)-------------//油泵排量=61.0cc ---
rOUT_3 := MOVE(SMP_Flow_Feedback);

SMP_Flow_Feedback := DIV(CalculateTemp[1], 1000);

CalculateTemp[1] := MUL(CalculateTemp[0], 1.0);

CalculateTemp[0] := MUL(61.0, SMP_RPM_Feedback);

// --- 伺服泵_压力给定 ---
// Block: AnalogOutput_X1_200 (AnalogOutput_X1)
AnalogOutput_X1_200(
	Input := SMP_PressurePV_Temp,
	In_Hi_Limit := 250.0,
	In_Lo_Limit := 0.0,
	Out_Hi_Limit := 27648,
	Out_Lo_Limit := 0
);
GVL_GPIO.CT_4158_AO_0 := AnalogOutput_X1_200.OutPut;

SMP_PressurePV_Temp := MUL(SMP_Pressure_InPut, 10.0);

// --- 伺服泵_流量给定 ---
// Block: AnalogOutput_X1_202 (AnalogOutput_X1)
IF AnalogOutput_X1_201.ENO THEN
	AnalogOutput_X1_202(
	Input := CalculateTemp_2,
	In_Hi_Limit := 1500.0,
	In_Lo_Limit := 0.0,
	Out_Hi_Limit := 27648,
	Out_Lo_Limit := 0
	);
END_IF
GVL_GPIO.CT_4158_AO_1 := AnalogOutput_X1_202.OutPut;

// Block: AnalogOutput_X1_201 (AnalogOutput_X1)
AnalogOutput_X1_201(
	Input := SMP_Flow_InPut,
	In_Hi_Limit := 91.5,
	In_Lo_Limit := 0.0,
	Out_Hi_Limit := 1500,
	Out_Lo_Limit := 0
);
CalculateTemp_2 := AnalogOutput_X1_201.OutPut;

END_PROGRAM