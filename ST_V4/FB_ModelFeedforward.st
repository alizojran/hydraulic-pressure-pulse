FUNCTION_BLOCK FB_ModelFeedforward
VAR_INPUT
	bEnable : BOOL; // 使能
	rTargetMPa : REAL; // 当前目标压力 (MPa)
	rTargetPrevMPa : REAL; // 上一步目标压力 (MPa)
	rDt : REAL; // 控制周期 (s)
	rBetaE : REAL; // 体积弹性模量 (Pa), 默认1.4e9
	rVTotal : REAL; // 系统总容积 (m³)
	rPs : REAL; // 供油压力 (Pa)
	rCLeak : REAL; // 泄漏系数
	rValveQnom : REAL; // 阀额定流量 (L/min)，样本直接查
	rValveDPnom : REAL; // 阀额定压降 (bar/每节流边)，样本直接查
	rValveUmax : REAL; // 阀额定信号最大值 (V)，通常10V
	iValveDynMode : INT; // 阀动态参数模式: 0=频响频率(Hz), 1=阶跃响应时间(ms)
	rValveDynParam : REAL; // 模式0: -3dB频率(Hz); 模式1: 阶跃响应时间(ms)
END_VAR
VAR_OUTPUT
	rOutput : REAL; // 前馈控制电压 (V)
	rQRequired : REAL; // 所需流量 (诊断用)
	rKv_Calc : REAL; // 反推得到的阀流量增益 Kv (诊断用)
	rTauValve_Calc : REAL; // 反推得到的阀时间常数 τv (诊断用)
END_VAR
VAR
	rUffPrev : REAL; // 上一步前馈电压（阀补偿用）
	bFirstRun : BOOL := TRUE;
	rKv : REAL; // 由样本参数反推的阀流量增益 (m³/s/V/√Pa)
	rTauValve : REAL; // 由样本参数反推的阀时间常数 (s)
	rTargetPa : REAL; // 目标压力 (Pa)
	rTargetPrevPa : REAL; // 上一步目标压力 (Pa)
	rDPdt : REAL; // 目标压力变化率 (Pa/s)
	rP : REAL; // 当前目标压力 (Pa)
	rDeltaP : REAL; // 阀口压差 (Pa)
	rUff : REAL; // 前馈电压 (V)
	rDUdt : REAL; // 前馈电压变化率 (V/s)
	rAreaRatio : REAL; // 面积比 A_iso/A_drive (隔离缸放大倍数)
	rPOil : REAL; // 油侧压力 (Pa) = P_test × 面积比
END_VAR

// ============================================================
// 主计算
// ============================================================

IF NOT bEnable THEN
    rOutput := 0.0;
    rQRequired := 0.0;
    rUffPrev := 0.0;
    bFirstRun := TRUE;
    RETURN;
END_IF

// ============================================================
// 从阀样本参数反推 Kv 和 τv
// ============================================================
// 【Kv 反推公式】
// 阀流量方程: Q = Kv × U × √ΔP
// 样本给出: Qnom (L/min) @ ΔPnom (bar/每节流边), Umax (V)
// 反解: Kv = (Qnom / 60000) / (Umax × √(ΔPnom × 1E5))
//   - Qnom / 60000: L/min → m³/s
//   - ΔPnom × 1E5: bar → Pa
//
// 以 Parker D3FP E50Y 为例:
//   Qnom=100 L/min, ΔPnom=35 bar, Umax=10V
//   Kv = (100/60000) / (10 × √(35×1E5))
//      = 1.667E-3 / (10 × 1870.8) = 8.91E-8 m³/s/V/√Pa
//
IF rValveQnom > 0.1 AND rValveDPnom > 0.1 AND rValveUmax > 0.1 THEN
    rKv := (rValveQnom / 60000.0) / (rValveUmax * SQRT(rValveDPnom * 1.0E5));
ELSE
    rKv := 8.91E-8;  // 默认值 (D3FP 100L/min @ 35bar)
END_IF

