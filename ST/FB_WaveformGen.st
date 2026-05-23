FUNCTION_BLOCK FB_WaveformGen
VAR_INPUT
	bEnable : BOOL; // 使能
	rPMin : REAL; // 最低压力 (MPa)
	rPMax : REAL; // 最高压力 (MPa)
	rFrequency : REAL; // 脉冲频率 (Hz)
	iWaveType : INT; // 波形类型 0=正弦 1=梯形 2=ARP1383水锤波
	rRisePct : REAL; // 梯形/水锤波上升段占比，默认0.1
	rHoldPct : REAL; // 梯形/水锤波保持段占比，默认0.3
	rFallPct : REAL; // 梯形/水锤波下降段占比，默认0.1
	rOvershoot : REAL; // 水锤波过冲幅值占比 = (Pos-Pmax)/(Pmax-Pmin)，默认0.10
	rRingPct : REAL; // 水锤波过冲后稳定段占比 (指令直接给PMax)，默认0.07
	rLowDwellPct : REAL; // 水锤波低保持段占比，默认0.48 (5段相对权重，内部归一化)
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
	rR : REAL; // 上升段占比
	rH : REAL; // 保持段占比
	rF : REAL; // 下降段占比
	rL : REAL; // 低保持段占比
	rPhaseLead : REAL; // 超前相位值
	rOS : REAL; // 水锤波过冲幅值占比 (本地副本+保护)
	rRing : REAL; // 水锤波过冲衰减段占比 (本地副本+保护后并归一化)
	rLow : REAL; // 水锤波低保持段占比 (本地副本+保护后并归一化)
	rSum : REAL; // 水锤波 5 段占比和 (用于归一化)
	rPeakOS : REAL; // 水锤波过冲峰压力 = Pmax + rOS*(Pmax-Pmin)
END_VAR
VAR CONSTANT
	PI : REAL := 3.14159265358979;
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
// 点数太少会导致波形分辨率不足，所以设下限 10 点保证基本波形质量。
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
    //
    rTarget := (rPMax + rPMin) / 2.0
               - (rPMax - rPMin) / 2.0 * COS(2.0 * PI * rPhase);

1:  // 梯形波
    // 【梯形波分段计算】
    // 梯形波四段组成:
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

2:  // ARP1383C Fig.2 水锤波形 (水锤型 / Water Hammer) — 指令面五段
    // 【五段组成 — 全部由用户显式设置，内部归一化为 sum=1】
    //   rR     上升段:      指令步进到过冲峰 P_OS (无斜率)
    //   rRing  过冲后稳定段: 指令步进到 PMax (快速从过冲峰回到正常压力)
    //   rH     保压段:      PMax 平直
    //   rF     下降段:      PMax → PMin (线性，平滑卸压)
    //   rLow   低保持段:    PMin
    //
    // 【对应 ARP1383C 标准】
    //   指令直接发 P_OS (= PMax × 1+rOvershoot) 形成过冲尖峰
    //   过冲峰持续 rR% 时间，然后步进回到 PMax (Ring 段)
    //   实际压力的上升/过冲衰减由控制器跟踪+液压系统自然完成
    //   平直保压区 (rRing + rH) 合计 ≥ 10% 周期
    //   下降至 P_min 并停留至周期末
    //
    // 【过冲峰值】
    //   P_OS = PMax + rOvershoot × (PMax - PMin)
    //   rOvershoot=0.10 → 过冲 10%（落在 ARP1383 Fig.2 容差带内）
    //
    // 【段时间归一化】
    //   读入 5 段相对权重后强制 sum = 1.0:
    //       rSum = rR + rRing + rH + rF + rLow
    //       rR /= rSum, rRing /= rSum, rH /= rSum, rF /= rSum, rLow /= rSum
    //   这样无论操作员输入 (5%,7%,35%,5%,48%) 还是 (1,1.4,7,1,9.6)，
    //   结果都得到一样的归一化比例，并保证波形闭合不超出 1 周期。
    //
    rR := rRisePct;
    rRing := rRingPct;
    rH := rHoldPct;
    rF := rFallPct;
    rLow := rLowDwellPct;
    IF rR < 0.01 THEN rR := 0.05; END_IF
    IF rRing < 0.01 THEN rRing := 0.07; END_IF
    IF rH < 0.01 THEN rH := 0.35; END_IF
    IF rF < 0.01 THEN rF := 0.05; END_IF
    IF rLow < 0.01 THEN rLow := 0.48; END_IF

    rSum := rR + rRing + rH + rF + rLow;
    IF rSum > 0.01 THEN
        rR := rR / rSum;
        rRing := rRing / rSum;
        rH := rH / rSum;
        rF := rF / rSum;
        rLow := rLow / rSum;
    END_IF

    rOS := rOvershoot;
    IF rOS <= 0.0 THEN rOS := 0.10; END_IF
    rPeakOS := rPMax + rOS * (rPMax - rPMin);

    IF rPhase < rR THEN
        // 上升段: 指令直接步进到过冲峰 P_OS (无斜率)
        rTarget := rPeakOS;
    ELSIF rPhase < (rR + rRing) THEN
        // 过冲后稳定段: 指令直接给 PMax (快速从过冲峰回到正常压力)
        // 实际从 P_OS 到 PMax 的过渡由控制器/液压系统自然完成
        rTarget := rPMax;
    ELSIF rPhase < (rR + rRing + rH) THEN
        // 平直保压段
        rTarget := rPMax;
    ELSIF rPhase < (rR + rRing + rH + rF) THEN
        // 下降段 (线性，保持平滑卸压)
        rTarget := rPMax - (rPMax - rPMin) * ((rPhase - rR - rRing - rH) / rF);
    ELSE
        // 低保持段 (rLow 已归一化，与剩余 1 - rR - rRing - rH - rF 相等)
        rTarget := rPMin;
    END_IF

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
    1:  // 梯形波
        IF rPhaseLead < rR THEN
            rTargetLead := rPMin + (rPMax - rPMin) * (rPhaseLead / rR);
        ELSIF rPhaseLead < (rR + rH) THEN
            rTargetLead := rPMax;
        ELSIF rPhaseLead < (rR + rH + rF) THEN
            rTargetLead := rPMax - (rPMax - rPMin) * ((rPhaseLead - rR - rH) / rF);
        ELSE
            rTargetLead := rPMin;
        END_IF
    2:  // ARP1383C 水锤波形（公式与主波形相同，使用超前相位）
        // 参数副本 rR/rRing/rH/rF/rLow/rOS/rPeakOS 已在主分支中赋值并归一化
        IF rPhaseLead < rR THEN
            rTargetLead := rPeakOS;
        ELSIF rPhaseLead < (rR + rRing) THEN
            rTargetLead := rPMax;
        ELSIF rPhaseLead < (rR + rRing + rH) THEN
            rTargetLead := rPMax;
        ELSIF rPhaseLead < (rR + rRing + rH + rF) THEN
            rTargetLead := rPMax - (rPMax - rPMin) * ((rPhaseLead - rR - rRing - rH) / rF);
        ELSE
            rTargetLead := rPMin;
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

END_FUNCTION_BLOCK
