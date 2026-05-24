PROGRAM TCP_PLC_to_PC
VAR
	INPUT_REGISTER AT %QW0 : ARRAY[0..1999] OF WORD; // PLC发送缓冲区
	Float_to_TwoWord : PWmotion.Float_to_TwoWord;
	j : DINT; // 寄存器地址索引（WORD索引）
END_VAR

// ===================================================================
// TCP INPUT_REGISTER 地址布局 (PLC → PC, V5.0)
// ===================================================================
// 设计原则:
//   - 每节内字段从基址连续紧排, 节尾留大块预留
//   - 节边界对齐 32W 倍数, 便于上位机分块读取
//   - 字段一旦发布不再挪位; 新字段从节末预留区追加
//   - [E] 指令回读区与 PC→PLC 区 [C][D][E] 一一对应, 让 HMI 验证收发一致
// ===================================================================
// [A] 系统状态     0   – 31    (32 W; 10 字段 = 20 W, 余 12 W)
// [B] 油路实时    32   – 95    (64 W; 11 标量 + 10 元 1ms 压力数组 = 42 W, 余 22 W)
// [C] 控制器分量  96   – 127   (32 W;  4 字段 =  8 W, 余 24 W)
// [D] 液压站实时 128  – 159    (32 W;  6 字段 = 12 W, 余 20 W)
// [E] 指令回读   160  – 223    (64 W; 26 字段 = 52 W, 余 12 W)
// [F] 系统诊断   224  – 255    (32 W;  4 字段 =  8 W, 余 24 W)
// [G] 设备状态   256  – 319    (64 W; 由 PRG_DeviceControl 填充)
// [Z] 未来扩展   320  – 1999
// ===================================================================


// ===== [A] 系统状态 (0-31) =====
j := 0;

Float_to_TwoWord(input := GVL_PulsePressure.PP_FrameCounter_PLC);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 0-1: PLC 帧计数器 (心跳)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_SysState);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 2-3: 系统状态 0=空闲 1=冲洗 3=运行 4=停止 5=故障 (无 2)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_AlarmFlags);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 4-5: 报警标志
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_TotalCyclesDone);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 6-7: 累计循环次数
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_SysCommand);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 8-9: 系统命令回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Enable);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 10-11: 使能回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_IO_InputBits);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 12-13: 数字量输入
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_IO_OutputBits_FB);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 14-15: 数字量输出回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_FlushTimeRemaining);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 16-17: 冲洗排气剩余时间 (s)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_StateReady);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 18-19: 状态推进就绪标志
j := j + 2;

// 20-31: 保留 (6 字段)


// ===== [B] 油路实时 (32-95) =====
j := 32;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ActualPressure);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 32-33: 油路实际压力 (MPa)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_SetpointPressure);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 34-35: 油路给定压力 (MPa)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_PressureError);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 36-37: 油路压力偏差 (MPa)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ControlOutput);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 38-39: 阀控总输出 (V) = PID
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ValveCurrent);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 40-41: 比例阀电流 (mA)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_CyclesDone);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 42-43: 完成循环次数
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_Frequency_FB);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 44-45: 实际频率 (Hz)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_WavePhase);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 46-47: 波形相位 (°)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_PeakPressure);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 48-49: 本次脉冲峰值 (MPa)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_TargetUpper);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 50-51: ARP1383C 上包络 (MPa)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_TargetLower);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 52-53: ARP1383C 下包络 (MPa)
j := j + 2;

// -- 1ms 分辨率压力缓冲 (10 采样, 54-73) --
// PLC 1ms 任务采样, TCP 10ms 任务在每个通讯周期发送上一窗口的 10 个点
// 索引: [0]=窗口起点(t-9ms), [9]=窗口终点(t-0ms, 最新)
Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ActualPressure_1ms[0]);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 54-55: 1ms 压力 [0] t-9ms
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ActualPressure_1ms[1]);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 56-57: 1ms 压力 [1] t-8ms
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ActualPressure_1ms[2]);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 58-59: 1ms 压力 [2] t-7ms
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ActualPressure_1ms[3]);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 60-61: 1ms 压力 [3] t-6ms
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ActualPressure_1ms[4]);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 62-63: 1ms 压力 [4] t-5ms
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ActualPressure_1ms[5]);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 64-65: 1ms 压力 [5] t-4ms
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ActualPressure_1ms[6]);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 66-67: 1ms 压力 [6] t-3ms
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ActualPressure_1ms[7]);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 68-69: 1ms 压力 [7] t-2ms
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ActualPressure_1ms[8]);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 70-71: 1ms 压力 [8] t-1ms
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ActualPressure_1ms[9]);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 72-73: 1ms 压力 [9] t-0ms (最新)
j := j + 2;

