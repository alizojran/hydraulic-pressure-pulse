FUNCTION_BLOCK FB_WaveformGen
VAR_INPUT
	bEnable : BOOL; // 使能
	rPMin : REAL; // 最低压力 (MPa)
	rPMax : REAL; // 最高压力 (MPa)
	rFrequency : REAL; // 脉冲频率 (Hz)
	iWaveType : INT; // 波形类型 0=正弦 1=方波 2=三角 3=梯形 4=自定义LUT
	rDutyCycle : REAL; // 方波占空比 (0~1)，默认0.5
	rRisePct : REAL; // 梯形波上升段占比，默认0.1
	rHoldPct : REAL; // 梯形波保持段占比，默认0.3
	rFallPct : REAL; // 梯形波下降段占比，默认0.1
	rDt : REAL; // 控制周期 (s)
	bReset : BOOL; // 复位相位
	nMffLeadSteps : INT; // MFF超前步数: 提前N步计算目标值给MFF使用
END_VAR
VAR_OUTPUT
	rTarget : REAL; // 当前目标压力 (MPa)
	rTargetPrev : REAL; // 上一步目标压力 (用于MFF计算dP/dt)
	rTargetLead : REAL; // 超前目标压力 (MPa) — 给MFF使用
	rTargetLeadPrev : REAL; // 超前目标上一步值 — 给MFF计算dP/dt
	rPhase : REAL; // 当前相位 (0~1)
	bNewCycle : BOOL; // 新周期开始脉冲 (相位过零)
	iPointIndex : INT; // 当前周期内采样点索引
	iPointsPerCycle : INT; // 每周期总采样点数
END_VAR
VAR
	rPhaseAcc : REAL; // 相位累加器 (0~1)
	rTargetLast : REAL; // 上一步计算值暂存
	rTargetLeadLast : REAL; // 超前目标上一步暂存
	bFirstRun : BOOL := TRUE;
	iIdxCounter : INT; // 采样点计数器
	arrLUT : ARRAY[0..1999] OF REAL; // 波形查找表 (MPa)
	iLutLen : INT; // 有效数据点数
	bLutValid : BOOL; // LUT数据有效标志
	rR : REAL; // 上升段占比
	rH : REAL; // 保持段占比
	rF : REAL; // 下降段占比
	rL : REAL; // 低保持段占比
	rPhaseLead : REAL; // 超前相位值
END_VAR
VAR CONSTANT
	MAX_LUT_POINTS : INT := 800; // LUT 最大点数（与 PP_WaveUpload_Data[0..799] 对齐）
	RISE_RATIO_SQUARE : REAL := 0.08; // 方波过渡段占比（8% 周期）
END_VAR

IF bReset OR NOT bEnable THEN
    rPhaseAcc := 0.0;
    rTarget := rPMin;
    rTargetPrev := rPMin;
    rTargetLast := rPMin;
    rTargetLead := rPMin;
    rTargetLeadPrev := rPMin;
    rTargetLeadLast := rPMin;
    bNewCycle := FALSE;
    bFirstRun := TRUE;
    iIdxCounter := 0;
    RETURN;
END_IF

// 频率保护
IF rFrequency < 0.01 THEN
    rTarget := rPMin;
    rTargetPrev := rPMin;
    RETURN;
END_IF

// 计算每周期采样点数
// 【每周期采样点数的物理含义】
// iPointsPerCycle = 1 / (f * dt) 表示一个完整波形周期被分成多少个采样点。
// 例如 f=1Hz, dt=1ms → iPointsPerCycle = 1000 点/周期。
// 点数太少会导致波形分辨率不足（如方波变成阶梯），
// 所以设下限 10 点保证基本波形质量。
iPointsPerCycle := REAL_TO_INT(1.0 / (rFrequency * rDt));
IF iPointsPerCycle < 10 THEN
    iPointsPerCycle := 10;
END_IF

// 保存上一步值
rTargetPrev := rTargetLast;

// 相位推进
// 【相位累加器机制】
// rPhaseAcc 是一个 0~1 的循环累加器，表示"当前在一个波形周期内的位置"。
// 每个扫描周期，相位增加 Δφ = f * dt:
//   - f=1Hz, dt=1ms → Δφ = 0.001，一个周期 1000 步走完 0→1
//   - f=5Hz, dt=1ms → Δφ = 0.005，一个周期 200 步走完
//
// rPhaseAcc 代表"归一化时间"，0=周期起点，1=周期终点。
// 相位与物理时间的对应: t = φ / f（秒）
//
// 使用累加器而非直接计时的原因:
//   (1) 避免浮点累积误差: 如果用 t = t + dt 然后取模，
//       长时间运行后 t 的浮点精度会下降（大数+小数）
//   (2) 相位本身是 [0,1) 的小数，累积误差可控
//   (3) 过零检测简单: rPhaseAcc >= 1.0 时减 1 即可
//
rPhaseAcc := rPhaseAcc + rFrequency * rDt;

