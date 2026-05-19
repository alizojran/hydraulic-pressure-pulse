PROGRAM TCP_PLC_to_PC
VAR
	INPUT_REGISTER AT %QW0 : ARRAY[0..1999] OF WORD; // PLC发送缓冲区
	Float_to_TwoWord : PWmotion.Float_to_TwoWord;
	Dint_to_TwoWord : PWmotion.DINT_to_TwoWord;
	j : DINT; // 寄存器地址索引（WORD索引）
END_VAR
// ============================================================
// 【系统状态区】（WORD地址 0–19, 92–93）
//
// 本区打包 PLC 的全局状态信息，包括帧计数器、系统状态机、
// 报警标志、运行模式、命令/使能回读、数字量I/O状态、
// 冲洗排气剩余时间、状态推进就绪标志等。
// 这些变量用于上位机监控 PLC 整体运行状态和故障诊断。
// PP_StateReady(92-93)利用保留区，不影响现有地址布局。
//
// 转换模式：每个 REAL 变量通过 Float_to_TwoWord 拆为低字[j]+高字[j+1]
// 地址推进：赋值后 j := j + 2
// ============================================================
j := 0;

Float_to_TwoWord(input := GVL_PulsePressure.PP_FrameCounter_PLC);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 0-1: PLC帧计数器
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_SysState);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 2-3: 系统状态
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_AlarmFlags);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 4-5: 报警标志
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_TotalCyclesDone);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 6-7: 累计循环次数
j := j + 2;


GVL_PulsePressure.PP_RunningMode := GVL_PulsePressure.PP_TestMode ;

Float_to_TwoWord(input := GVL_PulsePressure.PP_RunningMode);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 8-9: 当前运行模式
j := j + 2;

// 以下为命令/使能回读：上位机下发的命令和使能信号由PLC回读后打包，
// 上位机可通过比对确认指令已被PLC正确接收执行（回读验证机制）
Float_to_TwoWord(input := GVL_PulsePressure.PP_SysCommand);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 10-11: 系统命令回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Enable);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 12-13: 使能状态回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_IO_InputBits);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 14-15: 数字量输入
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_IO_OutputBits_FB);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 16-17: 数字量输出回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_FlushTimeRemaining);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 18-19: 冲洗排气剩余时间(s)
j := j + 2;

// ============================================================
// 【水路实时数据区】（WORD地址 20–49）
//
// 本区打包水路压力控制回路的全部实时数据，包括实际压力、
// 给定压力、压力偏差、控制总输出、比例阀电流、缸体位移、
// 循环计数、频率/相位/峰值等过程量。
// V2.0 新增 MFF/ILC/ADRC 控制分量反馈（地址40-49），
// 用于上位机实时监控复合控制各子算法的独立输出。
//
// 转换模式：每个 REAL → 2 WORD（IEEE 754拆字，低字在前高字在后）
// 地址推进：j 递增 2
// 回读说明：ControlOutput（26-27）为 MFF+ILC+ADRC 三者叠加后的
//           最终控制量，上位机可对比总输出与各分量之和验证控制完整性
// ============================================================
j := 20;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_ActualPressure);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 20-21: 水路实际压力
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_SetpointPressure);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 22-23: 水路给定压力
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_PressureError);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 24-25: 水路压力偏差
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_ControlOutput);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 26-27: 水路MFF+ILC+ADRC总输出
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_ValveCurrent);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 28-29: 水路比例阀电流
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_CylinderPos);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 30-31: 水路缸体位移
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_CyclesDone);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 32-33: 水路完成循环次数
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_Frequency_FB);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 34-35: 水路实际频率
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_WavePhase);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 36-37: 水路波形相位
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_PeakPressure);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 38-39: 水路峰值压力
j := j + 2;

