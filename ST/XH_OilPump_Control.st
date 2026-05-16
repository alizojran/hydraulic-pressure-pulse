PROGRAM XH_OilPump_Control
VAR
	XH_OilPump_Out : BOOL; // 循环泵_使能
	XH_OilPump_FAULT : BOOL; // 循环泵故障
	XH_OilPump_FAULT_1 : BOOL; // 循环泵故障1(启动超时)
	XH_OilPump_FAULT_2 : BOOL; // 循环泵故障2(外部输入)
	TON_130 : TON; // 循环泵_启动超时定时器
	TON_130_ET : TIME;
END_VAR
VAR_INPUT
	XH_OilPump_Start : BOOL; // 循环泵_启动
	XH_OilPump_Stop : BOOL; // 循环泵_停止
	XH_OilPump_Rest : BOOL; // 循环泵_故障复位
END_VAR
VAR_OUTPUT
	bOUT_1 : BOOL; // 循环泵_故障
END_VAR

// ========================================
// Auto-converted from Ladder Diagram (LD)
// ========================================

// --- 循环泵_启动/停止 ---
XH_OilPump_Out := ((NOT XH_OilPump_FAULT AND XH_OilPump_Start) OR (NOT XH_OilPump_FAULT AND XH_OilPump_Out)) AND NOT XH_OilPump_Stop;

// --- 循环泵_使能输出 ---
GVL_GPIO.CT_222F_1_DO_6 := XH_OilPump_Out;

// --- 循环泵启动超时故障 ---
// Block: TON_130 (TON)
TON_130(
	IN := XH_OilPump_Out AND NOT GVL_GPIO.CT_121F_DI_4,
	PT := T#2S
);
TON_130_ET := TON_130.ET;

XH_OilPump_FAULT_1 := TON_130.Q;

// --- 循环泵外部输入故障 ---
XH_OilPump_FAULT_2 := GVL_GPIO.CT_121F_DI_5;

// --- 循环泵故障 ---
XH_OilPump_FAULT := ((XH_OilPump_FAULT_1) OR (XH_OilPump_FAULT_2) OR (XH_OilPump_FAULT)) AND NOT XH_OilPump_Rest;

// --- 循环泵故障_FB输出 ---
bOUT_1 := XH_OilPump_FAULT;

END_PROGRAM