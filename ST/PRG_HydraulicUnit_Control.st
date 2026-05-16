PROGRAM PRG_HydraulicUnit_Control
VAR
	dwOil_CylinderPos : DWORD; // 剂侧油缸位置
	Oil_CylinderPos : REAL; // 剂侧油缸位置
	dwWater_CylinderPos : DWORD; // 水侧油缸位置
	Water_CylinderPos : REAL; // 水侧油缸位置
	Filter_8_01 : BOOL; // 压力过滤器8.01
	Filter_16_01 : BOOL; // 回油过滤器16.01
	Filter_19_01 : BOOL; // 回油过滤器19.01
	HydraulicUnit_OilTemperature : REAL; // 液压站_油液温度
	HydraulicUnit_OilLevel : REAL; // 液压站_油液液位
	AnalogCollect_X1_500 : AnalogCollect_X1; // ----实例化1(液压站_油液温度)
	AnalogCollect_X1_501 : AnalogCollect_X1; // ----实例化2(液压站_油液液位)
	Pressure_32_01 : REAL;
	Pressure_32_02 : REAL;
	Pressure_32_03 : REAL;
	Pressure_32_04 : REAL;
	AnalogCollect_X1_600 : AnalogCollect_X1; // ----实例化1(压力传感器_32.01)
	AnalogCollect_X1_601 : AnalogCollect_X1; // ----实例化2(压力传感器_32.02)
	AnalogCollect_X1_602 : AnalogCollect_X1; // ----实例化3(压力传感器_32.03)
	AnalogCollect_X1_603 : AnalogCollect_X1; // ----实例化4(压力传感器_32.04)
	Pressure_25_01 : REAL;
	Pressure_26_01 : REAL;
	Pressure_27_01 : REAL;
	AnalogCollect_X1_604 : AnalogCollect_X1; // ----实例化1(压力传感器_25.01)
	AnalogCollect_X1_605 : AnalogCollect_X1; // ----实例化2(压力传感器_26.01)
	AnalogCollect_X1_606 : AnalogCollect_X1; // ----实例化3(压力传感器_27.01)
	AnalogOutput_X1_700 : AnalogOutput_X1; // ----实例化1(压力传感器_25.01输出)
	AnalogOutput_X1_701 : AnalogOutput_X1; // ----实例化1(压力传感器_26.01输出)
	AnalogOutput_X1_702 : AnalogOutput_X1; // ----实例化1(压力传感器_27.01输出)
END_VAR
VAR_INPUT
	TD_Valve_10_01 : BOOL; // 通断阀10.01
	TD_Valve_10_02 : BOOL; // 通断阀10.02
	TD_Valve_10_03 : BOOL; // 通断阀10.03
	TD_Valve_10_04 : BOOL; // 通断阀10.04
	TD_Valve_24_01 : BOOL; // 通断阀24.01
	TD_Valve_30_01 : BOOL; // 通断阀30.01
END_VAR
VAR_OUTPUT
	bOUT_1 : BOOL; // 压力过滤器8.01
	bOUT_2 : BOOL; // 压力过滤器16.01
	bOUT_3 : BOOL; // 压力过滤器19.01
	rOUT_1 : REAL; // 液压站_油液温度
	rOUT_2 : REAL; // 液压站_油液液位
	rOUT_3 : REAL; // 压力32.01
	rOUT_4 : REAL; // 压力32.02
	rOUT_5 : REAL; // 压力32.03
	rOUT_6 : REAL; // 压力32.04
	rOUT_7 : REAL; // 压力25.01
	rOUT_8 : REAL; // 压力26.01
	rOUT_9 : REAL; // 压力27.01
END_VAR



//===============================剂侧液压油缸位置传感器(SSI)===============================//
               {*--------------传感器固定参数，请勿删除--------------*}
//剂侧(油路)液压油缸_高压(小油缸--内侧安装)

PWMotion.FPGAData.Axis1.SSILength:= 25; //SSI数据长度25位
PWmotion.FPGAData.Axis1.SSI_time := 300;  //SSI时钟
PWmotion.FPGAData.Axis1.Position_Coefficient := 0.001; //SSI位移传感器系数，分辨率=1μm]

PWmotion.FPGAData.Axis1.Position_ZERO := -51.786; //位置传感器零点标定----[根据实际值设定]

dwOil_CylinderPos := PWMotion.FPGAData.Axis1.SSI_DATA_Filter; //剂侧油缸位置(DWORD)-SSI读取
Oil_CylinderPos  := PWMotion.FPGAData.Axis1.FeedBackPosition; //剂侧油缸位置

//===============================水侧液压油缸位置传感器(SSI)===============================//
               {*--------------传感器固定参数，请勿删除--------------*}