// --- V2.0 新增: MFF/ILC/ADRC 控制分量反馈（水路，地址40-49）---
//
// 以下5个变量为 V2.0 复合控制方案的核心诊断数据，用于上位机
// 实时观测各控制子算法的独立输出，便于调试和性能分析：
//
//   MFF_Output（40-41）：模型前馈输出 — 基于系统数学模型（容积V、
//     流量增益Kv、弹性模量BetaE等）计算的开环前馈控制量，提供
//     快速的基准控制信号，是复合控制的主分量。
//
//   ILC_Output（42-43）：迭代学习控制输出 — 基于前一周期压力偏差
//     的学习修正量，通过逐周期迭代减小重复性跟踪误差，提升
//     周期性波形的跟踪精度。
//
//   ILC_Iteration（44-45）：ILC迭代次数 — 当前已完成的迭代学习
//     周期数，用于判断 ILC 是否已充分收敛，以及监控学习进程。
//
//   ADRC_Output（46-47）：自抗扰控制器输出 — ADRC 的反馈控制量，
//     基于扩展状态观测器(ESO)对系统扰动的实时估计，通过状态误差
//     反馈律生成补偿信号，抑制未建模动态和外部扰动。
//
//   ESO_Disturbance（48-49）：扩展状态观测器扰动估计 — ESO 对系统
//     总扰动（含未建模动态、参数摄动、外力干扰等）的实时估计值，
//     是 ADRC 抗扰能力的核心指标，上位机可据此判断扰动水平及
//     ADRC 补偿效果。
//
// 总输出关系：ControlOutput(26-27) = MFF_Output(40-41) + ILC_Output(42-43) + ADRC_Output(46-47)

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_MFF_Output);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 40-41: 水路模型前馈输出
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_ILC_Output);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 42-43: 水路ILC学习输出
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_ILC_Iteration);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 44-45: 水路ILC迭代次数
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_ADRC_Output);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 46-47: 水路ADRC反馈输出
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_ESO_Disturbance);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 48-49: 水路ESO扰动估计
j := j + 2;

// ============================================================
// 【油路实时数据区】（WORD地址 50–79）
//
// 本区打包油路压力控制回路的全部实时数据，结构和水路区
// 完全对称（实际压力、给定、偏差、控制输出、阀电流、位移、
// 循环计数、频率/相位/峰值），另含 V2.0 新增 MFF/ILC/ADRC 分量。
//
// 转换模式：同上，REAL → 2 WORD（低字在前，IEEE 754）
// 地址推进：j 递增 2
// 回读说明：油路 ControlOutput（56-57）= MFF+ILC+ADRC 总叠加输出
// ============================================================
j := 50;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ActualPressure);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 50-51: 油路实际压力
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_SetpointPressure);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 52-53: 油路给定压力
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_PressureError);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 54-55: 油路压力偏差
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ControlOutput);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 56-57: 油路MFF+ILC+ADRC总输出
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ValveCurrent);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 58-59: 油路比例阀电流
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_CylinderPos);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 60-61: 油路缸体位移
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_CyclesDone);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 62-63: 油路完成循环次数
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_Frequency_FB);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 64-65: 油路实际频率
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_WavePhase);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 66-67: 油路波形相位
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_PeakPressure);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 68-69: 油路峰值压力
j := j + 2;

// --- V2.0 新增: MFF/ILC/ADRC 控制分量反馈（油路，地址70-79）---
//
// 油路诊断变量含义与水路区（地址40-49）完全对称：
//
//   MFF_Output（70-71）：油路模型前馈输出 — 基于油路系统数学模型
//     计算的开环前馈控制量，为油路提供快速基准控制信号。
//
//   ILC_Output（72-73）：油路迭代学习控制输出 — 基于前一周期油路
//     压力偏差的迭代学习修正量，逐周期减小重复性跟踪误差。
//
//   ILC_Iteration（74-75）：油路ILC迭代次数 — 已完成的迭代学习
//     周期数，用于判断油路 ILC 收敛程度。
//
//   ADRC_Output（76-77）：油路自抗扰控制器输出 — 基于油路 ESO
//     扰动估计的状态误差反馈控制量，抑制油路未建模动态和外部扰动。
//
//   ESO_Disturbance（78-79）：油路扩展状态观测器扰动估计 — ESO 对
//     油路总扰动的实时估计值，是 ADRC 抗扰能力的核心指标。
//
// 总输出关系：ControlOutput(56-57) = MFF_Output(70-71) + ILC_Output(72-73) + ADRC_Output(76-77)

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_MFF_Output);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 70-71: 油路模型前馈输出
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ILC_Output);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 72-73: 油路ILC学习输出
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ILC_Iteration);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 74-75: 油路ILC迭代次数
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ADRC_Output);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 76-77: 油路ADRC反馈输出
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ESO_Disturbance);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 78-79: 油路ESO扰动估计
j := j + 2;

