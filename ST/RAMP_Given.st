PROGRAM RAMP_Given
VAR
	SMP_Pressure_SV_RAMP : Ramp; // 伺服泵_压力斜坡输出
	SMP_Flow_SV_RAMP : Ramp; // 伺服泵_流量斜坡输出
	HR_Pump1_Speed_SV_RAMP : Ramp; // 换热泵1_速度斜坡输出
	HR_Pump2_Speed_SV_RAMP : Ramp; // 换热泵1_速度斜坡输出
	CF_Var : ARRAY[0..3] OF BOOL;
	SMP_Pressure_SV_RAMP_OUT : REAL;
	SMP_Flow_SV_RAMP_OUT : REAL;
	HR_Pump1_Speed_SV_RAMP_OUT : REAL;
	HR_Pump2_Speed_SV_RAMP_OUT : REAL;
END_VAR
VAR_INPUT
	SMP_Pressure_SV : REAL; // 伺服泵_压力设定值(上位机)
	SMP_Flow_SV : REAL; // 伺服泵_流量设定值(上位机)
	HR_Pump1_Speed_SV : REAL; // 环热泵1_速度设定值(上位机)
	HR_Pump2_Speed_SV : REAL; // 环热泵2_速度设定值(上位机)
END_VAR


//伺服泵_压力设定RAMP函数
SMP_Pressure_SV_RAMP(
	Enable:= GVL_GPIO.CT_121F_DI_0 , 
	Stop:= TRUE , 
	Incre:= 0.5 , 
	InPut:= SMP_Pressure_SV , 
	Cycle:= T#10MS , 
	RampOut=> SMP_Pressure_SV_RAMP_OUT , 
	CF=> CF_Var[0] );




//伺服泵_流量设定RAMP函数
SMP_Flow_SV_RAMP(
	Enable:= GVL_GPIO.CT_121F_DI_0 , 
	Stop:= TRUE , 
	Incre:= 1.0 , 
	InPut:= SMP_Flow_SV , 
	Cycle:= T#10MS , 
	RampOut=> SMP_Flow_SV_RAMP_OUT , 
	CF=> CF_Var[1] );




//换热泵1_转速(频率)设定RAMP函数
HR_Pump1_Speed_SV_RAMP(
	Enable:= GVL_GPIO.CT_121F_DI_2 , 
	Stop:= TRUE , 
	Incre:= 1.0 , 
	InPut:= HR_Pump1_Speed_SV , 
	Cycle:= T#10MS , 
	RampOut=> HR_Pump1_Speed_SV_RAMP_OUT , 
	CF=> CF_Var[2] );


//换热泵2_转速(频率)设定RAMP函数
HR_Pump2_Speed_SV_RAMP(
	Enable:= GVL_GPIO.CT_121F_DI_3 , 
	Stop:= TRUE , 
	Incre:= 1.0 , 
	InPut:= HR_Pump2_Speed_SV , 
	Cycle:= T#10MS , 
	RampOut=> HR_Pump2_Speed_SV_RAMP_OUT , 
	CF=> CF_Var[3] );

END_PROGRAM