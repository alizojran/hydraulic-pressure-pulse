FUNCTION_BLOCK PhysicalModel
VAR_INPUT
	Mode : INT;
	K : REAL; // gain
	T : REAL; // 时间常熟
	D : REAL; // 自然频率Hz
	Ts : REAL := 0.001; // 默认周期1ms
	u : REAL;
END_VAR
VAR_OUTPUT
	y : REAL;
END_VAR
VAR
	u_1 : REAL;
	u_2 : REAL;
	y_1 : REAL;
	y_2 : REAL;
	int1 : OSCAT_BASIC.INTEGRATE;
	int2 : OSCAT_BASIC.INTEGRATE;
	tn2 : REAL;
	I1 : REAL;
	I2 : REAL;
END_VAR

CASE Mode OF 
	//默认
	 1: //一阶惯性
	   //G(s) = K / (T*s + 1)
       // G(s) 差分方程 = (K*Ts*z + K*Ts)/((2*T + Ts)*z + Ts - 2*T)
	   y := (K*Ts*u + K*Ts*u_1-y_1*(Ts-2*T))/(2*T + Ts);
	   y_1:=y;
	   u_1:=u;
	 2://二阶方程
	  tn2 := T * T;
	  int1(X := u * K / tn2 - I1 * 0.5 * D / T - I2 / TN2, Y := I1);
	  int2(X := I1,Y := I2);
	  y := I2;	
END_CASE

END_FUNCTION_BLOCK