// 检测新周期
IF rPhaseAcc >= 1.0 THEN
    // 相位超出 [0,1) 范围，回卷到 [0,1)
    // 注意: rPhaseAcc - 1.0 而非直接置零，保留小数部分避免相位跳变
    // 例如: rPhaseAcc = 1.003 → 修正后 = 0.003，保留了超出的 0.003 周期
    rPhaseAcc := rPhaseAcc - 1.0;
    bNewCycle := TRUE;
    iIdxCounter := 0;
ELSE
    bNewCycle := FALSE;
END_IF

rPhase := rPhaseAcc;
iPointIndex := iIdxCounter;

// ============================================================
// 波形计算
// ============================================================
CASE iWaveType OF

0:  // 正弦波 (-cos型，从PMin起步平滑上升)
    // 【为什么使用 -cos 形式从 PMin 平滑起步】
    // 标准正弦 sin(2πφ) 在 φ=0 时值为 0，对应中点 (PMax+PMin)/2，
    // 且 φ=0 处导数最大 → 压力一开机就急速上升，不利于平稳启动。
    //
    // -cos(2πφ) 在 φ=0 时值为 -1：
    //   P(φ) = (PMax+PMin)/2 - (PMax-PMin)/2 * (-1) = PMin
    //   从最低压力 PMin 起步，符合"从谷值开始"的物理要求。
    //
    // 更关键的优点: -cos 在 φ=0 处导数 dP/dφ = 0，
    //   即压力在周期起点处变化率为零 → 平滑上升，
    //   不会在波形起始处产生突变的 dP/dt（目标压力变化率），
    //   前馈控制器不需要在起始瞬间提供极大的电压。
    //   对比 sin: sin(0)=0 但 dP/dφ = PMax-PMin（最大速率），
    //   起始就有大的 dP/dt，前馈和执行机构承受冲击。
    //
    rTarget := (rPMax + rPMin) / 2.0
               - (rPMax - rPMin) / 2.0 * COS(2.0 * PI * rPhase);

1:  // 方波 (带过渡段)
    // 【方波过渡段的目的——避免不连续性】
    // 理想方波在 PMin 和 PMax 之间瞬间跳变，
    // dP/dt 在跳变点为无穷大，现实中执行器无法跟踪。
    // 更严重的是: dP/dt = ±∞ 会导致模型前馈 u_ff → ∞，
    // 控制电压瞬间饱和，系统和执行器承受巨大冲击。
    //
    // 过渡段 (RISE_RATIO_SQUARE = 8% 周期) 的作用:
    //   - 在 PMin→PMax 和 PMax→PMin 的跳变处插入线性过渡，
    //     将 dP/dt 限制在 (PMax-PMin) / (过渡段时长) 的有限值
    //   - 过渡段时长 = 0.08 / f，例如 f=1Hz 时 = 80ms
    //   - 虽然仍有 dP/dt 的阶跃变化（恒斜率），但幅值有限可跟踪
    //
    // 四段划分:
    //   0% ~ 8%:   线性上升 (PMin → PMax)
    //   8% ~ 50%:  高位保持 (PMax)
    //   50% ~ 58%: 线性下降 (PMax → PMin)
    //   58% ~ 100%: 低位保持 (PMin)
    //
    IF rPhase < RISE_RATIO_SQUARE THEN
        rTarget := rPMin + (rPMax - rPMin) * (rPhase / RISE_RATIO_SQUARE);
    ELSIF rPhase < 0.5 THEN
        rTarget := rPMax;
    ELSIF rPhase < (0.5 + RISE_RATIO_SQUARE) THEN
        rTarget := rPMax - (rPMax - rPMin) * ((rPhase - 0.5) / RISE_RATIO_SQUARE);
    ELSE
        rTarget := rPMin;
    END_IF

2:  // 三角波
    // 三角波是最简单的分段线性波形，两段等长:
    //   0% ~ 50%:  线性上升 (PMin → PMax)
    //   50% ~ 100%: 线性下降 (PMax → PMin)
    // dP/dt 在过零点有阶跃变化（斜率切换），但幅值恒定有限。
    IF rPhase < 0.5 THEN
        rTarget := rPMin + (rPMax - rPMin) * (rPhase / 0.5);
    ELSE
        rTarget := rPMax - (rPMax - rPMin) * ((rPhase - 0.5) / 0.5);
    END_IF

