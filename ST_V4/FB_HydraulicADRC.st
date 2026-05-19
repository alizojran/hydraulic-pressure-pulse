FUNCTION_BLOCK FB_HydraulicADRC
VAR_INPUT
	bEnable : BOOL; // 使能
	rError : REAL; // 跟踪误差 r - y (MPa)
	rDt : REAL; // 控制周期 (s)
	rVTotal : REAL; // 系统总容积 (m³)
	bReset : BOOL; // 复位ESO状态
	nCtrlMode : INT := 0; // ============================================================
 控制模式选择
 0 = ADRC (默认)
 1 = 经典 PID
 ============================================================
	rBetaE : REAL; // 体积弹性模量 (Pa)
	rPs : REAL; // 供油压力 (Pa)
	rValveQnom : REAL; // 阀额定流量 (L/min)
	rValveDPnom : REAL; // 阀额定压降 (bar/每节流边)
	rValveUmax : REAL; // 阀额定信号最大值 (V)
	rOmegaCBase : REAL := 150.0; // 控制器带宽基准 (rad/s)
	rOmegaOBase : REAL := 800.0; // 观测器带宽基准 (rad/s)
	rVRef : REAL := 0.0007; // 参考容积 (m³)
	rPID_Kp : REAL := 2.0; // 比例增益 (V/MPa)
	rPID_Ki : REAL := 0.5; // 积分增益 (V/MPa/s)
	rPID_Kd : REAL := 0.005; // 微分增益 (V·s/MPa)
	rPID_Tf : REAL := 0.001; // 微分滤波时间常数 (s)
	rPID_Kb : REAL := 20.0; // 积分抗饱和增益 (1/s)
END_VAR
VAR_OUTPUT
	rOutput : REAL; // 反馈控制输出 (V)
	rZ1 : REAL; // ESO 误差估计 (诊断, ADRC模式)
	rZ2 : REAL; // ESO 扰动估计 (诊断, ADRC模式)
	rOmegaC : REAL; // 当前控制带宽 (诊断, ADRC模式)
	rB0 : REAL; // 当前标称增益 (诊断, ADRC模式)
	rPID_P : REAL; // PID比例项输出 (诊断, PID模式)
	rPID_I : REAL; // PID积分项输出 (诊断, PID模式)
	rPID_D : REAL; // PID微分项输出 (诊断, PID模式)
END_VAR
VAR
	z1 : REAL; // ESO 状态: 误差估计
	z2 : REAL; // ESO 状态: 扰动估计
	rUfbPrev : REAL; // 上一步反馈输出 (ESO需要)
	rB0Base : REAL; // 标称增益基准值
	bInitialized : BOOL; // 是否已初始化b0
	rKv : REAL; // 由样本参数反推的阀流量增益 (m³/s/V/√Pa)
	rAlpha : REAL; // 容积比 V_ref / V_total
	rOmegaO : REAL; // 观测器带宽 (rad/s)
	rBeta1 : REAL; // ESO 增益1
	rBeta2 : REAL; // ESO 增益2
	rEobs : REAL; // 观测误差 e - z1
	rKp : REAL; // 控制器比例增益
	rUfb : REAL; // 反馈控制电压 (V)
	rIntegral : REAL; // 积分累积值
	rDfilt : REAL; // 微分滤波后的值
	rErrorPrev : REAL; // 上一步误差 (用于微分)
	rOutputRaw : REAL; // 限幅前的PID输出 (用于抗饱和)
END_VAR

// ============================================================
// 主计算
// ============================================================

// 复位
IF bReset OR NOT bEnable THEN
    // ADRC 状态复位
    z1 := 0.0;
    z2 := 0.0;
    rUfbPrev := 0.0;
    // PID 状态复位
    rIntegral := 0.0;
    rDfilt := 0.0;
    rErrorPrev := 0.0;
    rOutputRaw := 0.0;
    // 输出清零
    rOutput := 0.0;
    rZ1 := 0.0;
    rZ2 := 0.0;
    rPID_P := 0.0;
    rPID_I := 0.0;
    rPID_D := 0.0;
    IF NOT bEnable THEN
        bInitialized := FALSE;
    END_IF
    RETURN;
END_IF

// 参数保护
IF rDt < 1.0E-6 THEN
    rOutput := 0.0;
    RETURN;
END_IF

// ============================================================
// 根据 nCtrlMode 选择控制算法
// ============================================================