// 【τv 反推公式】
// 模式0 — 频响模式 (更精确):
//   阀近似一阶惯性 G(s) = 1/(τs+1)
//   -3dB频率 f₋₃dB 处 |G(jω)| = 1/√2
//   → τv = 1 / (2π × f₋₃dB)
//   D3FP: f₋₃dB=200Hz → τv = 1/(2π×200) = 0.000796s
//
// 模式1 — 阶跃响应模式:
//   样本给出100%阶跃响应时间(通常定义为到达±5%即95%稳态)
//   一阶系统 t₉₅ ≈ 3τ → τv = t_step / 3.0
//   D3FP: t_step<6ms → τv ≈ 6/3000 = 0.002s
//
IF iValveDynMode = 0 THEN
    IF rValveDynParam > 1.0 THEN
        rTauValve := 1.0 / (6.2832 * rValveDynParam);
    ELSE
        rTauValve := 0.0008;  // 默认200Hz
    END_IF
ELSE
    IF rValveDynParam > 0.1 THEN
        rTauValve := (rValveDynParam / 1000.0) / 3.0;
    ELSE
        rTauValve := 0.002;   // 默认6ms阶跃
    END_IF
END_IF

// 诊断输出
rKv_Calc := rKv;
rTauValve_Calc := rTauValve;

// ============================================================
// 隔离缸面积比 (固定结构常量)
// ============================================================
// 系统结构: 伺服阀 → 驱动缸(A_drive) → 机械耦合 → 隔离缸(A_iso) → 试验腔
//
// 物理关系:
//   活塞速度: v = Q_valve / A_drive
//   试验腔体积变化率: dV_test/dt = A_iso × v = AREA_RATIO × Q_valve
//   压力变化率: dP_test/dt = (βe/V_test) × AREA_RATIO × Q_valve
//
// 力平衡(忽略惯性摩擦):
//   P_oil × A_drive = P_test × A_iso
//   → P_oil = P_test × AREA_RATIO
//

// 参数保护
IF rDt < 1.0E-6 OR rKv < 1.0E-15 OR rBetaE < 1.0E6 OR rVTotal < 1.0E-8 THEN
    rOutput := 0.0;
    RETURN;