3:  // 梯形波
    // 【梯形波分段计算】
    // 梯形波是方波的平滑版本，四段组成:
    //   rR% 上升段: PMin 线性升至 PMax
    //   rH% 保持段: 停留在 PMax
    //   rF% 下降段: PMax 线性降至 PMin
    //   rL% 低保持段: 停留在 PMin
    //   （rL = 1 - rR - rH - rF，自动计算）
    //
    // 各段的相位区间:
    //   [0, rR):         上升
    //   [rR, rR+rH):     高位保持
    //   [rR+rH, rR+rH+rF): 下降
    //   [rR+rH+rF, 1.0): 低位保持
    //
    // 参数保护: 若用户设 rR/rH/rF < 0.01（如未配置），
    // 则回退到默认值，防止零宽度段导致除零。
    // 总占比检查: 若 rR+rH+rF > 1.0，则 rL=0，梯形波退化为三角波。
    //
    rR := rRisePct;
    rH := rHoldPct;
    rF := rFallPct;
    IF rR < 0.01 THEN rR := 0.1; END_IF
    IF rH < 0.01 THEN rH := 0.3; END_IF
    IF rF < 0.01 THEN rF := 0.1; END_IF
    rL := 1.0 - rR - rH - rF;
    IF rL < 0.0 THEN rL := 0.0; END_IF

    IF rPhase < rR THEN
        // 上升段: P = PMin + (PMax-PMin) * (φ / rR)
        // 斜率 = (PMax-PMin) / rR / T，其中T为周期
        rTarget := rPMin + (rPMax - rPMin) * (rPhase / rR);
    ELSIF rPhase < (rR + rH) THEN
        rTarget := rPMax;
    ELSIF rPhase < (rR + rH + rF) THEN
        // 下降段: P = PMax - (PMax-PMin) * ((φ-rR-rH) / rF)
        rTarget := rPMax - (rPMax - rPMin) * ((rPhase - rR - rH) / rF);
    ELSE
        rTarget := rPMin;
    END_IF

4:  // ★ 自定义波形 — 查表 + 线性插值
    LutInterpolate();

ELSE
    // 默认正弦
    rTarget := (rPMax + rPMin) / 2.0
               - (rPMax - rPMin) / 2.0 * COS(2.0 * PI * rPhase);
END_CASE

// 限幅保护
IF rTarget < 0.0 THEN rTarget := 0.0; END_IF
IF rTarget > 50.0 THEN rTarget := 50.0; END_IF

// 【首次运行初始化——防止 rTargetPrev 不匹配】
// 第一个扫描周期时，rTargetPrev 还没有被赋值（初始为 rPMin），
// 而 rTarget 已经根据波形计算出了值。如果两者不一致，
// 外部用 (rTarget - rTargetPrev)/dt 计算的 dP/dt 会产生巨大的伪微分值。
// 因此首次运行时令 rTargetPrev := rTarget，确保 dP/dt = 0 起步。
IF bFirstRun THEN
    rTargetPrev := rTarget;
    rTargetLeadPrev := rTargetLead;
    bFirstRun := FALSE;
END_IF

rTargetLast := rTarget;
// ============================================================
// MFF超前目标计算
// ============================================================
// 在当前相位基础上加超前相位偏移，计算"未来N步"的目标值
// MFF使用超前目标可以提前输出控制量，补偿系统滞后
// 超前相位 = nMffLeadSteps × f × dt (归一化到0~1)
//
rTargetLeadPrev := rTargetLeadLast;