// ============================================================
// 【液压站实时数据区】（WORD地址 80–91）
//
// 本区打包液压站（液压动力单元）的运行状态监测数据，
// 包括系统压力、油温、液位、泵状态、过滤器状态、泵运行时间。
// 用于上位机监控液压站的运行安全和维护预警。
//
// 转换模式：同上，REAL → 2 WORD（低字在前，IEEE 754拆字）
// 地址推进：j 递增 2
// ============================================================
j := 80;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_Pressure);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 80-81: 液压站系统压力
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_Temperature);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 82-83: 液压油温度
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_OilLevel);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 84-85: 液位值(mm)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_PumpStatus);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 86-87: 液压泵状态
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_FilterStatus);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 88-89: 过滤器状态
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_PumpRunTime);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 90-91: 液压泵运行时间
j := j + 2;

// 92-99: 保留

// PP_StateReady: 利用保留区 WORD 92-93
// 状态推进就绪标志，PC据此判断是否可以发SysCommand=3确认推进
Float_to_TwoWord(input := GVL_PulsePressure.PP_StateReady);
INPUT_REGISTER[92] := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[93] := Float_to_TwoWord.Word_HIGH;        // 92-93: 状态推进就绪标志

// ============================================================
// 【上位机指令参数回读区】（WORD地址 100–145）
//
// 【回读设计原理】
// 上位机通过 TCP Holding Register（HREG）向 PLC 下发控制参数
// （如目标压力、频率、波形类型、MFF系统参数等）。PLC 将这些
// 参数的当前值回读到 INPUT_REGISTER 的本区域并回传给上位机，
// 形成"上位机下发→PLC接收存储→PLC回读打包→上位机比对验证"
// 的闭环通讯机制。上位机通过对比下发值与回读值，可确认：
//   ① 参数是否被 PLC 正确接收（通讯链路完整性验证）
//   ② 参数是否被 PLC 正确存储（存储一致性验证）
//   ③ 是否存在通讯延迟或数据丢失（实时性验证）
//
// 本区域是 PC→PLC→PC 往返验证的数据镜像区。
//
// 转换模式：同上，REAL → 2 WORD（低字在前，IEEE 754拆字）
// 地址推进：j 递增 2
// V2.0变更：原 PID 参数(Kp/Ki/Kd)回读替换为 MFF 系统参数
//           (VBase/VSpecimen/Kv) 回读，新增 BetaE/CLeak/ILC_LearningRate 回读
// ============================================================
j := 100;

// --- 水路运行参数回读（100-109）---
Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_TargetPressure);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 100-101: 水路目标压力回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_MinPressure);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 102-103: 水路最低压力回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_Frequency);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 104-105: 水路频率回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_WaveType);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 106-107: 水路波形类型回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_HighLimit);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 108-109: 水路高压限值回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_TargetCycles);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 110-111: 水路目标循环次数回读
j := j + 2;

// --- V2.1: 水路阀样本参数回读 + 反推Kv/τv诊断（110-121）---
Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_VBase);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 112-113: 水路基础容积回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_VSpecimen);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 114-115: 水路被试件容积回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_Kv);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 116-117: 水路反推Kv回读(诊断)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_TauValve);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 118-119: 水路反推τv回读(诊断)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_ValveQnom);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 120-121: 水路阀额定流量回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_ValveDPnom);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 122-123: 水路阀额定压降回读
j := j + 2;

// --- 油路运行参数回读（122-131）---
Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_TargetPressure);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 124-125: 油路目标压力回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_MinPressure);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 126-127: 油路最低压力回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_Frequency);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 128-129: 油路频率回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_WaveType);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 130-131: 油路波形类型回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_HighLimit);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 132-133: 油路高压限值回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_TargetCycles);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 134-135: 油路目标循环次数回读
j := j + 2;

// --- V2.1: 油路阀样本参数回读 + 反推Kv/τv诊断（132-143）---
Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_VBase);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 136-137: 油路基础容积回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_VSpecimen);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 138-139: 油路被试件容积回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_Kv);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 140-141: 油路反推Kv回读(诊断)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_TauValve);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 142-143: 油路反推τv回读(诊断)
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ValveQnom);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 144-145: 油路阀额定流量回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ValveDPnom);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 146-147: 油路阀额定压降回读
j := j + 2;

// --- 液压站及全局参数回读（144-155）---
Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_HighLimit);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 148-149: 液压站高压限值回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Hydro_TempLimit);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 150-151: 液压站温度限值回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_TestMode);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 152-153: 当前测试模式回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Sys_BetaE);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 154-155: 体积弹性模量回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Sys_CLeak);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 156-157: 泄漏系数回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_ILC_LearningRate);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 158-159: 水路ILC学习率回读
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_ILC_LearningRate);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 160-161: 油路ILC学习率回读
j := j + 2;