//水侧液压油缸_低压(大油缸--外侧安装)

PWMotion.FPGAData.Axis2.SSILength:= 25; //SSI数据长度25位
PWmotion.FPGAData.Axis2.SSI_time := 300;  //SSI时钟
PWmotion.FPGAData.Axis2.Position_Coefficient := 0.001; //SSI位移传感器系数，分辨率=1μm]

PWmotion.FPGAData.Axis2.Position_ZERO := -51.31; //位置传感器零点标定----[根据实际值设定]

dwWater_CylinderPos := PWMotion.FPGAData.Axis2.SSI_DATA_Filter; //水侧油缸位置(DWORD)-SSI读取
Water_CylinderPos := PWMotion.FPGAData.Axis2.FeedBackPosition; //水侧油缸位置

//****************************************************************************************************************************//



{**************过滤器发讯信号采集**************}
//压力过滤器8.01发讯
IF GVL_GPIO.CT_121F_DI_8 =TRUE THEN
	Filter_8_01:= TRUE;
ELSIF GVL_GPIO.CT_121F_DI_8 =FALSE THEN
	Filter_8_01:= FALSE;
END_IF
bOUT_1 :=Filter_8_01;


//回油过滤器16.01
IF GVL_GPIO.CT_121F_DI_9 =TRUE THEN
	Filter_16_01:= TRUE;
ELSIF GVL_GPIO.CT_121F_DI_9 =FALSE THEN
	Filter_16_01:= FALSE;
END_IF
bOUT_2 :=Filter_16_01;

//回油过滤器19.01
IF GVL_GPIO.CT_121F_DI_10 =TRUE THEN
	Filter_19_01:= TRUE;
ELSIF GVL_GPIO.CT_121F_DI_10 =FALSE THEN
	Filter_19_01:= FALSE;
END_IF
bOUT_3 :=Filter_19_01;

{**************液压站通断阀控制**************}
//通断阀10.01
IF TD_Valve_10_01 =TRUE THEN
	GVL_GPIO.CT_222F_1_DO_8:= TRUE;
ELSIF TD_Valve_10_01 =FALSE THEN
	GVL_GPIO.CT_222F_1_DO_8:= FALSE;
END_IF

//通断阀10.02
IF TD_Valve_10_02 =TRUE THEN
	GVL_GPIO.CT_222F_1_DO_9:= TRUE;
ELSIF TD_Valve_10_02 =FALSE THEN
	GVL_GPIO.CT_222F_1_DO_9:= FALSE;
END_IF

//通断阀10.03
IF TD_Valve_10_03 =TRUE THEN
	GVL_GPIO.CT_222F_1_DO_10:= TRUE;
ELSIF TD_Valve_10_03 =FALSE THEN
	GVL_GPIO.CT_222F_1_DO_10:= FALSE;
END_IF

//通断阀10.04
IF TD_Valve_10_04 =TRUE THEN
	GVL_GPIO.CT_222F_1_DO_11:= TRUE;
ELSIF TD_Valve_10_04 =FALSE THEN
	GVL_GPIO.CT_222F_1_DO_11:= FALSE;
END_IF

//通断阀24.01
IF TD_Valve_24_01 =TRUE THEN
	GVL_GPIO.CT_222F_1_DO_12:= TRUE;
ELSIF TD_Valve_24_01 =FALSE THEN
	GVL_GPIO.CT_222F_1_DO_12:= FALSE;
END_IF

//通断阀30.01
IF TD_Valve_30_01 =TRUE THEN
	GVL_GPIO.CT_222F_1_DO_13:= TRUE;
ELSIF TD_Valve_30_01 =FALSE THEN
	GVL_GPIO.CT_222F_1_DO_13:= FALSE;
END_IF


//液压站_油液温度
AnalogCollect_X1_500(
	Input:= GVL_GPIO.CT_3238_2_AI_0 , 
	In_Hi_Limit:= 27648 , 
	In_Lo_Limit:= 0 , 
	Out_Hi_Limit:= 120.0 , 
	Out_Lo_Limit:= -40.0 , 
	Collect_Out=> HydraulicUnit_OilTemperature );
rOUT_1 := HydraulicUnit_OilTemperature;

//液压站_油液液位
AnalogCollect_X1_501(
	Input:= GVL_GPIO.CT_3238_2_AI_1 , 
	In_Hi_Limit:= 27648 , 
	In_Lo_Limit:= 0 , 
	Out_Hi_Limit:= 520.0 , 
	Out_Lo_Limit:= 0.0 , 
	Collect_Out=> HydraulicUnit_OilLevel );
 rOUT_2 := HydraulicUnit_OilLevel;
 