IF nMffLeadSteps > 0 THEN
    rPhaseLead := rPhaseAcc + INT_TO_REAL(nMffLeadSteps) * rFrequency * rDt;
    // 循环回卷到 [0, 1)
    IF rPhaseLead >= 1.0 THEN
        rPhaseLead := rPhaseLead - 1.0;
    END_IF

    // 用超前相位计算目标值(与主波形相同的公式)
    CASE iWaveType OF
    0:  // 正弦波
        rTargetLead := (rPMax + rPMin) / 2.0
                       - (rPMax - rPMin) / 2.0 * COS(2.0 * PI * rPhaseLead);
    1:  // 方波
        IF rPhaseLead < RISE_RATIO_SQUARE THEN
            rTargetLead := rPMin + (rPMax - rPMin) * (rPhaseLead / RISE_RATIO_SQUARE);
        ELSIF rPhaseLead < 0.5 THEN
            rTargetLead := rPMax;
        ELSIF rPhaseLead < (0.5 + RISE_RATIO_SQUARE) THEN
            rTargetLead := rPMax - (rPMax - rPMin) * ((rPhaseLead - 0.5) / RISE_RATIO_SQUARE);
        ELSE
            rTargetLead := rPMin;
        END_IF
    2:  // 三角波
        IF rPhaseLead < 0.5 THEN
            rTargetLead := rPMin + (rPMax - rPMin) * (rPhaseLead / 0.5);
        ELSE
            rTargetLead := rPMax - (rPMax - rPMin) * ((rPhaseLead - 0.5) / 0.5);
        END_IF
    3:  // 梯形波
        IF rPhaseLead < rR THEN
            rTargetLead := rPMin + (rPMax - rPMin) * (rPhaseLead / rR);
        ELSIF rPhaseLead < (rR + rH) THEN
            rTargetLead := rPMax;
        ELSIF rPhaseLead < (rR + rH + rF) THEN
            rTargetLead := rPMax - (rPMax - rPMin) * ((rPhaseLead - rR - rH) / rF);
        ELSE
            rTargetLead := rPMin;
        END_IF
    4:  // 自定义波形LUT插值
        IF bLutValid AND iLutLen >= 2 THEN
            rTargetLead := LutInterpolateAtPhase(rPhaseLead);
        ELSE
            rTargetLead := (rPMax + rPMin) / 2.0
                           - (rPMax - rPMin) / 2.0 * COS(2.0 * PI * rPhaseLead);
        END_IF
    ELSE
        rTargetLead := (rPMax + rPMin) / 2.0
                       - (rPMax - rPMin) / 2.0 * COS(2.0 * PI * rPhaseLead);
    END_CASE

    IF rTargetLead < 0.0 THEN rTargetLead := 0.0; END_IF
    IF rTargetLead > 50.0 THEN rTargetLead := 50.0; END_IF
ELSE
    // 无超前，等于当前目标
    rTargetLead := rTarget;
END_IF

rTargetLeadLast := rTargetLead;

iIdxCounter := iIdxCounter + 1;


// ============================================================
// 自定义波形: LUT线性插值
// ============================================================
// LUT 存储一个完整周期的压力值 (MPa)，等间距分布
// 相位 0~1 映射到索引 0~(N-1)，相邻两点线性插值
//
// 例: N=2000, phase=0.333
//   连续索引 = 0.333 * 1999 = 665.667
//   idx0 = 665, idx1 = 666
//   frac = 0.667
//   output = LUT[665] * 0.333 + LUT[666] * 0.667
// ============================================================
METHOD LutInterpolate
VAR
	rContIdx : REAL; // 连续索引 (浮点)
	iIdx0 : INT; // 左端整数索引
	iIdx1 : INT; // 右端整数索引
	rFrac : REAL; // 小数部分
	nPts : INT;
END_VAR
IF NOT bLutValid OR iLutLen < 2 THEN
    rTarget := (rPMax + rPMin) / 2.0
               - (rPMax - rPMin) / 2.0 * COS(2.0 * PI * rPhase);
    RETURN;
END_IF

nPts := iLutLen;
IF nPts > MAX_LUT_POINTS THEN nPts := MAX_LUT_POINTS; END_IF

// 相位 → 连续索引
// 【LUT 插值算法详解】
// LUT 存储了 N 个等间距采样点，覆盖一个完整周期 [0, 1)。
// 相位 φ ∈ [0, 1) 映射到连续索引 idx ∈ [0, N-1]:
//   rContIdx = φ * (N - 1)
//
// 为什么用 N-1 而不是 N:
//   φ=0 → idx=0 (第一个点)
//   φ=1⁻ → idx→(N-1) (最后一个点)
//   如果用 N，则 φ=1⁻ → idx→N，超出数组上界，造成越界。
//   用 N-1 保证首末两端精确对应，且相位在 [0,1) 内索引不会越界。
//
rContIdx := rPhase * INT_TO_REAL(nPts - 1);

