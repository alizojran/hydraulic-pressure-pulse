PROGRAM PRG_PneumaticValve_Control
VAR_INPUT
	Pne_Valve_YV1 : BOOL; // 气动电磁阀YV1
	Pne_Valve_YV2 : BOOL; // 气动电磁阀YV2
	Pne_Valve_YV3 : BOOL; // 气动电磁阀YV3
	Pne_Valve_YV4 : BOOL; // 气动电磁阀YV4
	Pne_Valve_YV5 : BOOL; // 气动电磁阀YV5
	Pne_Valve_YV6 : BOOL; // 气动电磁阀YV6
	Pne_Valve_YV7 : BOOL; // 气动电磁阀YV7
	Pne_Valve_YV8 : BOOL; // 气动电磁阀YV8
	Pne_Valve_YV9 : BOOL; // 气动电磁阀YV9
	Pne_Valve_YV10 : BOOL; // 气动电磁阀YV10
	Pne_Valve_YV11 : BOOL; // 气动电磁阀YV11
	Pne_Valve_YV12 : BOOL; // 气动电磁阀YV12
	Pne_Valve_YV13 : BOOL; // 气动电磁阀YV13
END_VAR

// ========================================
// Auto-converted from Ladder Diagram (LD)
// ========================================

// --- 气动电磁阀_YV1 ---
GVL_GPIO.CT_222F_2_DO_0 := Pne_Valve_YV1;

// --- 气动电磁阀_YV2 ---
GVL_GPIO.CT_222F_2_DO_1 := Pne_Valve_YV2;

// --- 气动电磁阀_YV3 ---
GVL_GPIO.CT_222F_2_DO_2 := Pne_Valve_YV3;

// --- 气动电磁阀_YV4 ---
GVL_GPIO.CT_222F_2_DO_3 := Pne_Valve_YV4;

// --- 气动电磁阀_YV5 ---
GVL_GPIO.CT_222F_2_DO_4 := Pne_Valve_YV5;

// --- 气动电磁阀_YV6 ---
GVL_GPIO.CT_222F_2_DO_5 := Pne_Valve_YV6;

// --- 气动电磁阀_YV7 ---
GVL_GPIO.CT_222F_2_DO_6 := Pne_Valve_YV7;

// --- 气动电磁阀_YV8 ---
GVL_GPIO.CT_222F_2_DO_7 := Pne_Valve_YV8;

// --- 气动电磁阀_YV9 ---
GVL_GPIO.CT_222F_2_DO_8 := Pne_Valve_YV9;

// --- 气动电磁阀_YV10 ---
GVL_GPIO.CT_222F_2_DO_9 := Pne_Valve_YV10;

// --- 气动电磁阀_YV11 ---
GVL_GPIO.CT_222F_2_DO_10 := Pne_Valve_YV11;

// --- 气动电磁阀_YV12 ---
GVL_GPIO.CT_222F_2_DO_11 := Pne_Valve_YV12;

// --- 气动电磁阀_YV13 ---
GVL_GPIO.CT_222F_2_DO_12 := Pne_Valve_YV13;

END_PROGRAM