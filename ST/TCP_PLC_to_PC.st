PROGRAM TCP_PLC_to_PC
VAR
	INPUT_REGISTER AT %QW0 : ARRAY[0..1999] OF WORD; // PLC发送缓冲区
	Float_to_TwoWord : PWmotion.Float_to_TwoWord;
	j : DINT; // 寄存器地址索引（WORD索引）
END_VAR

// ===================================================================
// TCP INPUT_REGISTER 地址布局 (PLC → PC，V4.x)
// ===================================================================
// [A] 系统状态         0   – 31     (32 W)
// [B] 油路实时         32  – 95     (64 W)
// [C] 油路控制分量     96  – 127    (32 W)
// [D] 液压站实时       128 – 159    (32 W)
// [E] 油路指令回读     160 – 223    (64 W)
// [F] 系统诊断         224 – 255    (32 W)
// [G] 设备状态         256 – 319    (64 W)  ← 由 PRG_DeviceControl 填充
// [Z] 未来扩展         320 – 1999
// ===================================================================


// ===== [A] 系统状态 (0-31) =====
j := 0;

Float_to_TwoWord(input := GVL_PulsePressure.PP_FrameCounter_PLC);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 0-1: PLC帧计数器
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_SysState);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 2-3: 系统状态 0=空闲 1=冲洗 2=预加压 3=运行 4=停止 5=故障
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
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 16-17: 冲洗排气剩余时间(s)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_StateReady);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 18-19: 状态推进就绪标志
j := j + 2;

// 20-31: 保留 (6 vars reserved)


// ===== [B] 油路实时 (32-95) =====
j := 32;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ActualPressure);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 32-33: 油路实际压力(MPa)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_SetpointPressure);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 34-35: 油路给定压力(MPa)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_PressureError);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 36-37: 油路压力偏差(MPa)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ControlOutput);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 38-39: MFF+ILC+PID 总输出(V)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ValveCurrent);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 40-41: 比例阀电流(mA)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_CylinderPos);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 42-43: 缸体位移(mm)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_CyclesDone);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 44-45: 完成循环次数
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_Frequency_FB);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 46-47: 实际频率(Hz)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_WavePhase);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 48-49: 波形相位(°)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_PeakPressure);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 50-51: 本次脉冲峰值(MPa)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_TargetUpper);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 52-53: ARP1383C 上包络(MPa)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_TargetLower);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 54-55: ARP1383C 下包络(MPa)
j := j + 2;

// 56-95: 保留 (20 vars reserved)


// ===== [C] 油路控制分量 (96-127) =====
j := 96;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_MFF_Output);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 96-97: 模型前馈输出(V)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ILC_Output);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 98-99: ILC 学习输出
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ILC_Iteration);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 100-101: ILC 迭代次数
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_PID_Output);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 102-103: PID 反馈输出
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_PID_Integral);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 104-105: PID 积分项
j := j + 2;

// 106-127: 保留 (11 vars reserved)


// ===== [D] 液压站实时 (128-159) =====
j := 128;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_Pressure);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 128-129: 液压站系统压力(MPa)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_Temperature);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 130-131: 液压油温度(°C)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_OilLevel);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 132-133: 液位(mm)
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
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 138-139: 液压泵累计运行时间(h)
j := j + 2;

// 140-159: 保留 (10 vars reserved)


// ===== [E] 油路指令回读 (160-223) =====
// 镜像 PC→PLC 区 [C][D] 让上位机验证收发一致
j := 160;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_WaveType);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 160-161: 波形类型 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_TargetPressure);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 162-163: 目标压力 (回读)
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
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 168-169: 高压限值 (回读)
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

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_VBase);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 184-185: 基础容积 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_VSpecimen);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 186-187: 被试件容积 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ValveQnom);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 188-189: 阀额定流量 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ValveDPnom);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 190-191: 阀额定压降 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_Kv);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 192-193: 反推 Kv (诊断)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_TauValve);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 194-195: 反推 τv (诊断)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_HighLimit);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 196-197: 液压站高压限值 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_TempLimit);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 198-199: 液压站温度限值 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_WorkingPressure);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 200-201: 液压站工作压力 Ps (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Sys_BetaE);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 202-203: 体积弹性模量 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Sys_CLeak);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 204-205: 泄漏系数 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ILC_LearningRate);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 206-207: ILC 学习率 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_EnvPctP);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 208-209: 包络压力容差 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_EnvPctT);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 210-211: 包络时间容差 (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_PID_Kp);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 212-213: PID Kp (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_PID_Ki);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 214-215: PID Ki (回读)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_PID_Kd);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 216-217: PID Kd (回读)
j := j + 2;

// 218-223: 保留 (3 vars reserved)


// ===== [F] 系统诊断 (224-255) =====
j := 224;

Float_to_TwoWord(input := GVL_PulsePressure.PP_PLC_ScanCycle);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 224-225: PLC 扫描周期(ms)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_TCPIP_CommCycle);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 226-227: TCP 通讯周期(ms)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_PLC_Timestamp_Low);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 228-229: 时间戳低32位(ms)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_PLC_Timestamp_High);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 230-231: 时间戳高32位
j := j + 2;

// 232-255: 保留 (12 vars reserved)


// ===== [G] 设备状态 (256-319) =====
// 该区域由 PRG_DeviceControl（待重写）填充
// 建议地址分配（占位约定）:
//   256-257 : bit-packed 泵运行/故障状态 (SMP/XH/HR1/HR2)
//   258-259 : bit-packed 过滤器状态 + 相序报警 (8.01/16.01/19.01/相序)
//   260-261 : 液压站油液温度
//   262-263 : 液压站油液液位
//   264-265 : 压力 32.01 (剂侧油缸无杆腔)
//   266-267 : 压力 32.03 (剂侧油缸有杆腔)
//   268-269 : 压力 26.01 (产品端低压传感器)
//   270-271 : 压力 27.01 (产品端高压传感器)
//   272-273 : SMP 压力反馈
//   274-275 : SMP 转速反馈
//   276-277 : SMP 流量反馈
//   278-279 : 油缸位置 Oil_CylinderPos
//   280-281 : HR_Pump1 频率反馈
//   282-283 : HR_Pump2 频率反馈
//   284-319 : 保留


// ===== [Z] 320-1999: 未来扩展 =====

END_PROGRAM
