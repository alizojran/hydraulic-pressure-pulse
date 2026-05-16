PROGRAM PRG_DeviceControl
VAR_INPUT
	fromPC_TD_Valve_10_01 : BOOL; // ------剂侧
	fromPC_TD_Valve_10_02 : BOOL; // 水侧
	fromPC_TD_Valve_10_03 : BOOL; // ------剂侧
	fromPC_TD_Valve_10_04 : BOOL; // 水侧
	fromPC_TD_Valve_24_01 : BOOL;
	fromPC_TD_Valve_30_01 : BOOL;
	fromPC_SMP_Start : BOOL; // *****************************************************//
*****************************************************//
	fromPC_SMP_Stop : BOOL;
	fromPC_SMP_Rest : BOOL;
	fromPC_SMP_Pressure_InPut : REAL;
	fromPC_SMP_Flow_InPut : REAL;
	fromPC_XH_OilPump_Start : BOOL; // 循环泵_启动(from-上位机)
	fromPC_XH_OilPump_Stop : BOOL; // 循环泵_停止(from-上位机)
	fromPC_XH_OilPump_Rest : BOOL; // 循环泵_故障复位(from-上位机)
	fromPC_HR_Pump1_Start : BOOL; // 换热泵1_启动(from-上位机)
	fromPC_HR_Pump1_Stop : BOOL; // 换热泵1_停止(from-上位机)
	fromPC_HR_Pump1_Rest : BOOL; // 换热泵1_故障复位(from-上位机)
	fromPC_HR_Pump1_Frequency_InPut : REAL;
	fromPC_HR_Pump2_Start : BOOL; // /换热泵1_频率设定(from-上位机)
	fromPC_HR_Pump2_Stop : BOOL; // 换热泵2_停止(from-上位机)
	fromPC_HR_Pump2_Rest : BOOL; // 换热泵2_故障复位(from-上位机)
	fromPC_HR_Pump2_Frequency_InPut : REAL;
	fromPC_Pne_Valve_YV1 : BOOL; // /换热泵2_频率设定(from-上位机)
	fromPC_Pne_Valve_YV2 : BOOL;
	fromPC_Pne_Valve_YV3 : BOOL;
	fromPC_Pne_Valve_YV4 : BOOL;
	fromPC_Pne_Valve_YV5 : BOOL;
	fromPC_Pne_Valve_YV6 : BOOL;
	fromPC_Pne_Valve_YV7 : BOOL;
	fromPC_Pne_Valve_YV8 : BOOL;
	fromPC_Pne_Valve_YV9 : BOOL;
	fromPC_Pne_Valve_YV10 : BOOL;
	fromPC_Pne_Valve_YV11 : BOOL;
	fromPC_Pne_Valve_YV12 : BOOL;
	fromPC_Pne_Valve_YV13 : BOOL;
	toPC_Filter_8_01 : BOOL; // 过滤器8.01发讯(to-上位机)
	toPC_Filter_16_01 : BOOL; // 过滤器16.01发讯(to-上位机)
	toPC_Filter_19_01 : BOOL; // 过滤器19.01发讯(to-上位机)
	toPC_HydraulicUnit_OilTemperature : REAL; // 液压站_油液温度(to-上位机)
	toPC_HydraulicUnit_OilLevel : REAL; // 液压站_油液液位(to-上位机)
	toPC_Pressure_32_01 : REAL; // 压力32.01(to-上位机)
	toPC_Pressure_32_02 : REAL; // 压力32.02(to-上位机)
	toPC_Pressure_32_03 : REAL; // 压力32.03(to-上位机)
	toPC_Pressure_32_04 : REAL; // 压力32.04(to-上位机)
	toPC_Pressure_25_01 : REAL; // 压力25.01(to-上位机)
	toPC_Pressure_26_01 : REAL; // 压力26.01(to-上位机)
	toPC_Pressure_27_01 : REAL; // 压力27.01(to-上位机)
	toPC_SMP_Pressure_Feedback : REAL; // 伺服泵_压力反馈(to-上位机)
	toPC_SMP_RPM_Feedback : REAL; // 伺服泵_转速反馈(to-上位机)
	toPC_SMP_Flow_Feedback : REAL; // 伺服泵_流量反馈(to-上位机)
END_VAR

//该程序段功能为调用脉冲动力站相关包含液压、辅机相关的控制程序


{*
1.水侧测试：开启10.02、10.04，关闭10.01、10.03

2.剂测测试：开启10.01、10.03，关闭10.02、10.04
*}

{*
  1.32.01为剂侧液压缸无杆腔压力，伺服阀A口压力
  2.32.03为剂侧液压缸有杆腔压力，伺服阀B口压力
  
  3.32.02为水侧液压缸无杆腔压力，伺服阀A口压力
  4.32.04为水侧液压缸有杆腔压力，伺服阀B口压力
  
  5.25.01为水侧产品端压力
  
  6.26.01为剂侧产品端低压力传感器，用于低压测试
  7.27.01为剂侧产品端15MPa压力传感器，用于爆破实验
*}



