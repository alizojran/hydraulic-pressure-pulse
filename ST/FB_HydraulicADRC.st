FUNCTION_BLOCK FB_HydraulicADRC
// 名称沿用 FB_HydraulicADRC 以保持调用点不变。内部实现已精简为
// 经典 PID（比例 + 积分抗饱和 + 滤波微分），不再使用 ADRC/ESO。
VAR_INPUT
	bEnable : BOOL; // 使能
	rError : REAL; // 跟踪误差 r - y (MPa)
	rDt : REAL; // 控制周期 (s)
	bReset : BOOL; // 复位
	rPID_Kp : REAL := 2.0; // 比例增益 (V/MPa)
	rPID_Ki : REAL := 0.5; // 积分增益 (V/MPa/s)
	rPID_Kd : REAL := 0.005; // 微分增益 (V·s/MPa)
	rPID_Tf : REAL := 0.001; // 微分滤波时间常数 (s)
	rPID_Kb : REAL := 20.0; // 积分抗饱和增益 (1/s)
END_VAR
VAR_OUTPUT
	rOutput : REAL; // 反馈控制输出 (V)
	rPID_P : REAL; // 比例项 (诊断)
	rPID_I : REAL; // 积分项 (诊断)
	rPID_D : REAL; // 微分项 (诊断)
END_VAR
VAR
	rIntegral : REAL; // 积分累积值
	rDfilt : REAL; // 微分滤波后的值
	rErrorPrev : REAL; // 上一步误差
	rOutputRaw : REAL; // 限幅前的输出 (用于抗饱和)
	rUfb : REAL; // 反馈控制电压 (V)
END_VAR
VAR CONSTANT
	OUTPUT_LIMIT : REAL := 10.0; // 输出限幅 (V)
END_VAR


// ============================================================
// 复位
// ============================================================
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

// 周期保护
IF rDt < 1.0E-6 THEN
    rOutput := 0.0;
    RETURN;
END_IF

// ============================================================
// PID 控制律: u = Kp*e + Ki*∫e*dt + Kd*de/dt(filtered)
//
// 微分项用一阶低通滤波避免噪声放大:
//   D_filt(k) = (1 - dt/Tf)*D_filt(k-1) + (Kd/Tf)*(e - e_prev)
//   Tf → 0 时退化为纯微分
//
// 积分抗饱和 (back-calculation):
//   当输出饱和时用饱和误差反馈修正积分项:
//   ∫e += (e + Kb*(u_sat - u_raw)) * dt
//   Kb 越大抗饱和越快
// ============================================================

// --- 比例项 ---
rPID_P := rPID_Kp * rError;

// --- 微分项 (带滤波) ---
IF rPID_Tf > rDt THEN
    rDfilt := rDfilt + (rDt / rPID_Tf) * (rPID_Kd * (rError - rErrorPrev) / rDt - rDfilt);
ELSE
    rDfilt := rPID_Kd * (rError - rErrorPrev) / rDt;
END_IF
rPID_D := rDfilt;

// --- 积分项 (带抗饱和) ---
rIntegral := rIntegral + rPID_Ki * (rError + rPID_Kb * (rOutput - rOutputRaw)) * rDt;
IF rIntegral > OUTPUT_LIMIT THEN rIntegral := OUTPUT_LIMIT; END_IF
IF rIntegral < -OUTPUT_LIMIT THEN rIntegral := -OUTPUT_LIMIT; END_IF
rPID_I := rIntegral;

// --- 合成输出 ---
rOutputRaw := rPID_P + rPID_I + rPID_D;

// --- 输出限幅 ---
rUfb := rOutputRaw;
IF rUfb > OUTPUT_LIMIT THEN rUfb := OUTPUT_LIMIT; END_IF
IF rUfb < -OUTPUT_LIMIT THEN rUfb := -OUTPUT_LIMIT; END_IF
rOutput := rUfb;

// 保存上一步误差
rErrorPrev := rError;

END_FUNCTION_BLOCK