// 分离整数和小数部分 (TRUNC 向零截断，对正数等价于向下取整)
// 【为什么需要 TRUNC + 范围检查】
// TRUNC 向零截断: TRUNC(3.7) = 3, TRUNC(-0.5) = 0
// 对于正数 rContIdx，TRUNC 等价于 FLOOR（向下取整）。
// 但有两个风险需要范围检查:
//
// (1) rPhase 浮点误差可能导致 rContIdx 略超出 [0, N-1]:
//     例如 rPhase = 1.0（理论上不应出现，但浮点累积误差可能产生），
//     则 rContIdx = N-1，此时 iIdx0 = N-1，iIdx1 = N 越界。
//     所以需要检查 iIdx0 >= nPts-1 时直接返回末尾值。
//
// (2) 极端情况下 rPhase 可能为负数（浮点误差或复位时序问题），
//     TRUNC 对负数向零截断不等于 FLOOR，例如 TRUNC(-0.1) = 0，
//     而 FLOOR(-0.1) = -1。代码检查 iIdx0 < 0 时钳位到 0，
//     防止数组负索引越界。
//
// 综上，TRUNC+范围检查 = 安全的整数索引提取，
// 保证 iIdx0 ∈ [0, nPts-2]（正常插值区间），
// 边界情况 iIdx0 ≥ nPts-1 时直接返回 arrLUT[nPts-1]。
//
iIdx0 := REAL_TO_INT(TRUNC(rContIdx));
IF iIdx0 < 0 THEN iIdx0 := 0; END_IF
IF iIdx0 >= nPts - 1 THEN
    // 到达末尾，直接取最后一个点
    rTarget := arrLUT[nPts - 1];
    RETURN;
END_IF

iIdx1 := iIdx0 + 1;
rFrac := rContIdx - INT_TO_REAL(iIdx0);

// 线性插值: y = y0*(1-f) + y1*f
// 【线性插值原理】
// 在 LUT[iIdx0] 和 LUT[iIdx1] 之间做线性内插:
//   rTarget = arrLUT[iIdx0] * (1.0 - rFrac) + arrLUT[iIdx1] * rFrac
//
// rFrac ∈ [0, 1) 表示当前相位在两采样点之间的相对位置:
//   rFrac = 0 → 正好在 iIdx0 点，取 arrLUT[iIdx0]
//   rFrac = 0.5 → 两点中点，取平均值
//   rFrac → 1⁻ → 接近 iIdx1 点
//
// 这种插值的精度取决于 LUT 点数:
//   N=2000 点/周期，正弦波最大插值误差 ≈ (π/N)² * Peak/8 ≈ 0.0002%，
//   远小于系统其他误差源，完全可以忽略。
//
rTarget := arrLUT[iIdx0] * (1.0 - rFrac) + arrLUT[iIdx1] * rFrac;
END_METHOD

METHOD LoadCustomWaveform
VAR_INPUT
	pData : POINTER TO REAL; // 指向波形数据数组
	nPoints : INT; // 数据点数 (2~2000)
END_VAR
VAR
	i : INT;
	n : INT;
END_VAR
n := nPoints;
IF n < 2 THEN n := 2; END_IF
IF n > MAX_LUT_POINTS THEN n := MAX_LUT_POINTS; END_IF

// 复制数据到内部 LUT
FOR i := 0 TO n - 1 DO
    arrLUT[i] := pData[i];
END_FOR

iLutLen := n;
bLutValid := TRUE;
END_METHOD

METHOD LutInterpolateAtPhase : REAL
VAR_INPUT
	rPhaseIn : REAL; // 输入相位 (0~1)
END_VAR
VAR
	rContIdx : REAL;
	iIdx0 : INT;
	iIdx1 : INT;
	rFrac : REAL;
	nPts : INT;
END_VAR

IF NOT bLutValid OR iLutLen < 2 THEN
    LutInterpolateAtPhase := (rPMax + rPMin) / 2.0
                             - (rPMax - rPMin) / 2.0 * COS(2.0 * PI * rPhaseIn);
    RETURN;
END_IF

nPts := iLutLen;
IF nPts > MAX_LUT_POINTS THEN nPts := MAX_LUT_POINTS; END_IF

rContIdx := rPhaseIn * INT_TO_REAL(nPts - 1);
iIdx0 := REAL_TO_INT(TRUNC(rContIdx));
IF iIdx0 < 0 THEN iIdx0 := 0; END_IF
IF iIdx0 >= nPts - 1 THEN
    LutInterpolateAtPhase := arrLUT[nPts - 1];
    RETURN;
END_IF

iIdx1 := iIdx0 + 1;
rFrac := rContIdx - INT_TO_REAL(iIdx0);
LutInterpolateAtPhase := arrLUT[iIdx0] * (1.0 - rFrac) + arrLUT[iIdx1] * rFrac;
END_METHOD
END_FUNCTION_BLOCK