//压力传感器_32.01
AnalogCollect_X1_600(
	Input:= GVL_GPIO.CT_3238_1_AI_3 , 
	In_Hi_Limit:= 27648 , 
	In_Lo_Limit:= 0 , 
	Out_Hi_Limit:= 25.0 , 
	Out_Lo_Limit:= 0.0 , 
	Collect_Out=> Pressure_32_01 );
rOUT_3 :=Pressure_32_01;

//压力传感器_32.02
AnalogCollect_X1_601(
	Input:= GVL_GPIO.CT_3238_1_AI_4 , 
	In_Hi_Limit:= 27648 , 
	In_Lo_Limit:= 0 , 
	Out_Hi_Limit:= 25.0 , 
	Out_Lo_Limit:= 0.0 , 
	Collect_Out=> Pressure_32_02 );
rOUT_4 :=Pressure_32_02;

//压力传感器_32.03
AnalogCollect_X1_602(
	Input:= GVL_GPIO.CT_3238_1_AI_5 , 
	In_Hi_Limit:= 27648 , 
	In_Lo_Limit:= 0 , 
	Out_Hi_Limit:= 25.0 , 
	Out_Lo_Limit:= 0.0 , 
	Collect_Out=> Pressure_32_03 );
rOUT_5 :=Pressure_32_03;

//压力传感器_32.04
AnalogCollect_X1_603(
	Input:= GVL_GPIO.CT_3238_1_AI_6 , 
	In_Hi_Limit:= 27648 , 
	In_Lo_Limit:= 0 , 
	Out_Hi_Limit:= 25.0 , 
	Out_Lo_Limit:= 0.0 , 
	Collect_Out=> Pressure_32_04 );
rOUT_6 :=Pressure_32_04;

//****************************************************************************************************//

{*********控制器AD通道采集压力*********}
//压力传感器25.01
{AD1满量程0-32767；1-5V对应3277-16384}
AnalogCollect_X1_604(
	Input:= PWMotion.FPGAData.AD1 , 
	In_Hi_Limit:= 16384 , 
	In_Lo_Limit:= 3277 , 
	Out_Hi_Limit:= 1.6 , 
	Out_Lo_Limit:= 0.0 , 
	Collect_Out=> Pressure_25_01 );
rOUT_7 :=Pressure_25_01;

//压力传感器26.01
{AD2满量程0-32767；1-5V对应3277-16384}
AnalogCollect_X1_605(
	Input:= PWMotion.FPGAData.AD2 , 
	In_Hi_Limit:= 16384 , 
	In_Lo_Limit:= 3277 , 
	Out_Hi_Limit:= 5.0 , 
	Out_Lo_Limit:= 0.0 , 
	Collect_Out=> Pressure_26_01 );
rOUT_8 :=Pressure_26_01;

//压力传感器27.01
{AD3满量程0-32767；1-5V对应3277-16384}
AnalogCollect_X1_606(
	Input:= PWMotion.FPGAData.AD3 , 
	In_Hi_Limit:= 16384 , 
	In_Lo_Limit:= 3277 , 
	Out_Hi_Limit:= 15.0 , 
	Out_Lo_Limit:= 0.0 , 
	Collect_Out=> Pressure_27_01 );
rOUT_9 :=Pressure_27_01;

//---------------------------------------------------------------------------//
//CT-4158输出压力25.01
AnalogOutput_X1_700(
	Input:= PRG_PressureControl.Water_Pressure_Filter.out , 
	In_Hi_Limit:= 1.6 , 
	In_Lo_Limit:= 0.0 , 
	Out_Hi_Limit:= 27648 , 
	Out_Lo_Limit:= 0 , 
	OutPut=> GVL_GPIO.CT_4158_AO_4 );

//CT-4158输出压力26.01
AnalogOutput_X1_701(
	Input:= PRG_PressureControl.Oil_Pressure_Filter.out , 
	In_Hi_Limit:= 5.0 , 
	In_Lo_Limit:= 0.0 , 
	Out_Hi_Limit:= 27648 , 
	Out_Lo_Limit:= 0 , 
	OutPut=> GVL_GPIO.CT_4158_AO_5 );
	
//CT-4158输出压力26.01
AnalogOutput_X1_702(
	Input:= PRG_PressureControl.Oil_Pressure_Filter.out , 
	In_Hi_Limit:= 15.0 , 
	In_Lo_Limit:= 0.0 , 
	Out_Hi_Limit:= 27648 , 
	Out_Lo_Limit:= 0 , 
	OutPut=> GVL_GPIO.CT_4158_AO_6 );

END_PROGRAM