IF nCtrlMode = 1 THEN
    // ============================================================
    // 经典 PID 控制器
    // ============================================================
    // 控制律: u = Kp*e + Ki*∫e*dt + Kd*de/dt(filtered)
    //
    // 微分项使用一阶低通滤波避免噪声放大:
    //   D_filt(k) = D_filt(k-1) + (dt/Tf) * (Kd*(e-e_prev)/dt - D_filt(k-1))
    //            = (1 - dt/Tf)*D_filt(k-1) + (Kd/Tf)*(e - e_prev)
    //   当 Tf → 0 时退化为纯微分
    //
    // 积分抗饱和 (back-calculation):
    //   当输出饱和时，用饱和误差反馈修正积分项:
    //   ∫e += (e + Kb*(u_sat - u_raw)) * dt
    //   Kb 越大，抗饱和越快
    //
    // ============================================================

    // --- 比例项 ---
    rPID_P := rPID_Kp * rError;

    // --- 微分项 (带滤波) ---
    IF rPID_Tf > rDt THEN
        // 一阶滤波微分
        rDfilt := rDfilt + (rDt / rPID_Tf) * (rPID_Kd * (rError - rErrorPrev) / rDt - rDfilt);
    ELSE
        // Tf 太小，直接用差分
        rDfilt := rPID_Kd * (rError - rErrorPrev) / rDt;
    END_IF
    rPID_D := rDfilt;

    // --- 积分项 (带抗饱和) ---
    // 使用 back-calculation: 积分输入 = e + Kb*(u_saturated - u_raw)
    rIntegral := rIntegral + rPID_Ki * (rError + rPID_Kb * (rOutput - rOutputRaw)) * rDt;

    // 积分限幅 (防止极端情况)
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

    // ADRC 诊断输出清零
    rZ1 := 0.0;
    rZ2 := 0.0;
    rOmegaC := 0.0;
    rB0 := 0.0;

ELSE
    // ============================================================
    // ADRC 控制器 (默认模式, nCtrlMode = 0)
    // ============================================================

    // 额外参数保护 (ADRC 需要容积和弹性模量)
    IF rVTotal < 1.0E-8 OR rBetaE < 1.0E6 THEN
        rOutput := 0.0;
        RETURN;
    END_IF

    // 从阀样本参数反推 Kv (与 FB_ModelFeedforward 相同的公式)
    IF rValveQnom > 0.1 AND rValveDPnom > 0.1 AND rValveUmax > 0.1 THEN
        rKv := (rValveQnom / 60000.0) / (rValveUmax * SQRT(rValveDPnom * 1.0E5));
    ELSE
        rKv := 8.91E-8;
    END_IF

    IF rKv < 1.0E-15 THEN
        rOutput := 0.0;
        RETURN;
    END_IF

    // ============================================================
    // 计算标称增益 b0 (首次或参数变化时)
    // b0 = (βe / V_total) * Kv * √(Ps/2) / 1e6   [MPa/s/V]
    // ============================================================
    IF NOT bInitialized THEN
        rB0Base := (rBetaE / rVTotal) * rKv * SQRT(rPs / 2.0) / 1.0E6;
        bInitialized := TRUE;
    END_IF

    // ============================================================
    // 容积自适应带宽
    // ============================================================
    rAlpha := rVRef / rVTotal;
    // 限幅
    IF rAlpha < 0.15 THEN rAlpha := 0.15; END_IF
    IF rAlpha > 5.0 THEN rAlpha := 5.0; END_IF

    // ωc = ωc_base * α^0.5,  ωo = ωo_base * α^0.4
    rOmegaC := rOmegaCBase * SQRT(rAlpha);
    rOmegaO := rOmegaOBase * EXP(0.4 * LN(rAlpha));

    // b0 不随容积缩放 — 初始化时已按实际容积计算
    rB0 := rB0Base;

    // ============================================================
    // ESO 增益 (带宽参数化)
    // β1 = 2*ωo,  β2 = ωo²
    // ============================================================
    rBeta1 := 2.0 * rOmegaO;
    rBeta2 := rOmegaO * rOmegaO;

    // ============================================================
    // ESO 观测更新 (欧拉积分)
    // dz1/dt = z2 + β1*(e - z1) - b0*u_fb_prev
    // dz2/dt = β2*(e - z1)
    // ============================================================
    rEobs := rError - z1;

    z1 := z1 + (z2 + rBeta1 * rEobs - rB0 * rUfbPrev) * rDt;
    z2 := z2 + (rBeta2 * rEobs) * rDt;

    // ============================================================
    // 控制律: u_fb = (kp * z1 + z2) / b0
    // 目标: de/dt = -ωc * e  (误差指数衰减)
    // ============================================================
    rKp := rOmegaC;

    IF ABS(rB0) > 1.0E-6 THEN
        rUfb := (rKp * z1 + z2) / rB0;
    ELSE
        rUfb := 0.0;
    END_IF

    // 输出限幅
    IF rUfb > OUTPUT_LIMIT THEN rUfb := OUTPUT_LIMIT; END_IF
    IF rUfb < -OUTPUT_LIMIT THEN rUfb := -OUTPUT_LIMIT; END_IF

    rOutput := rUfb;
    rUfbPrev := rUfb;

    // 诊断输出
    rZ1 := z1;
    rZ2 := z2;

    // PID 诊断输出清零
    rPID_P := 0.0;
    rPID_I := 0.0;
    rPID_D := 0.0;

END_IF
END_FUNCTION_BLOCK