// ============================================================
// 【系统诊断与时间戳区】（WORD地址 160–167）
//
// 本区打包 PLC 的运行诊断信息，包括扫描周期、通讯周期、
// PLC时间戳。用于上位机监控 PLC 实时性能和时间同步。
//
// 转换模式：同上，REAL → 2 WORD（低字在前，IEEE 754拆字）
// 地址推进：j 递增 2
// ============================================================
j := 164;

Float_to_TwoWord(input := GVL_PulsePressure.PP_PLC_ScanCycle);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 164-165: PLC扫描周期实测
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_TCPIP_CommCycle);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 166-167: TCP通讯周期实测
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_PLC_Timestamp_Low);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 168-169: 时间戳低32位
j := j + 2;

Float_to_TwoWord(input := GVL_PulsePressure.PP_PLC_Timestamp_High);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 170-171: 时间戳高32位
j := j + 2;


// 200-235: 
j:=200;
//-{200}
//INPUT_REGISTER[j].0 :=;  //伺服泵_运行
//INPUT_REGISTER[j].1 :=;  //伺服泵_故障
INPUT_REGISTER[j].2 := GVL_GPIO.CT_121F_DI_4;  //循环泵_运行
INPUT_REGISTER[j].3 := XH_OilPump_Control.XH_OilPump_FAULT;  //循环泵_故障

INPUT_REGISTER[j].4 := GVL_GPIO.CT_121F_DI_2;  //换热泵1_运行
INPUT_REGISTER[j].5 := HR_Pump1_Control.HR_Pump1_FAULT;  //换热泵1_故障
INPUT_REGISTER[j].6 := GVL_GPIO.CT_121F_DI_3;  //换热泵2_运行
INPUT_REGISTER[j].7 := HR_Pump2_Control.HR_Pump2_FAULT;  //换热泵2_故障

INPUT_REGISTER[j].8 := PRG_DeviceControl.toPC_Filter_8_01;
INPUT_REGISTER[j].9 := PRG_DeviceControl.toPC_Filter_16_01;
INPUT_REGISTER[j].10 := PRG_DeviceControl.toPC_Filter_19_01;
INPUT_REGISTER[j].11 := GVL_GPIO.CT_121F_DI_11;  //相序报警

//INPUT_REGISTER[j].12 := ;
//INPUT_REGISTER[j].13 := ;
//INPUT_REGISTER[j].14 := ;
//INPUT_REGISTER[j].15 := ;

//-{201}
//INPUT_REGISTER[j+1].0 := ;  
//INPUT_REGISTER[j+1].1 := ;  
//INPUT_REGISTER[j+1].2 := ;
//INPUT_REGISTER[j+1].3 := ;

//INPUT_REGISTER[j+1].4 := ;
//INPUT_REGISTER[j+1].5 := ;
//INPUT_REGISTER[j+1].6 := ;
//INPUT_REGISTER[j+1].7 := ;

//INPUT_REGISTER[j+1].8 := ;
//INPUT_REGISTER[j+1].9 := ;
//INPUT_REGISTER[j+1].10 := ;
//INPUT_REGISTER[j+1].11 := ;

//INPUT_REGISTER[j+1].12 := ;
//INPUT_REGISTER[j+1].13 := ;
//INPUT_REGISTER[j+1].14 := ;
//INPUT_REGISTER[j+1].15 := ;

j := j + 2;
//-{202}
//INPUT_REGISTER[j].0 :=;  
//INPUT_REGISTER[j].1 :=;  
//INPUT_REGISTER[j].2 := ;
//INPUT_REGISTER[j].3 := ;

//INPUT_REGISTER[j].4 := ;
//INPUT_REGISTER[j].5 := ;
//INPUT_REGISTER[j].6 := ;
//INPUT_REGISTER[j].7 := ;

//INPUT_REGISTER[j].8 := ;
//INPUT_REGISTER[j].9 := ;
//INPUT_REGISTER[j].10 := ;
//INPUT_REGISTER[j].11 := ;  

//INPUT_REGISTER[j].12 := ;
//INPUT_REGISTER[j].13 := ;
//INPUT_REGISTER[j].14 := ;
//INPUT_REGISTER[j].15 := ;

//-{203}
//INPUT_REGISTER[j+1].0 := ;  
//INPUT_REGISTER[j+1].1 := ;  
//INPUT_REGISTER[j+1].2 := ;
//INPUT_REGISTER[j+1].3 := ;

