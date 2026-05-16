// Global Variable List: GVL_GPIO
VAR_GLOBAL
	CT_121F_DI_0 : BOOL; // 伺服泵_运行
	CT_121F_DI_1 : BOOL; // 伺服泵_故障
	CT_121F_DI_2 : BOOL; // 换热泵1变频器_运行
	CT_121F_DI_3 : BOOL; // 换热泵2变频器_运行
	CT_121F_DI_4 : BOOL; // 循环泵_运行
	CT_121F_DI_5 : BOOL; // 循环泵_故障
	CT_121F_DI_6 : BOOL;
	CT_121F_DI_7 : BOOL;
	CT_121F_DI_8 : BOOL; // 压力过滤器8.01_发讯
	CT_121F_DI_9 : BOOL; // 压力过滤器16.01_发讯
	CT_121F_DI_10 : BOOL; // 压力过滤器19.01_发讯
	CT_121F_DI_11 : BOOL; // GRM_32B_相序报警
	CT_121F_DI_12 : BOOL;
	CT_121F_DI_13 : BOOL;
	CT_121F_DI_14 : BOOL;
	CT_121F_DI_15 : BOOL;
	CT_222F_1_DO_0 : BOOL; // 伺服泵_使能(启动/停止)
	CT_222F_1_DO_1 : BOOL; // 伺服泵_故障复位
	CT_222F_1_DO_2 : BOOL; // 换热泵1_使能(启动/停止)
	CT_222F_1_DO_3 : BOOL; // 换热泵1_故障复位
	CT_222F_1_DO_4 : BOOL; // 换热泵2_使能(启动/停止)
	CT_222F_1_DO_5 : BOOL; // 换热泵2_故障复位
	CT_222F_1_DO_6 : BOOL; // 循环泵_使能(启动/停止)
	CT_222F_1_DO_7 : BOOL;
	CT_222F_1_DO_8 : BOOL; // 通断阀10.01
	CT_222F_1_DO_9 : BOOL; // 通断阀10.02
	CT_222F_1_DO_10 : BOOL; // 通断阀10.03
	CT_222F_1_DO_11 : BOOL; // 通断阀10.04
	CT_222F_1_DO_12 : BOOL; // 通断阀24.01
	CT_222F_1_DO_13 : BOOL; // 通断阀30.01
	CT_222F_1_DO_14 : BOOL;
	CT_222F_1_DO_15 : BOOL;
	CT_222F_2_DO_0 : BOOL; // 气动电磁阀YV1
	CT_222F_2_DO_1 : BOOL; // 气动电磁阀YV2
	CT_222F_2_DO_2 : BOOL; // 气动电磁阀YV3
	CT_222F_2_DO_3 : BOOL; // 气动电磁阀YV4
	CT_222F_2_DO_4 : BOOL; // 气动电磁阀YV5
	CT_222F_2_DO_5 : BOOL; // 气动电磁阀YV6
	CT_222F_2_DO_6 : BOOL; // 气动电磁阀YV7
	CT_222F_2_DO_7 : BOOL; // 气动电磁阀YV8
	CT_222F_2_DO_8 : BOOL; // 气动电磁阀YV9
	CT_222F_2_DO_9 : BOOL; // 气动电磁阀YV10
	CT_222F_2_DO_10 : BOOL; // 气动电磁阀YV11
	CT_222F_2_DO_11 : BOOL; // 气动电磁阀YV12
	CT_222F_2_DO_12 : BOOL; // 气动电磁阀YV13
	CT_222F_2_DO_13 : BOOL;
	CT_222F_2_DO_14 : BOOL;
	CT_222F_2_DO_15 : BOOL;
	CT_3168_AI_0 : INT; // 伺服泵_压力反馈
	CT_3168_AI_1 : INT; // 伺服泵_转速反馈
	CT_3168_AI_2 : INT; // 换热泵1_转速反馈
	CT_3168_AI_3 : INT; // 换热泵2_转速反馈
	CT_3168_AI_4 : INT;
	CT_3168_AI_5 : INT;
	CT_3168_AI_6 : INT;
	CT_3168_AI_7 : INT;
	CT_3238_1_AI_0 : INT;
	CT_3238_1_AI_1 : INT;
	CT_3238_1_AI_2 : INT;
	CT_3238_1_AI_3 : INT; // 压力传感器_32.01
	CT_3238_1_AI_4 : INT; // 压力传感器_32.02
	CT_3238_1_AI_5 : INT; // 压力传感器_32.03
	CT_3238_1_AI_6 : INT; // 压力传感器_32.04
	CT_3238_1_AI_7 : INT;
	CT_3238_2_AI_0 : INT; // 液压站_油液温度
	CT_3238_2_AI_1 : INT; // 液压站_油液液位
	CT_3238_2_AI_2 : INT;
	CT_3238_2_AI_3 : INT;
	CT_3238_2_AI_4 : INT;
	CT_3238_2_AI_5 : INT;
	CT_3238_2_AI_6 : INT;
	CT_3238_2_AI_7 : INT;
	CT_4158_AO_0 : INT; // 伺服泵_压力指令
	CT_4158_AO_1 : INT; // 伺服泵_流量指令
	CT_4158_AO_2 : INT; // 换热泵1_转速指令(频率)
	CT_4158_AO_3 : INT; // 换热泵2_转速指令(频率)
	CT_4158_AO_4 : INT; // 产品端压力_25.01(水侧)
	CT_4158_AO_5 : INT; // 产品端压力26.01(剂侧低压)
	CT_4158_AO_6 : INT; // 产品端压力27.01(剂侧高压)
	CT_4158_AO_7 : INT;
END_VAR