END_IF


    // MPa → Pa
    // 【单位转换】所有物理计算在 SI 单位制 (Pa, m³, m³/s) 下进行，
    // 输入以 MPa 为单位是为了方便上位机配置，内部统一升六阶到 Pa。
    rTargetPa := rTargetMPa * 1.0E6;
    rTargetPrevPa := rTargetPrevMPa * 1.0E6;

    // 步骤①: 目标压力变化率
    // 【dP/dt 的数值微分】
    // 用后向差分近似: dP/dt ≈ (P_k - P_{k-1}) / dt
    // 这是因果可实现的最简单微分方法。
    // 精度依赖 dt 足够小（本系统 dt=1ms，对应最高频率 1kHz，远高于信号带宽）。
    rDPdt := (rTargetPa - rTargetPrevPa) / rDt;

    rP := rTargetPa;

    // 步骤②: 所需流量 = (dP/dt * V / βe) / AreaRatio + Cleak * P_oil
    // 【带隔离缸的逆模型推导】
    // 试验腔压力方程:
    //   dP_test/dt = (βe / V_test) × (A_iso/A_drive) × Q_valve  ... (1')
    // 反解阀流量:
    //   Q_valve = (dP_test/dt × V_test / βe) / (A_iso/A_drive)
    //           = (dP_test/dt × V_test) / (βe × AreaRatio)       ... (8')
    // 加上泄漏补偿(泄漏发生在油侧，P_oil = P_test × AreaRatio):
    //   Q_total = Q_valve + Cleak × P_oil
    //
    // 当 AreaRatio=1 时退化为原始公式: Q = dP/dt × V / βe + Cleak × P
    //
    rPOil := rP * AREA_RATIO;  // 油侧压力
    rQRequired := (rDPdt * rVTotal / rBetaE) / AREA_RATIO + rCLeak * rPOil;

    // 步骤③: 反解阀控电压 u = Q / (Kv * √ΔP)
    // 【四通阀压差模型】
    // 四通对称阀 + 对称缸: 无论升压还是降压，都是从Ps供油驱动活塞运动
    //   升压(u>0): A口供油→伸出侧有杆腔, B口回油←缩回侧有杆腔 → 活塞伸出 → 隔离活塞排液 → 压力升
    //   降压(u<0): B口供油→缩回侧有杆腔, A口回油←伸出侧有杆腔 → 活塞缩回 → 隔离活塞吸液 → 压力降
    // 两个方向ΔP公式相同: ΔP = Ps - P_oil，输出连续无跳变
    //
    rDeltaP := rPs - ABS(rPOil);
    IF rDeltaP < MIN_DELTA_P THEN rDeltaP := MIN_DELTA_P; END_IF
    rUff := rQRequired / (rKv * SQRT(rDeltaP));

    // 限幅
    IF rUff > OUTPUT_LIMIT THEN rUff := OUTPUT_LIMIT; END_IF
    IF rUff < -OUTPUT_LIMIT THEN rUff := -OUTPUT_LIMIT; END_IF

    // 步骤④: 阀动态超前补偿 u_comp = u_ff + τv * du_ff/dt
    // 【阀动态补偿的目的】
    // 伺服阀是一个一阶惯性环节: G_valve(s) = 1 / (τv*s + 1)
    // 当输入阶跃电压时，阀开口不是瞬间到位，而是以时间常数 τv 指数跟踪。
    // 这导致前馈信号 u_ff 到达阀后，实际流量 Q_actual 对 u_ff 有 τv 的延迟。
    // 在压力脉冲控制中（频率可达数 Hz 到数十 Hz），这种阀延迟会引起相位滞后，
    // 使压力跟踪出现固定的滞后误差。
    //
    // 补偿方法——零相位误差前馈补偿:
    //   设理想（无延迟）响应为 y_desired，阀的传递函数为 G_v，
    //   则需要给阀的输入为 u_comp = G_v^{-1} * u_ff
    //   对一阶惯性: G_v^{-1}(s) = τv*s + 1
    //   对应时域: u_comp(t) = u_ff(t) + τv * du_ff/dt
    //
    //   直觉理解: 如果 u_ff 正在上升(du_ff/dt > 0)，
    //   则提前多加 τv*du_ff/dt 的电压让阀提前动作，
    //   当 u_ff 达到目标值时阀芯刚好到位，消除惯性延迟。
    //
    // 这是前馈补偿，不改变闭环稳定性（因为不依赖反馈信号）。
    //
    // 【首次运行处理——防止启动尖峰】
    // 第一个扫描周期时，rUffPrev 初始值为 0（功能块初始化默认值），
    // 而 rUff 的第一个计算值可能较大（特别是初始目标压力非零时），
    // 此时 du_ff/dt = (rUff - 0) / dt 会产生一个巨大的伪微分值，
    // 叠加到 u_comp 上造成启动瞬间电压尖峰。
    // bFirstRun 机制: 在第一次运行时令 rUffPrev := rUff，
    // 使得第二步开始的微分计算基于正确的初始值，
    // 而 bFirstRun 置 FALSE 使得第一个周期的 du/dt = 0（跳过补偿），
    // 从而避免启动尖峰。
    //
    IF bFirstRun THEN
        rUffPrev := rUff;
        bFirstRun := FALSE;
    END_IF

    rDUdt := (rUff - rUffPrev) / rDt;
    rOutput := rUff + rTauValve * rDUdt;

    // 最终限幅
    IF rOutput > OUTPUT_LIMIT THEN rOutput := OUTPUT_LIMIT; END_IF
    IF rOutput < -OUTPUT_LIMIT THEN rOutput := -OUTPUT_LIMIT; END_IF

    // 保存当前值
    rUffPrev := rUff;
END_FUNCTION_BLOCK