// 74-95: 保留 (11 字段)


// ===== [C] 控制器分量 (96-127) =====
j := 96;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ILC_Output);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 96-97: ILC 指令修正量 (MPa)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ILC_Iteration);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 98-99: ILC 当前迭代次数
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_PID_Output);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 100-101: PID 反馈输出 (V)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_PID_Integral);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 102-103: PID 积分项 (V)
j := j + 2;

// 104-127: 保留 (12 字段)


// ===== [D] 液压站实时 (128-159) =====
j := 128;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_Pressure);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 128-129: 液压站系统压力 (MPa)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_Temperature);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 130-131: 液压油温度 (°C)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_OilLevel);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 132-133: 液位 (mm)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_PumpStatus);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 134-135: 液压泵运行状态
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_FilterStatus);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 136-137: 过滤器状态
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_PumpRunTime);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 138-139: 液压泵累计运行时间 (h)
j := j + 2;

// 140-159: 保留 (10 字段)


// ===== [E] 指令回读 (160-223) =====
// 镜像 PC→PLC 区 [C][D][E], 让上位机验证收发一致
// 顺序与 PC→PLC 一致, 但布局连续 (PC→PLC 节内的预留区在回读区不复制)
j := 160;

// -- 镜像 PC→PLC [C] 油路波形 (15 字段) --
Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_WaveType);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 160-161: 波形类型 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_TargetPressure);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 162-163: 目标峰值压力 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_MinPressure);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 164-165: 最低压力 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_Frequency);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 166-167: 频率 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_HighLimit);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 168-169: 油路高压限值 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_TargetCycles);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 170-171: 目标循环次数 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_RisePct);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 172-173: 上升段占比 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_HoldPct);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 174-175: 保压段占比 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_FallPct);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 176-177: 下降段占比 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_Overshoot);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 178-179: 过冲幅值占比 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_RingPct);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 180-181: 过冲后稳定段占比 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_LowDwellPct);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 182-183: 低保持段占比 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_CycleReset);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 184-185: 循环计数清零 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_EnvPctP);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 186-187: 包络压力容差 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_EnvPctT);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 188-189: 包络时间容差 (回读)
j := j + 2;

// -- 镜像 PC→PLC [D] 控制器 (6 字段) --
Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ILC_Enable);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 190-191: ILC 使能 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ILC_MaxIter);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 192-193: ILC 最大迭代 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ILC_LearningRate);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 194-195: ILC 学习率 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_PID_Kp);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 196-197: PID Kp (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_PID_Ki);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 198-199: PID Ki (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_PID_Kd);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 200-201: PID Kd (回读)
j := j + 2;

// -- 镜像 PC→PLC [E] 液压站 (4 字段) --
Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_HighLimit);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 202-203: 液压站高压限值 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_TempLimit);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 204-205: 液压站温度限值 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_PumpCmd);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 206-207: 液压泵启停 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_MotorSpeed);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 208-209: 电机转速设定 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_Filter);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 210-211: 油路滤波时间常数 (回读, ms)
j := j + 2;

// 212-223: 保留 (6 字段)


// ===== [F] 系统诊断 (224-255) =====
j := 224;

Float_to_TwoWord(input := GVL_PulsePressure.PP_PLC_ScanCycle);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 224-225: PLC 扫描周期 (ms)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_TCPIP_CommCycle);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 226-227: TCP 通讯周期 (ms)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_PLC_Timestamp_Low);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 228-229: 时间戳低 32 位 (ms)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_PLC_Timestamp_High);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 230-231: 时间戳高 32 位
j := j + 2;

// 232-255: 保留 (12 字段)


// ===== [G] 设备状态 (256-319) =====
// 该区域由 PRG_DeviceControl（待重写）填充
// 建议地址分配 (占位约定):
//   256-257 : bit-packed 泵运行/故障状态 (SMP/XH/HR1/HR2)
//   258-259 : bit-packed 过滤器状态 + 相序报警 (8.01/16.01/19.01/相序)
//   260-261 : 液压站油液温度
//   262-263 : 液压站油液液位
//   264-271 : 4 路油路压力传感器
//   272-279 : SMP 压力/转速/流量反馈
//   280-283 : HR_Pump1/Pump2 频率反馈
//   284-319 : 保留 (18 字段)


// ===== [Z] 320-1999: 未来扩展 =====

END_PROGRAM
