FUNCTION_BLOCK FB_HydraulicPID
VAR_INPUT
	bEnable : BOOL; // 使能
	rError : REAL; // 跟踪误差 r - y (MPa)
	rDt : REAL; // 控制周期 (s)
	bReset : BOOL; // 复位 PID 内部状态
	bResetIntegral : BOOL; // 仅复位积分项（相位切换用，不影响 P/D 输出）
	rPID_Kp : REAL := 0.3; // 比例增益 (V/MPa)
	rPID_Ki : REAL := 0.0; // 积分增益 (V/MPa/s)
	rPID_Kd : REAL := 0.0; // 微分增益 (V·s/MPa)
	rPID_Tf : REAL := 0.001; // 微分滤波时间常数 (s)
	rPID_Kb : REAL := 20.0; // 积分抗饱和增益 (1/s)
	rOutLimit : REAL := 10.0; // 输出限幅 (V)
END_VAR
VAR_OUTPUT
	rOutput : REAL; // 反馈控制输出 (V)
	rPID_P : REAL; // 比例项 (诊断)
	rPID_I : REAL; // 积分项 (诊断)
	rPID_D : REAL; // 微分项 (诊断)
END_VAR
VAR
	rIntegral : REAL;
	rDfilt : REAL;
	rErrorPrev : REAL;
	rOutputRaw : REAL; // 限幅前的 PID 输出 (用于抗饱和)
	rUfb : REAL;
END_VAR

// 复位
IF bReset OR NOT bEnable THEN
	rIntegral := 0.0;
	rDfilt := 0.0;
	rErrorPrev := 0.0;
	rOutputRaw := 0.0;
	rOutput := 0.0;
	rPID_P := 0.0;
	rPID_I := 0.0;
	rPID_D := 0.0;
	RETURN;
END_IF

IF rDt < 1.0E-6 THEN
	rOutput := 0.0;
	RETURN;
END_IF

// 仅复位积分（不影响输出，相位切换时清掉 hold 段累积的 I）
IF bResetIntegral THEN
	rIntegral := 0.0;
	rPID_I := 0.0;
END_IF

// 比例项
rPID_P := rPID_Kp * rError;

// 微分项 (带一阶滤波)
IF rPID_Tf > rDt THEN
	rDfilt := rDfilt + (rDt / rPID_Tf) * (rPID_Kd * (rError - rErrorPrev) / rDt - rDfilt);
ELSE
	rDfilt := rPID_Kd * (rError - rErrorPrev) / rDt;
END_IF
rPID_D := rDfilt;

// 积分项 (带 back-calculation 抗饱和)
rIntegral := rIntegral + rPID_Ki * (rError + rPID_Kb * (rOutput - rOutputRaw)) * rDt;
IF rIntegral > rOutLimit THEN rIntegral := rOutLimit; END_IF
IF rIntegral < -rOutLimit THEN rIntegral := -rOutLimit; END_IF
rPID_I := rIntegral;

// 合成 + 限幅
rOutputRaw := rPID_P + rPID_I + rPID_D;
rUfb := rOutputRaw;
IF rUfb > rOutLimit THEN rUfb := rOutLimit; END_IF
IF rUfb < -rOutLimit THEN rUfb := -rOutLimit; END_IF
rOutput := rUfb;

rErrorPrev := rError;
END_FUNCTION_BLOCK