//INPUT_REGISTER[j+1].4 := ;
//INPUT_REGISTER[j+1].5 := ;
//INPUT_REGISTER[j+1].6 := ;
//INPUT_REGISTER[j+1].7 := ;

//INPUT_REGISTER[j+1].8 := ;
//INPUT_REGISTER[j+1].9 := ;
//INPUT_REGISTER[j+1].10 := ;
//INPUT_REGISTER[j+1].11 := ;

//INPUT_REGISTER[j+1].12 := ;
//INPUT_REGISTER[j+1].13 := ;
//INPUT_REGISTER[j+1].14 := ;
//INPUT_REGISTER[j+1].15 := ;

j := j + 2;
Float_to_TwoWord(input := PRG_HydraulicUnit_Control.HydraulicUnit_OilTemperature);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 204-205: 液压站_油液温度

j := j + 2;
Float_to_TwoWord(input := PRG_HydraulicUnit_Control.HydraulicUnit_OilLevel);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 206-207: 液压站_油液液位

j := j + 2;
Float_to_TwoWord(input := PRG_DeviceControl.toPC_Pressure_32_01);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 208-209: 压力32.01(剂侧油缸_无杆腔压力)

j := j + 2;
Float_to_TwoWord(input := PRG_DeviceControl.toPC_Pressure_32_02);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 210-211: 压力32.02(水侧油缸_无杆腔压力)

j := j + 2;
Float_to_TwoWord(input := PRG_DeviceControl.toPC_Pressure_32_03);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 212-213: 压力32.03(剂侧油缸_有杆腔压力)

j := j + 2;
Float_to_TwoWord(input := PRG_DeviceControl.toPC_Pressure_32_04);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 214-215: 压力32.04(水侧油缸_有杆腔压力)

j := j + 2;
Float_to_TwoWord(input := PRG_DeviceControl.toPC_Pressure_25_01);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 216-217: 压力25.01(水侧产品端压力)

j := j + 2;
Float_to_TwoWord(input := PRG_DeviceControl.toPC_Pressure_26_01);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 218-219: 压力26.01(剂侧产品端压力_低压)

j := j + 2;
Float_to_TwoWord(input := PRG_DeviceControl.toPC_Pressure_27_01);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 220-221: 压力27.01(剂侧产品端压力_爆破压力)

j := j + 2;
Float_to_TwoWord(input := PRG_DeviceControl.toPC_SMP_Pressure_Feedback);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 222-223: 伺服泵_压力反馈

j := j + 2;
Float_to_TwoWord(input := PRG_DeviceControl.toPC_SMP_RPM_Feedback);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 224-225: 伺服泵_转速反馈

j := j + 2;
Float_to_TwoWord(input := PRG_DeviceControl.toPC_SMP_Flow_Feedback);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 226-227: 伺服泵_流量反馈

j := j + 2;
Float_to_TwoWord(input := PRG_HydraulicUnit_Control.Water_CylinderPos);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 228-229: 水路缸体位置传感器

j := j + 2;
Float_to_TwoWord(input := PRG_HydraulicUnit_Control.Oil_CylinderPos);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 230-231: 油路(剂侧)缸体位置传感器


j := j + 2;
Float_to_TwoWord(input := GVL_GPIO.CT_3168_AI_2);  
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 232-233: 换热泵1_运行频率反馈_(传送AD通道采集值)

j := j + 2;
Float_to_TwoWord(input := GVL_GPIO.CT_3168_AI_3);  //
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 234-235: 换热泵2_运行频率反馈_(传送AD通道采集值)

// ============================================================
// 爆破测试结果回传区（WORD地址 236-243）
// 数据流: PRG_PressureControl 爆破状态机写入 → PC 读取展示
// ============================================================
j := j + 2;
Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_BurstResult);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 236-237: 水路爆破压力记录(MPa)

j := j + 2;
Float_to_TwoWord(input := GVL_PulsePressure.PP_Water_BurstPhase);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 238-239: 水路爆破相位 0=升压 1=保压 2=续升 3=已爆破

j := j + 2;
Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_BurstResult);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 240-241: 油路爆破压力记录(MPa)

j := j + 2;
Float_to_TwoWord(input := GVL_PulsePressure.PP_Oil_BurstPhase);
INPUT_REGISTER[j]   := Float_to_TwoWord.Word_LOW;
INPUT_REGISTER[j+1] := Float_to_TwoWord.Word_HIGH;         // 242-243: 油路爆破相位 0=升压 1=保压 2=续升 3=已爆破

END_PROGRAM