//------------------液压系统-控制子程序调用------------------//
PRG_HydraulicUnit_Control(
	TD_Valve_10_01:= fromPC_TD_Valve_10_01 , 
	TD_Valve_10_02:= fromPC_TD_Valve_10_02 , 
	TD_Valve_10_03:= fromPC_TD_Valve_10_03 , 
	TD_Valve_10_04:= fromPC_TD_Valve_10_04 , 
	TD_Valve_24_01:= fromPC_TD_Valve_24_01 , 
	TD_Valve_30_01:= fromPC_TD_Valve_30_01 , 
	bOUT_1=> toPC_Filter_8_01 , 
	bOUT_2=> toPC_Filter_16_01 , 
	bOUT_3=> toPC_Filter_19_01 , 
	rOUT_1=> toPC_HydraulicUnit_OilTemperature , 
	rOUT_2=> toPC_HydraulicUnit_OilLevel , 
	rOUT_3=> toPC_Pressure_32_01 , 
	rOUT_4=> toPC_Pressure_32_02 , 
	rOUT_5=> toPC_Pressure_32_03 , 
	rOUT_6=> toPC_Pressure_32_04 , 
	rOUT_7=> toPC_Pressure_25_01 , 
	rOUT_8=> toPC_Pressure_26_01 , 
	rOUT_9=> toPC_Pressure_27_01 );
//------------------液压系统-控制子程序调用------------------//


//------------------伺服泵-控制子程序调用------------------//
//上位机设定伺服泵压力
RAMP_Given.SMP_Pressure_SV :=fromPC_SMP_Pressure_InPut; 
//上位机设定伺服泵流量
RAMP_Given.SMP_Flow_SV :=fromPC_SMP_Flow_InPut;
//伺服泵控制	
ServoMotorPump_Control(
	SMP_Start:= fromPC_SMP_Start , 
	SMP_Stop:= fromPC_SMP_Stop , 
	SMP_Rest:= fromPC_SMP_Rest , 
	SMP_Pressure_InPut:= RAMP_Given.SMP_Pressure_SV_RAMP_OUT , 
	SMP_Flow_InPut:= RAMP_Given.SMP_Flow_SV_RAMP_OUT , 
	bOUT_1=> , 
	rOUT_1=> toPC_SMP_Pressure_Feedback , 
	rOUT_2=> toPC_SMP_RPM_Feedback , 
	rOUT_3=> toPC_SMP_Flow_Feedback );
//------------------伺服泵-控制子程序调用------------------//


//------------------循环泵-控制子程序调用------------------//
XH_OilPump_Control(
      XH_OilPump_Start:= fromPC_XH_OilPump_Start , 
      XH_OilPump_Stop:= fromPC_XH_OilPump_Stop , 
      XH_OilPump_Rest:= fromPC_XH_OilPump_Rest , 
      bOUT_1=> );
//------------------循环泵-控制子程序调用------------------//


//------------------换热泵1-控制子程序调用------------------//
RAMP_Given.HR_Pump1_Speed_SV:= fromPC_HR_Pump1_Frequency_InPut ;
HR_Pump1_Control(
	HR_Pump1_Start:= fromPC_HR_Pump1_Start , 
	HR_Pump1_Stop:= fromPC_HR_Pump1_Stop , 
	HR_Pump1_Rest:= fromPC_HR_Pump1_Rest , 
	HR_Pump1_Frequency_InPut:= RAMP_Given.HR_Pump1_Speed_SV_RAMP_OUT , 
	bOUT_1=> );
//------------------换热泵1-控制子程序调用------------------//


//------------------换热泵2-控制子程序调用------------------//
RAMP_Given.HR_Pump2_Speed_SV:= fromPC_HR_Pump2_Frequency_InPut ;
HR_Pump2_Control(
	HR_Pump2_Start:= fromPC_HR_Pump2_Start , 
	HR_Pump2_Stop:= fromPC_HR_Pump2_Stop , 
	HR_Pump2_Rest:= fromPC_HR_Pump2_Rest , 
	HR_Pump2_Frequency_InPut:= RAMP_Given.HR_Pump2_Speed_SV_RAMP_OUT , 
	bOUT_1=> );
//------------------换热泵2-控制子程序调用------------------//


//------------------气路电磁阀-控制子程序调用------------------//
PRG_PneumaticValve_Control(
	Pne_Valve_YV1:= fromPC_Pne_Valve_YV1 , 
	Pne_Valve_YV2:= fromPC_Pne_Valve_YV2 , 
	Pne_Valve_YV3:= fromPC_Pne_Valve_YV3 , 
	Pne_Valve_YV4:= fromPC_Pne_Valve_YV4 , 
	Pne_Valve_YV5:= fromPC_Pne_Valve_YV5 , 
	Pne_Valve_YV6:= fromPC_Pne_Valve_YV6 , 
	Pne_Valve_YV7:= fromPC_Pne_Valve_YV7 , 
	Pne_Valve_YV8:= fromPC_Pne_Valve_YV8 , 
	Pne_Valve_YV9:= fromPC_Pne_Valve_YV9 , 
	Pne_Valve_YV10:= fromPC_Pne_Valve_YV10 , 
	Pne_Valve_YV11:= fromPC_Pne_Valve_YV11 , 
	Pne_Valve_YV12:= fromPC_Pne_Valve_YV12 , 
	Pne_Valve_YV13:= fromPC_Pne_Valve_YV13 );
//------------------气路电磁阀-控制子程序调用------------------//

END_PROGRAM