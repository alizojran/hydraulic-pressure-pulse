PROGRAM TCP_PC_to_PLC
VAR
	HOLDING_REGISTER AT %IW0 : ARRAY[0..1999] OF WORD; // 上位机写入缓冲区
	TwoWord_to_Float : PWmotion.TwoWord_to_Float;
	i : DINT; // 寄存器地址索引（WORD索引）
END_VAR

// ===================================================================
// TCP HOLDING_REGISTER 地址布局 (PC → PLC, V5.0)
// ===================================================================
// 设计原则:
//   - 每节内字段从基址连续紧排, 节尾留大块预留
//   - 节边界对齐 32W 倍数, 便于上位机分块读写
//   - 字段一旦发布不再挪位; 新字段从节末预留区追加
// ===================================================================
// [A] 系统控制    0   – 31    (32 W;  6 字段 = 12 W, 余 20 W)
// [B] 冲洗排气    32  – 47    (16 W;  2 字段 =  4 W, 余 12 W)
// [C] 油路波形    48  – 95    (48 W; 15 字段 = 30 W, 余 18 W)
// [D] 控制器      96  – 127   (32 W;  6 字段 = 12 W, 余 20 W)  ILC + PID
// [E] 液压站     128 – 159    (32 W;  4 字段 =  8 W, 余 24 W)
// [F] IO 控制    160 – 191    (32 W;  2 字段 =  4 W, 余 28 W)
// [G] 设备控制   192 – 255    (64 W; 由 PRG_DeviceControl 解析)
// [Z] 未来扩展   256 – 1999
// ===================================================================


// ===== [A] 系统控制 (0-31) =====
i := 0;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_FrameCounter_PC := TwoWord_to_Float.Output;        // 0-1: 上位机帧计数器(心跳)
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_SysCommand := TwoWord_to_Float.Output;             // 2-3: 系统命令 0=空闲 1=冲洗 2=运行 3=停止
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_AlarmReset := TwoWord_to_Float.Output;             // 4-5: 报警复位
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Enable := TwoWord_to_Float.Output;                 // 6-7: 系统使能
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_EmergencyStop := TwoWord_to_Float.Output;          // 8-9: 急停
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_HeartbeatTimeout := TwoWord_to_Float.Output;       // 10-11: 心跳超时(s)
i := i + 2;

// 12-31: 保留 (10 字段)


// ===== [B] 冲洗排气 (32-47) =====
i := 32;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_FlushDuration := TwoWord_to_Float.Output;          // 32-33: 冲洗持续时间(s); 0=跳过冲洗
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_FlushValveOutput := TwoWord_to_Float.Output;       // 34-35: 冲洗阀门输出(V); 默认 2.0
i := i + 2;

// 36-47: 保留 (6 字段)


// ===== [C] 油路波形 (48-95) =====
i := 48;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_WaveType := TwoWord_to_Float.Output;           // 48-49: 波形类型 0=正弦 1=梯形 2=ARP1383 水锤
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_TargetPressure := TwoWord_to_Float.Output;     // 50-51: 目标峰值压力 PMax (MPa)
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_MinPressure := TwoWord_to_Float.Output;        // 52-53: 最低压力 PMin (MPa)
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_Frequency := TwoWord_to_Float.Output;          // 54-55: 脉冲频率 (Hz)
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_HighLimit := TwoWord_to_Float.Output;          // 56-57: 高压保护限值 (MPa)
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_TargetCycles := TwoWord_to_Float.Output;       // 58-59: 目标循环次数
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_RisePct := TwoWord_to_Float.Output;            // 60-61: 上升段占比
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_HoldPct := TwoWord_to_Float.Output;            // 62-63: 保压段占比
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_FallPct := TwoWord_to_Float.Output;            // 64-65: 下降段占比
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_Overshoot := TwoWord_to_Float.Output;          // 66-67: 水锤波过冲幅值占比
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_RingPct := TwoWord_to_Float.Output;            // 68-69: 水锤波过冲后稳定段占比
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_LowDwellPct := TwoWord_to_Float.Output;        // 70-71: 水锤波低保持段占比
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_CycleReset := TwoWord_to_Float.Output;         // 72-73: 循环计数清零命令
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_EnvPctP := TwoWord_to_Float.Output;            // 74-75: ARP1383C 包络压力容差 ×PMax (默认 0.05)
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_EnvPctT := TwoWord_to_Float.Output;            // 76-77: ARP1383C 包络时间容差 ×周期 (默认 0.10)
i := i + 2;

// 78-95: 保留 (9 字段)


// ===== [D] 控制器: ILC + PID (96-127) =====
i := 96;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_ILC_Enable := TwoWord_to_Float.Output;         // 96-97: ILC 使能
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_ILC_MaxIter := TwoWord_to_Float.Output;        // 98-99: ILC 最大迭代次数
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_ILC_LearningRate := TwoWord_to_Float.Output;   // 100-101: ILC 学习率 (0~1)
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_PID_Kp := TwoWord_to_Float.Output;             // 102-103: PID 比例增益 Kp (V/MPa)
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_PID_Ki := TwoWord_to_Float.Output;             // 104-105: PID 积分增益 Ki (V/MPa/s)
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Oil_PID_Kd := TwoWord_to_Float.Output;             // 106-107: PID 微分增益 Kd (V·s/MPa)
i := i + 2;

// 108-127: 保留 (10 字段)


// ===== [E] 液压站 (128-159) =====
i := 128;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Hydro_HighLimit := TwoWord_to_Float.Output;        // 128-129: 液压站高压限值 (MPa)
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Hydro_TempLimit := TwoWord_to_Float.Output;        // 130-131: 油温保护限值 (°C)
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Hydro_PumpCmd := TwoWord_to_Float.Output;          // 132-133: 液压泵启停命令
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_Hydro_MotorSpeed := TwoWord_to_Float.Output;       // 134-135: 电机转速设定 (rpm)
i := i + 2;

// 136-159: 保留 (12 字段)


// ===== [F] IO 控制 (160-191) =====
i := 160;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_IO_OutputBits := TwoWord_to_Float.Output;          // 160-161: 数字量输出控制
i := i + 2;

TwoWord_to_Float(word_low := HOLDING_REGISTER[i], word_high := HOLDING_REGISTER[i+1]);
GVL_PulsePressure.PP_IO_OilCircuitSel := TwoWord_to_Float.Output;       // 162-163: 油路选通
i := i + 2;

// 164-191: 保留 (14 字段)


// ===== [G] 设备控制 (192-255) =====
// 该区域的解析由 PRG_DeviceControl（待重写）负责。原始 HOLDING_REGISTER
// 直接保留在缓冲区, 新 PRG_DeviceControl 可直接按 bit/Float 访问解析。
//
// 建议地址分配 (占位约定):
//   192-193 : bit-packed 泵启停 (SMP/XH/HR1/HR2 × Start/Stop/Reset, 12 bits)
//   194-195 : bit-packed Pne_Valve YV1-YV13 (13 bits)
//   196-205 : 保留 (5 字段)
//   206-207 : SMP 压力设定 (MPa)
//   208-209 : SMP 流量设定
//   210-211 : HR_Pump1 频率设定
//   212-213 : HR_Pump2 频率设定
//   214-255 : 保留 (21 字段)


// ===== [Z] 256-1999: 未来扩展 =====

END_PROGRAM
