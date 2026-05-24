FUNCTION_BLOCK FB_ILC
VAR_INPUT
	bEnable : BOOL;
	rTargetRaw : REAL; // 原始目标值 (MPa)
	rActual : REAL; // 当前反馈值 (MPa)
	iPointIndex : INT; // 周期内采样点序号 (0 ~ iPointsPerCycle-1)
	iPointsPerCycle : INT;
	bNewCycle : BOOL;
	bReset : BOOL;
	iMaxIterations : INT;
	rLearningRate : REAL := 0.3; // 端点学习率
	rAlphaLR : REAL := 0.2; // α 学习率（正弦/三角 8 段、梯形/矩形 6 段）
	rGroupW : REAL := 0.5; // 12 段组级修正权重（解决 bin 钳位时溢出不转移问题）；0=禁用
	bAlphaEnable : BOOL := TRUE; // α 自学习使能（正弦/三角/梯形/矩形）
	bPlatCorrEnable : BOOL := TRUE; // 平台 2 段幅值修正使能（仅梯形/矩形生效）
	iWaveType : INT;            // 波形类型（与 PP_Trace_Flag 对齐）：1=正弦 2=三角 3=梯形 4=矩形 5=任意 6=直线
	nWarmupCycles : INT := 3; // 暖机周期数：前N个周期透传不修正，等待 vMin/vMax 极值收敛
	// 事件型 ILC 切分入参（仅 nWaveType=5 自定义波使用；其它波形可恒为 FALSE / 0 / NULL）
	bSegmentTrigger : BOOL;     // 上升沿触发一次切分（PRG 在 PP_WaveUpload_Commit 上升沿置 TRUE 一拍）
	pSegmentData : POINTER TO REAL; // 待切分波形点表指针（通常指向 PP_WaveUpload_Data）
	nSegmentPoints : INT;       // 待切分点数
	// 直线波入参（仅 nWaveType=6 使用，其它波形可恒为 0）
	rLinearRate : REAL;         // 直线波升压速率 (MPa/s)
	rDt : REAL := 0.001;        // 控制周期 (s)，与 PRG 主循环 rDt 对齐
END_VAR
VAR_OUTPUT
	rOutput : REAL; // 修正量 = rVirtualTarget - rTargetRaw (MPa)
	rVirtualTarget : REAL; // 预畸变指令实时值 (MPa)
	iIteration : INT;
	rRmsError : REAL;
	bConverged : BOOL;
	rPeakError : REAL;
	rValleyError : REAL;
	rVMax : REAL; // 端点学习量
	rVMin : REAL;
	rScalePos : REAL := 1.0;
	rScaleNeg : REAL := 1.0;
	rAlphaCmd : ARRAY[1..8] OF REAL; // 8 段 α 时长占比（正弦 / 三角共用）
	rAlphaTgt : ARRAY[1..8] OF REAL;
	rAlphaFb : ARRAY[1..8] OF REAL;
	rAlpha12Cmd : ARRAY[1..12] OF REAL; // 12 段 α 时长占比（梯形 / 矩形共用：底平 / 升 1..5 / 顶平 / 降 1..5）
	rAlpha12Tgt : ARRAY[1..12] OF REAL;
	rAlpha12Fb : ARRAY[1..12] OF REAL;
	rPlatBotA : REAL; // 梯形 / 矩形：平台分 2 段幅值修正（MPa，叠加在 vMin/vMax 上）
	rPlatBotB : REAL;
	rPlatTopA : REAL;
	rPlatTopB : REAL;
	nWaveType : INT := 0; // 内部使用波形分类：1=正弦, 2=三角, 3=梯形, 4=矩形, 5=任意波（由 iWaveType 映射）
	nAuthStatus : INT; // 鉴权状态 0=未检查 1=授权 2=未授权 3=读序列号失败
END_VAR
VAR
	rMidpoint : REAL;
	rHalfRange : REAL;
	rQuarter : REAL;
	rTargetMax : REAL;
	rTargetMin : REAL;
	rActualMax : REAL;
	rActualMin : REAL;
	rPrevTargetMax : REAL;
	rPrevTargetMin : REAL;
	rPrevTargetRange : REAL;
	bNewCyclePrev : BOOL;
	iIterCount : INT;
	bVInitialized : BOOL; // vMax/vMin 已初始化
	nUpdateCount : INT;
	rPeakErrSum : REAL;
	rValleyErrSum : REAL;
	rErrorSum2 : REAL;
	iErrorCount : INT;
	iTgtBin : ARRAY[1..8] OF INT; // 8 段 α 状态
	iFbBin : ARRAY[1..8] OF INT;
	iBinTotal : INT;
	iTgtBin12 : ARRAY[1..12] OF INT; // 12 段 α 状态
	iFbBin12 : ARRAY[1..12] OF INT;
	iBinTotal12 : INT;
	rFbSumBotA : REAL; // 平台 2 段反馈累加（按 cmd phase 切割）
	rFbSumBotB : REAL;
	rFbSumTopA : REAL;
	rFbSumTopB : REAL;
	iCntBotA : INT;
	iCntBotB : INT;
	iCntTopA : INT;
	iCntTopB : INT;
	rT1Cached : REAL; // cmd 平台 phase 边界缓存（每周期边界更新一次）
	rT6Cached : REAL;
	rT7Cached : REAL;
	rBotMidPhase : REAL;
	rTopMidPhase : REAL;
	rFbAvg : REAL;
	rPlatCorrLimit : REAL;
	rTargetPrev : REAL;
	bTgtRising : BOOL;
	rActualPrev : REAL;
	bFbRising : BOOL;
	rTgtPos : REAL;
	rFbPos : REAL;
	iBinK : INT;
	rAlphaSum : REAL;
	rRiseTgtSum : REAL; // 12 段组级学习: 升段(bin 1~6) 指令时间占比合计
	rRiseFbSum : REAL;
	rRiseCmdSum : REAL;
	rFallTgtSum : REAL; // 12 段组级学习: 降段(bin 8~12) 指令时间占比合计
	rFallFbSum : REAL;
	rFallCmdSum : REAL;
	rRiseGroupErr : REAL;
	rFallGroupErr : REAL;
	rGroupCorr : REAL;
	rBinErr : REAL;
	rT1 : REAL;
	rT2 : REAL;
	rT3 : REAL;
	rT4 : REAL;
	rT5 : REAL;
	rT6 : REAL;
	rT7 : REAL;
	rT8 : REAL;
	rT9 : REAL;
	rT10 : REAL;
	rT11 : REAL;
	rBand1 : REAL;
	rBand2 : REAL;
	rBand3 : REAL;
	rBand4 : REAL;
	rPlateauThr : REAL;
	rDelta : REAL;
	rPhi : REAL;
	rPhiStd : REAL;
	rWarpedY : REAL;
	rSourceTarget : REAL;
	rNorm : REAL;
	rLimit : REAL;
	rBinTotal : REAL;
	// --- 任意波（nWaveType=5）逐点 ILC 内部状态 ---
	rCorrTable5 : ARRAY[0..999] OF REAL;  // 学到的逐点加性修正量 (MPa)
	rErrSum5    : ARRAY[0..999] OF REAL;  // 本周期各点误差累加
	iErrCnt5    : ARRAY[0..999] OF INT;   // 本周期各点命中次数
	rQBuf5      : ARRAY[0..999] OF REAL;  // Q-filter 临时缓冲（先存均值，再原地平滑）
	iPtsPerCycle5Last : INT;              // 上一周期点数，变化时清表
	iIdx5       : INT;                    // 当前点钳位索引
	iLeft5      : INT;                    // Q-filter 左邻
	iRight5     : INT;                    // Q-filter 右邻
	rMeanErr5   : REAL;                   // 平滑后单点误差
	rCorrLimit5 : REAL;                   // 单点修正限幅
	// --- 事件型 ILC 状态（nWaveType=5 内部自动升级，V1：A/B 共用 8 段幅值修正）---
	bEventModeActive  : BOOL;             // 事件型路径生效
	bSegmentationOK   : BOOL;             // 最近一次切分成功标志（诊断用）
	iSegFailPhase     : INT;              // 切分失败阶段：0=成功 1=入参 2=幅值范围 3=事件数 4=多平台 5=类数超限
	nSegRunCount      : INT;              // 累计进入切分块的次数（=0 说明上升沿从未触发）
	nEventCount       : INT;              // 事件数
	iEventStart       : ARRAY[0..31] OF INT;   // 事件起点索引
	iEventEnd         : ARRAY[0..31] OF INT;   // 事件终点索引
	iEventShape       : ARRAY[0..31] OF INT;   // 形状：1=A 钟形, 2=B 单梯形
	rEventPeak        : ARRAY[0..31] OF REAL;  // 事件峰值（B 型为平台幅值）
	iEventPlatStart   : ARRAY[0..31] OF INT;   // B 型平台起点（-1 表 A 型）
	iEventPlatEnd     : ARRAY[0..31] OF INT;   // B 型平台终点
	iEventClass       : ARRAY[0..31] OF INT;   // 所属类索引
	iPointToEvent     : ARRAY[0..999] OF INT;  // 反查表：-1=基线段 否则=事件索引
	// 类学习器
	nClassCount       : INT;
	iClassShape       : ARRAY[0..7] OF INT;
	rClassPeakRef     : ARRAY[0..7] OF REAL;
	rEvtBinCorr       : ARRAY[0..7, 1..8] OF REAL;  // 每类 8 段幅值修正 (MPa)
	// 周期内误差累加（按事件实例 × bin）
	rEvtBinErrSum     : ARRAY[0..31, 1..8] OF REAL;
	iEvtBinErrCnt     : ARRAY[0..31, 1..8] OF INT;
	// 事件型运行时临时变量
	iEvtK, iEvtCls, iEvtBinIdx, iEvtLen, iEvtLocal, iEvtPoolCnt : INT;
	iEvtLutIdx : INT;          // iPointIndex(扫描空间) → LUT 空间映射结果
	rEvtFrac, rEvtCorr, rEvtPoolErr, rEvtPoolMean, rEvtBinCorrUpLim, rEvtBinCorrDnLim, rEvtDelta, rEvtDeltaMax : REAL;
	iEvtBb : INT;
	// 直线波 (nWaveType=6) 临时变量
	rLinearDelta : REAL;        // 每周期最大步长 = rLinearRate · rDt
	// 事件型切分内部状态（一次性，由 bSegmentTrigger 上升沿触发）
	bSegmentTriggerPrev : BOOL;
	bSegContinue : BOOL;        // 切分分阶段串联门控
	iSegI, iSegJ, iSegK : INT;
	rSegTgt : REAL;
	rSegMinAll, rSegMaxAll, rSegRange : REAL;
	rSegThrUp, rSegThrDn, rSegFlatThr : REAL;
	bSegInEvent : BOOL;
	rSegWinMax, rSegWinMin : REAL;
	iSegScan, iSegPlatS, iSegPlatE : INT;
	rSegPlatLvl : REAL;
	nSegPlatInEvt : INT;
	bSegMultiPlat : BOOL;
	iSegCls : INT;
	rSegClassGap : REAL;
	bSegExtended : BOOL;
	// --- 授权检查内部状态 ---
	bAuthChecked : BOOL;     // 已检查标志（每次重启检查一次）
	bAuthorized : BOOL;      // 鉴权通过
	sSerial : STRING(255);   // 实际读到的设备序列号
	pSerialBuf : POINTER TO STRING(255);
	diSerialLen : DINT;
END_VAR
VAR CONSTANT
	// --- 授权序列号白名单 (最多 4 个) ---
	// 每台 PLC 用 SysTargetGetSerialNumber 读出来后填进来，
	// 然后在 CODESYS 里 "另存为编译库" 输出 .compiled-library，源码不可见。
	AUTHORIZED_SERIAL_1 : STRING(64) := '100000006c1f7e74';
	AUTHORIZED_SERIAL_2 : STRING(64) := '';
	AUTHORIZED_SERIAL_3 : STRING(64) := '';
	AUTHORIZED_SERIAL_4 : STRING(64) := '';
	// --- 其它常量 ---
	ALPHA_Q_MIN       : REAL := 0.04;
	ALPHA_Q_MAX       : REAL := 0.35;
	ALPHA12_Q_MIN     : REAL := 0.02;
	ALPHA12_Q_MAX     : REAL := 0.45;
	PLATEAU_BAND_K    : REAL := 0.7;     // 平台判定带：|y - mid| > K * halfRange
	PLAT_CORR_LR      : REAL := 0.3;     // 平台幅值修正学习率
	PLAT_CORR_LIMIT_K : REAL := 0.3;     // 平台幅值修正上限：0.3 * halfRange
	PLAT_TGT_MIN_FRAC : REAL := 0.03;    // 目标平台占比阈值：低于此值视为"没有平台"，跳过修正学习
	PLAT_CORR_DECAY   : REAL := 0.9;     // 跳过学习时的修正衰减系数
	TWO_PI            : REAL := 6.283185307;
	CYCLES_PER_UPDATE : INT  := 2;
	V_RANGE_LIMIT_K   : REAL := 2.0;
	// --- 任意波 (nWaveType=5) 逐点 ILC ---
	POINTS_MAX        : INT  := 1000;    // 逐点表最大容量；iPointsPerCycle > POINTS_MAX 时该分支降级透传
	ILC5_Q_W0         : REAL := 0.25;    // Q-filter 三点核：左/右权
	ILC5_Q_W1         : REAL := 0.50;    // Q-filter 三点核：中心权
	ILC5_CORR_LIMIT_K : REAL := 0.5;     // 单点修正限幅：K * rPrevTargetRange
	// --- 事件型 ILC (nWaveType=5 自动升级) ---
	EVT_MAX_EVENTS    : INT  := 32;       // 最大事件数（超过则切分失败，退回逐点 ILC）
	EVT_MAX_CLASSES   : INT  := 8;        // 最大类数
	EVT_THR_UP_K      : REAL := 0.10;     // 进事件阈值：rMin + K · 全程
	EVT_THR_DN_K      : REAL := 0.04;     // 出事件阈值：rMin + K · 全程
	EVT_PLAT_FLAT_K   : REAL := 0.025;    // 平台平坦度阈值：窗口 max-min ≤ K · 全程
	EVT_MIN_PLAT_LEN  : INT  := 8;        // 最短平台点数（短于此值不算平台）
	EVT_MIN_EVENT_LEN : INT  := 6;        // 最短事件点数
	EVT_CLASS_GAP_K   : REAL := 0.10;     // 类间距：|peak_a - peak_b| ≤ K · 全程 视为同类
	EVT_MIN_EVENTS    : INT  := 2;        // 事件数 < 此值则不启用事件型
	EVT_BIN_CORR_LR   : REAL := 0.10;     // 类 bin 幅值修正学习率（配合下面的单周期增量限幅；0.15 LR 单步过大会引发收敛瞬态超调）
	EVT_BIN_CORR_LIM_UP_K: REAL := 0.3;   // 类 bin UP 修正限幅：K · 全程（防 ILC 把虚拟目标顶到 actual 过冲；上行 0.3 比对称 0.5 紧）
	EVT_BIN_CORR_LIM_DN_K: REAL := 0.5;   // 类 bin DOWN 修正限幅：K · 全程（落沿压制保留宽限幅，让 ILC 能把虚拟目标拉低足够多以加速落沿）
	EVT_BIN_DELTA_K   : REAL := 0.02;     // 类 bin 单周期增量限幅：K · 全程（防止 LR×大误差一拍跨过最优修正，强制多周期渐进逼近）
END_VAR
// ============================================================
// 授权检查（首次调用懒加载，每次启动只查一次）
// 未授权时 FB 退化为透传，等同于 bEnable=FALSE，看不出与"未启用"的区别。
// ============================================================
IF NOT bAuthChecked THEN
    pSerialBuf := ADR(sSerial);
    diSerialLen := SIZEOF(sSerial);
    IF SysTarget.SysTargetGetSerialNumber(
           ppsSerialNumber := ADR(pSerialBuf),
           pnMaxLen        := ADR(diSerialLen)) = 0 THEN
        // 读到序列号后逐个白名单比对（空槽位会被排除）
        bAuthorized := FALSE;
        IF LEN(sSerial) >= 8 THEN
            IF AUTHORIZED_SERIAL_1 <> '' AND sSerial = AUTHORIZED_SERIAL_1 THEN bAuthorized := TRUE; END_IF
            IF AUTHORIZED_SERIAL_2 <> '' AND sSerial = AUTHORIZED_SERIAL_2 THEN bAuthorized := TRUE; END_IF
            IF AUTHORIZED_SERIAL_3 <> '' AND sSerial = AUTHORIZED_SERIAL_3 THEN bAuthorized := TRUE; END_IF
            IF AUTHORIZED_SERIAL_4 <> '' AND sSerial = AUTHORIZED_SERIAL_4 THEN bAuthorized := TRUE; END_IF
        END_IF
        IF bAuthorized THEN
            nAuthStatus := 1;
        ELSE
            nAuthStatus := 2;
        END_IF
    ELSE
        bAuthorized := FALSE;
        nAuthStatus := 3;
    END_IF
    bAuthChecked := TRUE;
END_IF

// 未授权：强制透传（rVirtualTarget = rTargetRaw, rOutput = 0），让 PID 直接跟踪原始波形
IF NOT bAuthorized THEN
    rOutput        := 0.0;
    rVirtualTarget := rTargetRaw;
    bNewCyclePrev  := bNewCycle;
    RETURN;
END_IF

// ============================================================
// 波形类型映射：上位机经 PP_Trace_Flag(168-169) 直接指定
// 入参 iWaveType 与协议对齐，与内部 nWaveType 数值相同：
//   1=正弦(8 段 α), 2=三角(8 段 α), 3=梯形(12 段 α + 2 段平台),
//   4=矩形(同 3), 5=任意波(逐点 ILC), 6=直线波(斜率限制透传)
// ============================================================
IF iWaveType >= 1 AND iWaveType <= 6 THEN
    nWaveType := iWaveType;
ELSE
    nWaveType := 1; // 未知类型按正弦处理（兜底）
END_IF

// ============================================================
// 事件型 ILC 切分（仅 bSegmentTrigger 上升沿触发一次）
// 流程分 6 阶段，用 bSegContinue 串联门控；任一阶段失败 → 静默退回逐点 ILC
//   1) 入参合法性
//   2) 全程扫描求 min/max
//   3) 双阈值带迟滞切分事件
//   4) 每事件扫平台 → 形状指纹（1=A 钟形, 2=B 单梯形）；多平台直接判失败
//   5) (shape, peak 桶) 分类，类数超限判失败
//   6) 建反查表 + 清旧逐点 ILC 表 / 累加器 + 置 bEventModeActive
// ============================================================
IF bSegmentTrigger AND NOT bSegmentTriggerPrev THEN
    nSegRunCount := nSegRunCount + 1;
    bSegmentationOK  := FALSE;
    bEventModeActive := FALSE;
    nEventCount := 0;
    nClassCount := 0;
    bSegContinue := TRUE;
    bSegMultiPlat := FALSE;
    iSegFailPhase := 0;

    // 阶段 1：入参合法性
    IF NOT (nSegmentPoints >= 2 AND nSegmentPoints <= POINTS_MAX AND pSegmentData <> 0) THEN
        bSegContinue := FALSE;
        iSegFailPhase := 1;
    END_IF

    // 阶段 2：全程扫描
    IF bSegContinue THEN
        rSegMinAll := pSegmentData[0];
        rSegMaxAll := pSegmentData[0];
        FOR iSegI := 1 TO nSegmentPoints - 1 DO
            rSegTgt := pSegmentData[iSegI];
            IF rSegTgt < rSegMinAll THEN rSegMinAll := rSegTgt; END_IF
            IF rSegTgt > rSegMaxAll THEN rSegMaxAll := rSegTgt; END_IF
        END_FOR
        rSegRange := rSegMaxAll - rSegMinAll;
        IF rSegRange < 0.05 THEN
            bSegContinue := FALSE; // 几乎是直流，没有事件结构
            iSegFailPhase := 2;
        END_IF
    END_IF

    // 阶段 3：双阈值切分事件
    IF bSegContinue THEN
        rSegThrUp   := rSegMinAll + EVT_THR_UP_K * rSegRange;
        rSegThrDn   := rSegMinAll + EVT_THR_DN_K * rSegRange;
        rSegFlatThr := EVT_PLAT_FLAT_K * rSegRange;
        bSegInEvent := FALSE;
        nEventCount := 0;
        FOR iSegI := 0 TO nSegmentPoints - 1 DO
            rSegTgt := pSegmentData[iSegI];
            IF NOT bSegInEvent THEN
                IF rSegTgt >= rSegThrUp AND nEventCount < EVT_MAX_EVENTS THEN
                    bSegInEvent := TRUE;
                    iEventStart[nEventCount] := iSegI;
                    rEventPeak[nEventCount]  := rSegTgt;
                END_IF
            ELSE
                IF rSegTgt > rEventPeak[nEventCount] THEN
                    rEventPeak[nEventCount] := rSegTgt;
                END_IF
                IF rSegTgt <= rSegThrDn THEN
                    iEventEnd[nEventCount] := iSegI - 1;
                    IF (iEventEnd[nEventCount] - iEventStart[nEventCount] + 1) >= EVT_MIN_EVENT_LEN THEN
                        nEventCount := nEventCount + 1;
                    END_IF
                    bSegInEvent := FALSE;
                    IF nEventCount >= EVT_MAX_EVENTS THEN
                        EXIT;
                    END_IF
                END_IF
            END_IF
        END_FOR
        // 末尾仍在事件内
        IF bSegInEvent AND nEventCount < EVT_MAX_EVENTS THEN
            iEventEnd[nEventCount] := nSegmentPoints - 1;
            IF (iEventEnd[nEventCount] - iEventStart[nEventCount] + 1) >= EVT_MIN_EVENT_LEN THEN
                nEventCount := nEventCount + 1;
            END_IF
        END_IF
        IF nEventCount < EVT_MIN_EVENTS THEN
            nEventCount := 0;
            bSegContinue := FALSE;
            iSegFailPhase := 3;
        END_IF
    END_IF

    // 阶段 4：形状判定（扫平台）
    IF bSegContinue THEN
        FOR iSegK := 0 TO nEventCount - 1 DO
            nSegPlatInEvt := 0;
            iSegPlatS     := -1;
            iSegPlatE     := -1;
            rSegPlatLvl   := 0.0;
            iSegScan      := iEventStart[iSegK];

            WHILE iSegScan + EVT_MIN_PLAT_LEN - 1 <= iEventEnd[iSegK] DO
                rSegWinMin := pSegmentData[iSegScan];
                rSegWinMax := pSegmentData[iSegScan];
                FOR iSegJ := 1 TO EVT_MIN_PLAT_LEN - 1 DO
                    rSegTgt := pSegmentData[iSegScan + iSegJ];
                    IF rSegTgt < rSegWinMin THEN rSegWinMin := rSegTgt; END_IF
                    IF rSegTgt > rSegWinMax THEN rSegWinMax := rSegTgt; END_IF
                END_FOR

                IF (rSegWinMax - rSegWinMin) <= rSegFlatThr AND rSegWinMax >= rSegThrUp THEN
                    IF nSegPlatInEvt = 0 THEN
                        iSegPlatS     := iSegScan;
                        iSegPlatE     := iSegScan + EVT_MIN_PLAT_LEN - 1;
                        rSegPlatLvl   := (rSegWinMax + rSegWinMin) / 2.0;
                        nSegPlatInEvt := 1;
                        // 向右扩展同一平台
                        bSegExtended := TRUE;
                        iSegJ := iSegPlatE + 1;
                        WHILE bSegExtended AND iSegJ <= iEventEnd[iSegK] DO
                            rSegTgt := pSegmentData[iSegJ];
                            IF ABS(rSegTgt - rSegPlatLvl) <= rSegFlatThr THEN
                                iSegPlatE := iSegJ;
                                iSegJ := iSegJ + 1;
                            ELSE
                                bSegExtended := FALSE;
                            END_IF
                        END_WHILE
                        iSegScan := iSegPlatE + 1;
                    ELSE
                        bSegMultiPlat := TRUE;
                        EXIT;
                    END_IF
                ELSE
                    iSegScan := iSegScan + 1;
                END_IF
            END_WHILE

            IF bSegMultiPlat THEN
                EXIT;
            END_IF

            IF nSegPlatInEvt = 1 THEN
                iEventShape[iSegK]     := 2;        // B: 单梯形
                iEventPlatStart[iSegK] := iSegPlatS;
                iEventPlatEnd[iSegK]   := iSegPlatE;
                rEventPeak[iSegK]      := rSegPlatLvl; // B 型用平台幅值替代峰值
            ELSE
                iEventShape[iSegK]     := 1;        // A: 钟形
                iEventPlatStart[iSegK] := -1;
                iEventPlatEnd[iSegK]   := -1;
            END_IF
        END_FOR

        IF bSegMultiPlat THEN
            // V1 不支持多平台事件
            nEventCount := 0;
            bSegContinue := FALSE;
            iSegFailPhase := 4;
        END_IF
    END_IF

    // 阶段 5：分类 (shape, peak 桶)
    IF bSegContinue THEN
        rSegClassGap := EVT_CLASS_GAP_K * rSegRange;
        nClassCount := 0;
        FOR iSegK := 0 TO nEventCount - 1 DO
            iSegCls := -1;
            FOR iSegJ := 0 TO nClassCount - 1 DO
                IF iClassShape[iSegJ] = iEventShape[iSegK]
                AND ABS(rClassPeakRef[iSegJ] - rEventPeak[iSegK]) <= rSegClassGap THEN
                    iSegCls := iSegJ;
                    EXIT;
                END_IF
            END_FOR
            IF iSegCls < 0 THEN
                IF nClassCount >= EVT_MAX_CLASSES THEN
                    bSegContinue := FALSE;
                    iSegFailPhase := 5;
                    EXIT;
                END_IF
                iSegCls := nClassCount;
                iClassShape[iSegCls]   := iEventShape[iSegK];
                rClassPeakRef[iSegCls] := rEventPeak[iSegK];
                FOR iSegJ := 1 TO 8 DO
                    rEvtBinCorr[iSegCls, iSegJ] := 0.0;
                END_FOR
                nClassCount := nClassCount + 1;
            END_IF
            iEventClass[iSegK] := iSegCls;
        END_FOR
        IF NOT bSegContinue THEN
            nEventCount := 0;
            nClassCount := 0;
        END_IF
    END_IF

    // 阶段 6：建反查表 + 清旧表 + 提交
    IF bSegContinue THEN
        FOR iSegI := 0 TO nSegmentPoints - 1 DO
            iPointToEvent[iSegI] := -1;
        END_FOR
        FOR iSegK := 0 TO nEventCount - 1 DO
            FOR iSegI := iEventStart[iSegK] TO iEventEnd[iSegK] DO
                iPointToEvent[iSegI] := iSegK;
            END_FOR
        END_FOR
        // 清旧逐点 ILC 表（事件模式接管）
        FOR iSegI := 0 TO POINTS_MAX - 1 DO
            rCorrTable5[iSegI] := 0.0;
        END_FOR
        iPtsPerCycle5Last := 0;
        // 清事件累加器
        FOR iSegK := 0 TO EVT_MAX_EVENTS - 1 DO
            FOR iSegJ := 1 TO 8 DO
                rEvtBinErrSum[iSegK, iSegJ] := 0.0;
                iEvtBinErrCnt[iSegK, iSegJ] := 0;
            END_FOR
        END_FOR
        bSegmentationOK  := TRUE;
        bEventModeActive := TRUE;
    END_IF
END_IF
bSegmentTriggerPrev := bSegmentTrigger;

// ============================================================
// 复位 / 禁用
// ============================================================
IF bReset OR NOT bEnable THEN
    IF bReset THEN
        iIterCount        := 0;
        nUpdateCount      := 0;
        rPeakErrSum       := 0.0;
        rValleyErrSum     := 0.0;
        rRmsError         := 0.0;
        bConverged        := FALSE;
        rMidpoint         := 0.0;
        rHalfRange        := 0.0;
        rQuarter          := 0.0;
        rPrevTargetMax    := 0.0;
        rPrevTargetMin    := 0.0;
        rPrevTargetRange  := 0.0;
        rVMax             := 0.0;
        rVMin             := 0.0;
        rScalePos         := 1.0;
        rScaleNeg         := 1.0;
        bVInitialized     := FALSE;
        rActualPrev       := 0.0;
        rTargetPrev       := 0.0;
        // 8 段 α 默认均分
        FOR iBinK := 1 TO 8 DO
            rAlphaCmd[iBinK] := 0.125;
            rAlphaTgt[iBinK] := 0.125;
            rAlphaFb[iBinK]  := 0.125;
        END_FOR
        // 12 段 α 默认均分（1/12 ≈ 0.08333）
        FOR iBinK := 1 TO 12 DO
            rAlpha12Cmd[iBinK] := 0.08333;
            rAlpha12Tgt[iBinK] := 0.08333;
            rAlpha12Fb[iBinK]  := 0.08333;
        END_FOR
        rPlatBotA := 0.0; rPlatBotB := 0.0;
        rPlatTopA := 0.0; rPlatTopB := 0.0;
        // 任意波逐点 ILC：清学习修正表
        FOR iBinK := 0 TO POINTS_MAX - 1 DO
            rCorrTable5[iBinK] := 0.0;
        END_FOR
        iPtsPerCycle5Last := 0;
        // 事件型 ILC：清切分结果 + 类学习器
        bEventModeActive := FALSE;
        bSegmentationOK  := FALSE;
        nEventCount      := 0;
        nClassCount      := 0;
        FOR iEvtK := 0 TO EVT_MAX_CLASSES - 1 DO
            FOR iEvtBb := 1 TO 8 DO
                rEvtBinCorr[iEvtK, iEvtBb] := 0.0;
            END_FOR
        END_FOR
    END_IF
    rOutput        := 0.0;
    rVirtualTarget := 0.0;
    rTargetMax     := -1.0E30;
    rTargetMin     :=  1.0E30;
    rActualMax     := -1.0E30;
    rActualMin     :=  1.0E30;
    rErrorSum2     := 0.0;
    iErrorCount    := 0;
    iBinTotal      := 0;
    FOR iBinK := 1 TO 8 DO
        iTgtBin[iBinK] := 0;
        iFbBin[iBinK]  := 0;
    END_FOR
    FOR iBinK := 1 TO 12 DO
        iTgtBin12[iBinK] := 0;
        iFbBin12[iBinK]  := 0;
    END_FOR
    iBinTotal12    := 0;
    rFbSumBotA := 0.0; rFbSumBotB := 0.0;
    rFbSumTopA := 0.0; rFbSumTopB := 0.0;
    iCntBotA := 0; iCntBotB := 0;
    iCntTopA := 0; iCntTopB := 0;
    FOR iBinK := 0 TO POINTS_MAX - 1 DO
        rErrSum5[iBinK] := 0.0;
        iErrCnt5[iBinK] := 0;
    END_FOR
    // 事件型 ILC：清周期内 (事件 × bin) 累加器
    FOR iEvtK := 0 TO EVT_MAX_EVENTS - 1 DO
        FOR iEvtBb := 1 TO 8 DO
            rEvtBinErrSum[iEvtK, iEvtBb] := 0.0;
            iEvtBinErrCnt[iEvtK, iEvtBb] := 0;
        END_FOR
    END_FOR
    bNewCyclePrev  := FALSE;
    IF NOT bEnable THEN
        RETURN;
    END_IF
END_IF

IF iPointsPerCycle < 10 THEN
    rOutput := 0.0; rVirtualTarget := 0.0; RETURN;
END_IF

// ============================================================
// 新周期边界
// ============================================================
IF bNewCycle AND NOT bNewCyclePrev THEN

    // RMS
    IF iErrorCount > 0 THEN
        rRmsError := SQRT(rErrorSum2 / INT_TO_REAL(iErrorCount));
    END_IF
    rErrorSum2  := 0.0;
    iErrorCount := 0;

    // 8 段分布归一
    IF iBinTotal > 0 THEN
        rBinTotal := INT_TO_REAL(iBinTotal);
        FOR iBinK := 1 TO 8 DO
            rAlphaTgt[iBinK] := INT_TO_REAL(iTgtBin[iBinK]) / rBinTotal;
            rAlphaFb[iBinK]  := INT_TO_REAL(iFbBin[iBinK])  / rBinTotal;
        END_FOR
    END_IF
    FOR iBinK := 1 TO 8 DO
        iTgtBin[iBinK] := 0;
        iFbBin[iBinK]  := 0;
    END_FOR
    iBinTotal := 0;

    // 12 段分布归一
    IF iBinTotal12 > 0 THEN
        rBinTotal := INT_TO_REAL(iBinTotal12);
        FOR iBinK := 1 TO 12 DO
            rAlpha12Tgt[iBinK] := INT_TO_REAL(iTgtBin12[iBinK]) / rBinTotal;
            rAlpha12Fb[iBinK]  := INT_TO_REAL(iFbBin12[iBinK])  / rBinTotal;
        END_FOR
    END_IF
    FOR iBinK := 1 TO 12 DO
        iTgtBin12[iBinK] := 0;
        iFbBin12[iBinK]  := 0;
    END_FOR
    iBinTotal12 := 0;

    // 端点误差
    rPeakError   := rTargetMax - rActualMax;
    rValleyError := rTargetMin - rActualMin;

    // rMidpoint / rHalfRange
    rMidpoint  := (rTargetMax + rTargetMin) / 2.0;
    rHalfRange := (rTargetMax - rTargetMin) / 2.0;
    IF rHalfRange < 0.001 THEN rHalfRange := 0.001; END_IF
    rQuarter   := 0.5 * rHalfRange;

    rPrevTargetMax   := rTargetMax;
    rPrevTargetMin   := rTargetMin;
    rPrevTargetRange := rTargetMax - rTargetMin;

    rTargetMax := -1.0E30; rTargetMin :=  1.0E30;
    rActualMax := -1.0E30; rActualMin :=  1.0E30;

    iIterCount := iIterCount + 1;
    iIteration := iIterCount;

    IF iIterCount <= nWarmupCycles THEN
        // 暖机阶段：透传不学习，等待 vMin/vMax 极值收敛
        nUpdateCount  := 0;
        rPeakErrSum   := 0.0;
        rValleyErrSum := 0.0;

    ELSIF NOT bConverged THEN
        IF NOT bVInitialized THEN
            rVMax := rPrevTargetMax;
            rVMin := rPrevTargetMin;
            bVInitialized := TRUE;
        END_IF

        IF iMaxIterations > 0 AND iIterCount >= iMaxIterations THEN
            bConverged := TRUE;
        ELSE
            // α 8 段自学习（正弦 nWaveType=1 + 三角 nWaveType=2）
            IF bAlphaEnable AND (nWaveType = 1 OR nWaveType = 2) THEN
                FOR iBinK := 1 TO 8 DO
                    rAlphaCmd[iBinK] := rAlphaCmd[iBinK]
                                     + rAlphaLR * (rAlphaTgt[iBinK] - rAlphaFb[iBinK]);
                    IF rAlphaCmd[iBinK] < ALPHA_Q_MIN THEN rAlphaCmd[iBinK] := ALPHA_Q_MIN; END_IF
                    IF rAlphaCmd[iBinK] > ALPHA_Q_MAX THEN rAlphaCmd[iBinK] := ALPHA_Q_MAX; END_IF
                END_FOR
                rAlphaSum := 0.0;
                FOR iBinK := 1 TO 8 DO
                    rAlphaSum := rAlphaSum + rAlphaCmd[iBinK];
                END_FOR
                IF rAlphaSum > 0.001 THEN
                    FOR iBinK := 1 TO 8 DO
                        rAlphaCmd[iBinK] := rAlphaCmd[iBinK] / rAlphaSum;
                    END_FOR
                END_IF
            END_IF

            // α 12 段自学习（梯形 nWaveType=3 + 矩形 nWaveType=4）
            // 组级修正: 当 bin 1(底平)/bin 7(顶平) 被 ALPHA12_Q_MIN 钳死时，
            // 组级误差(升 1..6 / 降 8..12) 会按 α 比例摊到组内其它 bin，
            // 让组总占比能继续学习，避免溢出无人接手。
            IF bAlphaEnable AND (nWaveType = 3 OR nWaveType = 4) THEN
                // 1. 计算组总占比
                rRiseTgtSum  := 0.0; rRiseFbSum  := 0.0; rRiseCmdSum  := 0.0;
                rFallTgtSum  := 0.0; rFallFbSum  := 0.0; rFallCmdSum  := 0.0;
                FOR iBinK := 1 TO 6 DO
                    rRiseTgtSum := rRiseTgtSum + rAlpha12Tgt[iBinK];
                    rRiseFbSum  := rRiseFbSum  + rAlpha12Fb[iBinK];
                    rRiseCmdSum := rRiseCmdSum + rAlpha12Cmd[iBinK];
                END_FOR
                FOR iBinK := 8 TO 12 DO
                    rFallTgtSum := rFallTgtSum + rAlpha12Tgt[iBinK];
                    rFallFbSum  := rFallFbSum  + rAlpha12Fb[iBinK];
                    rFallCmdSum := rFallCmdSum + rAlpha12Cmd[iBinK];
                END_FOR
                rRiseGroupErr := rRiseTgtSum - rRiseFbSum;
                rFallGroupErr := rFallTgtSum - rFallFbSum;

                // 2. 各 bin 更新 = 自身误差 + 所属组的组级误差按 α 比例分摊
                FOR iBinK := 1 TO 12 DO
                    rBinErr := rAlpha12Tgt[iBinK] - rAlpha12Fb[iBinK];
                    IF iBinK <= 6 AND rRiseCmdSum > 0.001 THEN
                        rGroupCorr := rGroupW * rRiseGroupErr
                                    * (rAlpha12Cmd[iBinK] / rRiseCmdSum);
                    ELSIF iBinK >= 8 AND rFallCmdSum > 0.001 THEN
                        rGroupCorr := rGroupW * rFallGroupErr
                                    * (rAlpha12Cmd[iBinK] / rFallCmdSum);
                    ELSE
                        rGroupCorr := 0.0;  // 顶平 bin 7 单段无组可摊
                    END_IF
                    rAlpha12Cmd[iBinK] := rAlpha12Cmd[iBinK]
                                       + rAlphaLR * (rBinErr + rGroupCorr);
                    IF rAlpha12Cmd[iBinK] < ALPHA12_Q_MIN THEN rAlpha12Cmd[iBinK] := ALPHA12_Q_MIN; END_IF
                    IF rAlpha12Cmd[iBinK] > ALPHA12_Q_MAX THEN rAlpha12Cmd[iBinK] := ALPHA12_Q_MAX; END_IF
                END_FOR

                // 3. 归一化使 Σα = 1
                rAlphaSum := 0.0;
                FOR iBinK := 1 TO 12 DO
                    rAlphaSum := rAlphaSum + rAlpha12Cmd[iBinK];
                END_FOR
                IF rAlphaSum > 0.001 THEN
                    FOR iBinK := 1 TO 12 DO
                        rAlpha12Cmd[iBinK] := rAlpha12Cmd[iBinK] / rAlphaSum;
                    END_FOR
                END_IF
            END_IF

            // 事件型 ILC (nWaveType=5 自动升级)：每类 8 段幅值修正，同类事件实例做样本池化
            // 模型：rVirtualTarget[i] = rTargetRaw[i] + rEvtBinCorr[class(i), bin(i)]
            //       周期末对每个类 c，把该类所有事件实例的 bin 误差均值汇总 → 类级更新
            IF bAlphaEnable AND nWaveType = 5 AND bEventModeActive AND nClassCount > 0 THEN
                rEvtBinCorrUpLim := EVT_BIN_CORR_LIM_UP_K * rPrevTargetRange;
                IF rEvtBinCorrUpLim < 0.001 THEN rEvtBinCorrUpLim := 0.001; END_IF
                rEvtBinCorrDnLim := EVT_BIN_CORR_LIM_DN_K * rPrevTargetRange;
                IF rEvtBinCorrDnLim < 0.001 THEN rEvtBinCorrDnLim := 0.001; END_IF
                rEvtDeltaMax := EVT_BIN_DELTA_K * rPrevTargetRange;
                IF rEvtDeltaMax < 0.0001 THEN rEvtDeltaMax := 0.0001; END_IF
                FOR iEvtCls := 0 TO nClassCount - 1 DO
                    FOR iEvtBb := 1 TO 8 DO
                        rEvtPoolErr := 0.0;
                        iEvtPoolCnt := 0;
                        FOR iEvtK := 0 TO nEventCount - 1 DO
                            IF iEventClass[iEvtK] = iEvtCls AND iEvtBinErrCnt[iEvtK, iEvtBb] > 0 THEN
                                rEvtPoolErr := rEvtPoolErr
                                            + rEvtBinErrSum[iEvtK, iEvtBb] / INT_TO_REAL(iEvtBinErrCnt[iEvtK, iEvtBb]);
                                iEvtPoolCnt := iEvtPoolCnt + 1;
                            END_IF
                        END_FOR
                        IF iEvtPoolCnt > 0 THEN
                            rEvtPoolMean := rEvtPoolErr / INT_TO_REAL(iEvtPoolCnt);
                            rEvtDelta := EVT_BIN_CORR_LR * rEvtPoolMean;
                            // 单周期增量限幅：禁止一拍跨过最优修正
                            IF rEvtDelta >  rEvtDeltaMax THEN rEvtDelta :=  rEvtDeltaMax; END_IF
                            IF rEvtDelta < -rEvtDeltaMax THEN rEvtDelta := -rEvtDeltaMax; END_IF
                            rEvtBinCorr[iEvtCls, iEvtBb] := rEvtBinCorr[iEvtCls, iEvtBb] + rEvtDelta;
                            // 总量限幅：UP / DOWN 独立（UP 紧防 actual 过冲，DOWN 宽保留落沿压制能力）
                            IF rEvtBinCorr[iEvtCls, iEvtBb] >  rEvtBinCorrUpLim THEN rEvtBinCorr[iEvtCls, iEvtBb] :=  rEvtBinCorrUpLim; END_IF
                            IF rEvtBinCorr[iEvtCls, iEvtBb] < -rEvtBinCorrDnLim THEN rEvtBinCorr[iEvtCls, iEvtBb] := -rEvtBinCorrDnLim; END_IF
                        END_IF
                    END_FOR
                END_FOR
                // 清本周期 (事件 × bin) 累加器
                FOR iEvtK := 0 TO nEventCount - 1 DO
                    FOR iEvtBb := 1 TO 8 DO
                        rEvtBinErrSum[iEvtK, iEvtBb] := 0.0;
                        iEvtBinErrCnt[iEvtK, iEvtBb] := 0;
                    END_FOR
                END_FOR
            END_IF

            // 任意波 (nWaveType=5) 逐点 ILC: P-type + 三点 Q-filter（事件型未启用时的回退路径）
            // 模型：rVirtualTarget[i] = rTargetRaw[i] + rCorrTable5[i]
            //       rCorrTable5[i] += LR · Q(mean_err[i])
            // 周期点数变化时清表（结构不可比），iPointsPerCycle > POINTS_MAX 时跳过（降级透传）
            IF bAlphaEnable AND nWaveType = 5 AND NOT bEventModeActive AND iPointsPerCycle <= POINTS_MAX THEN
                IF iPointsPerCycle <> iPtsPerCycle5Last THEN
                    FOR iBinK := 0 TO POINTS_MAX - 1 DO
                        rCorrTable5[iBinK] := 0.0;
                    END_FOR
                    iPtsPerCycle5Last := iPointsPerCycle;
                END_IF
                // 1) 各点平均误差 → rQBuf5
                FOR iBinK := 0 TO iPointsPerCycle - 1 DO
                    IF iErrCnt5[iBinK] > 0 THEN
                        rQBuf5[iBinK] := rErrSum5[iBinK] / INT_TO_REAL(iErrCnt5[iBinK]);
                    ELSE
                        rQBuf5[iBinK] := 0.0;
                    END_IF
                END_FOR
                // 2) 三点环绕 Q-filter + 学习率更新 + 限幅
                rCorrLimit5 := ILC5_CORR_LIMIT_K * rPrevTargetRange;
                IF rCorrLimit5 < 0.001 THEN rCorrLimit5 := 0.001; END_IF
                FOR iBinK := 0 TO iPointsPerCycle - 1 DO
                    iLeft5  := iBinK - 1;
                    iRight5 := iBinK + 1;
                    IF iLeft5  < 0                  THEN iLeft5  := iPointsPerCycle - 1; END_IF
                    IF iRight5 >= iPointsPerCycle   THEN iRight5 := 0;                   END_IF
                    rMeanErr5 := ILC5_Q_W0 * rQBuf5[iLeft5]
                               + ILC5_Q_W1 * rQBuf5[iBinK]
                               + ILC5_Q_W0 * rQBuf5[iRight5];
                    rCorrTable5[iBinK] := rCorrTable5[iBinK] + rLearningRate * rMeanErr5;
                    IF rCorrTable5[iBinK] >  rCorrLimit5 THEN rCorrTable5[iBinK] :=  rCorrLimit5; END_IF
                    IF rCorrTable5[iBinK] < -rCorrLimit5 THEN rCorrTable5[iBinK] := -rCorrLimit5; END_IF
                END_FOR
            END_IF

            // 平台分 2 段幅值修正学习（梯形 + 矩形）
            // 双门控：目标平台时间占比 < 3% → 跳过并衰减；样本不足 → 跳过
            IF bPlatCorrEnable AND (nWaveType = 3 OR nWaveType = 4) THEN
                // 顶部平台
                IF rAlpha12Tgt[7] >= PLAT_TGT_MIN_FRAC THEN
                    IF iCntTopA >= 2 THEN
                        rFbAvg := rFbSumTopA / INT_TO_REAL(iCntTopA);
                        rPlatTopA := rPlatTopA + PLAT_CORR_LR * (rPrevTargetMax - rFbAvg);
                    END_IF
                    IF iCntTopB >= 2 THEN
                        rFbAvg := rFbSumTopB / INT_TO_REAL(iCntTopB);
                        rPlatTopB := rPlatTopB + PLAT_CORR_LR * (rPrevTargetMax - rFbAvg);
                    END_IF
                ELSE
                    rPlatTopA := rPlatTopA * PLAT_CORR_DECAY;
                    rPlatTopB := rPlatTopB * PLAT_CORR_DECAY;
                END_IF
                // 底部平台
                IF rAlpha12Tgt[1] >= PLAT_TGT_MIN_FRAC THEN
                    IF iCntBotA >= 2 THEN
                        rFbAvg := rFbSumBotA / INT_TO_REAL(iCntBotA);
                        rPlatBotA := rPlatBotA + PLAT_CORR_LR * (rPrevTargetMin - rFbAvg);
                    END_IF
                    IF iCntBotB >= 2 THEN
                        rFbAvg := rFbSumBotB / INT_TO_REAL(iCntBotB);
                        rPlatBotB := rPlatBotB + PLAT_CORR_LR * (rPrevTargetMin - rFbAvg);
                    END_IF
                ELSE
                    rPlatBotA := rPlatBotA * PLAT_CORR_DECAY;
                    rPlatBotB := rPlatBotB * PLAT_CORR_DECAY;
                END_IF
                // 限幅
                rPlatCorrLimit := PLAT_CORR_LIMIT_K * rHalfRange;
                IF rPlatTopA >  rPlatCorrLimit THEN rPlatTopA :=  rPlatCorrLimit; END_IF
                IF rPlatTopA < -rPlatCorrLimit THEN rPlatTopA := -rPlatCorrLimit; END_IF
                IF rPlatTopB >  rPlatCorrLimit THEN rPlatTopB :=  rPlatCorrLimit; END_IF
                IF rPlatTopB < -rPlatCorrLimit THEN rPlatTopB := -rPlatCorrLimit; END_IF
                IF rPlatBotA >  rPlatCorrLimit THEN rPlatBotA :=  rPlatCorrLimit; END_IF
                IF rPlatBotA < -rPlatCorrLimit THEN rPlatBotA := -rPlatCorrLimit; END_IF
                IF rPlatBotB >  rPlatCorrLimit THEN rPlatBotB :=  rPlatCorrLimit; END_IF
                IF rPlatBotB < -rPlatCorrLimit THEN rPlatBotB := -rPlatCorrLimit; END_IF
            END_IF

            // 端点幅值自学习（加法型，所有波形通用）
            rPeakErrSum   := rPeakErrSum   + rPeakError;
            rValleyErrSum := rValleyErrSum + rValleyError;
            nUpdateCount  := nUpdateCount  + 1;
            IF nUpdateCount >= CYCLES_PER_UPDATE THEN
                rVMax := rVMax + rLearningRate * (rPeakErrSum   / INT_TO_REAL(nUpdateCount));
                rVMin := rVMin + rLearningRate * (rValleyErrSum / INT_TO_REAL(nUpdateCount));
                IF rPrevTargetRange > 0.001 THEN
                    rLimit := V_RANGE_LIMIT_K * rPrevTargetRange;
                    IF rVMax > rPrevTargetMax + rLimit THEN rVMax := rPrevTargetMax + rLimit; END_IF
                    IF rVMax < rPrevTargetMax - rLimit THEN rVMax := rPrevTargetMax - rLimit; END_IF
                    IF rVMin > rPrevTargetMin + rLimit THEN rVMin := rPrevTargetMin + rLimit; END_IF
                    IF rVMin < rPrevTargetMin - rLimit THEN rVMin := rPrevTargetMin - rLimit; END_IF
                END_IF
                IF rVMax <= rVMin + 0.001 THEN
                    rVMax := rVMin + 0.001;
                END_IF
                rPeakErrSum   := 0.0;
                rValleyErrSum := 0.0;
                nUpdateCount  := 0;
            END_IF
        END_IF
    END_IF

    // 诊断派生量 rScalePos / rScaleNeg
    IF rHalfRange > 0.001 AND bVInitialized THEN
        rScalePos := (rVMax - rMidpoint) / rHalfRange;
        rScaleNeg := (rMidpoint - rVMin) / rHalfRange;
    END_IF

    // 缓存梯形/矩形平台 phase 边界（per-sample 与输出阶段共用）
    IF nWaveType = 3 OR nWaveType = 4 THEN
        rT1Cached    := rAlpha12Cmd[1];
        rT6Cached    := rT1Cached + rAlpha12Cmd[2] + rAlpha12Cmd[3]
                     + rAlpha12Cmd[4] + rAlpha12Cmd[5] + rAlpha12Cmd[6];
        rT7Cached    := rT6Cached + rAlpha12Cmd[7];
        rBotMidPhase := rT1Cached * 0.5;
        rTopMidPhase := (rT6Cached + rT7Cached) * 0.5;
    END_IF

    // 复位平台 2 段反馈累加
    rFbSumBotA := 0.0; rFbSumBotB := 0.0;
    rFbSumTopA := 0.0; rFbSumTopB := 0.0;
    iCntBotA := 0; iCntBotB := 0;
    iCntTopA := 0; iCntTopB := 0;

    // 任意波逐点 ILC 误差累加器清零
    IF nWaveType = 5 THEN
        FOR iBinK := 0 TO POINTS_MAX - 1 DO
            rErrSum5[iBinK] := 0.0;
            iErrCnt5[iBinK] := 0;
        END_FOR
    END_IF

END_IF

// ============================================================
// 每个采样点
// ============================================================

// 周期相位
IF iPointsPerCycle > 0 THEN
    rPhi := INT_TO_REAL(iPointIndex) / INT_TO_REAL(iPointsPerCycle);
ELSE
    rPhi := 0.0;
END_IF
IF rPhi < 0.0 THEN rPhi := 0.0; END_IF
IF rPhi > 1.0 THEN rPhi := 1.0; END_IF

// 目标 / 反馈极值跟踪
IF rTargetRaw > rTargetMax THEN rTargetMax := rTargetRaw; END_IF
IF rTargetRaw < rTargetMin THEN rTargetMin := rTargetRaw; END_IF
IF rActual    > rActualMax THEN rActualMax := rActual;    END_IF
IF rActual    < rActualMin THEN rActualMin := rActual;    END_IF

rErrorSum2  := rErrorSum2 + (rTargetRaw - rActual) * (rTargetRaw - rActual);
iErrorCount := iErrorCount + 1;

// 方向检测
IF rTargetRaw >= rTargetPrev THEN bTgtRising := TRUE; ELSE bTgtRising := FALSE; END_IF
rTargetPrev := rTargetRaw;
IF rActual   >= rActualPrev THEN bFbRising  := TRUE; ELSE bFbRising  := FALSE; END_IF
rActualPrev := rActual;

// --------- 8 段分箱（正弦 + 三角共用）---------
IF (nWaveType = 1 OR nWaveType = 2) AND iIterCount >= 1 AND rHalfRange > 0.001 THEN
    iBinTotal := iBinTotal + 1;
    rTgtPos := rTargetRaw - rMidpoint;
    IF bTgtRising THEN
        IF      rTgtPos < -rQuarter THEN iBinK := 1;
        ELSIF   rTgtPos <  0.0      THEN iBinK := 2;
        ELSIF   rTgtPos <  rQuarter THEN iBinK := 3;
        ELSE                              iBinK := 4;
        END_IF
    ELSE
        IF      rTgtPos >  rQuarter THEN iBinK := 5;
        ELSIF   rTgtPos >  0.0      THEN iBinK := 6;
        ELSIF   rTgtPos > -rQuarter THEN iBinK := 7;
        ELSE                              iBinK := 8;
        END_IF
    END_IF
    iTgtBin[iBinK] := iTgtBin[iBinK] + 1;

    rFbPos := rActual - rMidpoint;
    IF bFbRising THEN
        IF      rFbPos < -rQuarter THEN iBinK := 1;
        ELSIF   rFbPos <  0.0      THEN iBinK := 2;
        ELSIF   rFbPos <  rQuarter THEN iBinK := 3;
        ELSE                             iBinK := 4;
        END_IF
    ELSE
        IF      rFbPos >  rQuarter THEN iBinK := 5;
        ELSIF   rFbPos >  0.0      THEN iBinK := 6;
        ELSIF   rFbPos > -rQuarter THEN iBinK := 7;
        ELSE                             iBinK := 8;
        END_IF
    END_IF
    iFbBin[iBinK] := iFbBin[iBinK] + 1;
END_IF

// --------- 12 段分箱（梯形 + 矩形共用）---------
// 1=底平; 2..6=升 5 子段（自下而上）; 7=顶平; 8..12=降 5 子段（自上而下）
// 斜坡振幅区间 [-PLATEAU_BAND_K, +PLATEAU_BAND_K]·hR 五等分
IF (nWaveType = 3 OR nWaveType = 4) AND iIterCount >= 1 AND rHalfRange > 0.001 THEN
    iBinTotal12 := iBinTotal12 + 1;
    rPlateauThr := PLATEAU_BAND_K * rHalfRange;
    rBand1 := -0.6 * rPlateauThr;   // = -0.42 hR
    rBand2 := -0.2 * rPlateauThr;   // = -0.14 hR
    rBand3 :=  0.2 * rPlateauThr;   // = +0.14 hR
    rBand4 :=  0.6 * rPlateauThr;   // = +0.42 hR

    rTgtPos := rTargetRaw - rMidpoint;
    IF rTgtPos < -rPlateauThr THEN
        iBinK := 1;
    ELSIF rTgtPos > rPlateauThr THEN
        iBinK := 7;
    ELSIF bTgtRising THEN
        IF      rTgtPos < rBand1 THEN iBinK := 2;
        ELSIF   rTgtPos < rBand2 THEN iBinK := 3;
        ELSIF   rTgtPos < rBand3 THEN iBinK := 4;
        ELSIF   rTgtPos < rBand4 THEN iBinK := 5;
        ELSE                          iBinK := 6;
        END_IF
    ELSE
        IF      rTgtPos > rBand4 THEN iBinK := 8;
        ELSIF   rTgtPos > rBand3 THEN iBinK := 9;
        ELSIF   rTgtPos > rBand2 THEN iBinK := 10;
        ELSIF   rTgtPos > rBand1 THEN iBinK := 11;
        ELSE                          iBinK := 12;
        END_IF
    END_IF
    iTgtBin12[iBinK] := iTgtBin12[iBinK] + 1;

    rFbPos := rActual - rMidpoint;
    IF rFbPos < -rPlateauThr THEN
        iBinK := 1;
    ELSIF rFbPos > rPlateauThr THEN
        iBinK := 7;
    ELSIF bFbRising THEN
        IF      rFbPos < rBand1 THEN iBinK := 2;
        ELSIF   rFbPos < rBand2 THEN iBinK := 3;
        ELSIF   rFbPos < rBand3 THEN iBinK := 4;
        ELSIF   rFbPos < rBand4 THEN iBinK := 5;
        ELSE                         iBinK := 6;
        END_IF
    ELSE
        IF      rFbPos > rBand4 THEN iBinK := 8;
        ELSIF   rFbPos > rBand3 THEN iBinK := 9;
        ELSIF   rFbPos > rBand2 THEN iBinK := 10;
        ELSIF   rFbPos > rBand1 THEN iBinK := 11;
        ELSE                         iBinK := 12;
        END_IF
    END_IF
    iFbBin12[iBinK] := iFbBin12[iBinK] + 1;
END_IF

// --------- 任意波 (nWaveType=5) 误差累加 ---------
// 事件型：iPointToEvent 按 LUT 索引建表（≤ nSegmentPoints ≤ POINTS_MAX）；
// iPointIndex(扫描空间，可超 POINTS_MAX) 需先映射到 LUT 空间再查表
// 逐点 ILC：rCorrTable5/rErrSum5 按扫描空间索引，仍受 iPointsPerCycle ≤ POINTS_MAX 限制
IF nWaveType = 5 AND iIterCount >= 1 THEN
    IF bEventModeActive AND nSegmentPoints > 0 AND iPointsPerCycle > 0 THEN
        // 扫描空间 → LUT 空间（即便 iPointsPerCycle 远大于 nSegmentPoints 也安全）
        iEvtLutIdx := REAL_TO_INT(INT_TO_REAL(iPointIndex) * INT_TO_REAL(nSegmentPoints)
                                / INT_TO_REAL(iPointsPerCycle));
        IF iEvtLutIdx < 0                 THEN iEvtLutIdx := 0;                  END_IF
        IF iEvtLutIdx >= nSegmentPoints   THEN iEvtLutIdx := nSegmentPoints - 1; END_IF
        iEvtK := iPointToEvent[iEvtLutIdx];
        IF iEvtK >= 0 AND iEvtK < nEventCount THEN
            iEvtLen := iEventEnd[iEvtK] - iEventStart[iEvtK] + 1;
            IF iEvtLen >= 1 THEN
                iEvtLocal := iEvtLutIdx - iEventStart[iEvtK];
                IF iEvtLocal < 0           THEN iEvtLocal := 0;            END_IF
                IF iEvtLocal >= iEvtLen    THEN iEvtLocal := iEvtLen - 1;  END_IF
                rEvtFrac := INT_TO_REAL(iEvtLocal) / INT_TO_REAL(iEvtLen);
                iEvtBinIdx := REAL_TO_INT(rEvtFrac * 8.0) + 1;
                IF iEvtBinIdx < 1 THEN iEvtBinIdx := 1; END_IF
                IF iEvtBinIdx > 8 THEN iEvtBinIdx := 8; END_IF
                rEvtBinErrSum[iEvtK, iEvtBinIdx] := rEvtBinErrSum[iEvtK, iEvtBinIdx] + (rTargetRaw - rActual);
                iEvtBinErrCnt[iEvtK, iEvtBinIdx] := iEvtBinErrCnt[iEvtK, iEvtBinIdx] + 1;
            END_IF
        END_IF
    ELSIF NOT bEventModeActive AND iPointsPerCycle <= POINTS_MAX THEN
        // 逐点 ILC（回退路径，扫描空间表，受 POINTS_MAX 限制）
        iIdx5 := iPointIndex;
        IF iIdx5 < 0                THEN iIdx5 := 0;                  END_IF
        IF iIdx5 >= iPointsPerCycle THEN iIdx5 := iPointsPerCycle - 1; END_IF
        rErrSum5[iIdx5] := rErrSum5[iIdx5] + (rTargetRaw - rActual);
        iErrCnt5[iIdx5] := iErrCnt5[iIdx5] + 1;
    END_IF
END_IF

// --------- 平台 2 段反馈累加（按 cmd phase 切割）---------
IF (nWaveType = 3 OR nWaveType = 4) AND iIterCount >= 1 THEN
    IF rPhi < rT1Cached AND rT1Cached > 0.001 THEN
        IF rPhi < rBotMidPhase THEN
            rFbSumBotA := rFbSumBotA + rActual;
            iCntBotA   := iCntBotA + 1;
        ELSE
            rFbSumBotB := rFbSumBotB + rActual;
            iCntBotB   := iCntBotB + 1;
        END_IF
    ELSIF rPhi >= rT6Cached AND rPhi < rT7Cached AND (rT7Cached - rT6Cached) > 0.001 THEN
        IF rPhi < rTopMidPhase THEN
            rFbSumTopA := rFbSumTopA + rActual;
            iCntTopA   := iCntTopA + 1;
        ELSE
            rFbSumTopB := rFbSumTopB + rActual;
            iCntTopB   := iCntTopB + 1;
        END_IF
    END_IF
END_IF

// ============================================================
// 输出生成
// ============================================================

// 直线波 (nWaveType=6)：斜率限制透传，无学习无暖机
// rVirtualTarget 以 rLinearRate · rDt 每步逼近 rTargetRaw（PMax），到位即保持。
// 起步从复位后的 rVirtualTarget=0；切换波形时从当前值继续。
IF nWaveType = 6 THEN
    rLinearDelta := rLinearRate * rDt;
    IF rLinearDelta < 0.0 THEN rLinearDelta := 0.0; END_IF
    IF rTargetRaw > rVirtualTarget + rLinearDelta THEN
        rVirtualTarget := rVirtualTarget + rLinearDelta;
    ELSIF rTargetRaw < rVirtualTarget - rLinearDelta THEN
        rVirtualTarget := rVirtualTarget - rLinearDelta;
    ELSE
        rVirtualTarget := rTargetRaw;
    END_IF
    rOutput        := rVirtualTarget - rTargetRaw;
    bNewCyclePrev  := bNewCycle;
    RETURN;
END_IF

// 暖机期 / 首次学习窗未到 / 目标无幅值：直通
IF iIterCount <= nWarmupCycles OR rPrevTargetRange < 0.001 THEN
    rVirtualTarget := rTargetRaw;
    rOutput        := 0.0;
    bNewCyclePrev  := bNewCycle;
    RETURN;
END_IF

IF NOT bVInitialized THEN
    rVirtualTarget := rTargetRaw;
    rOutput        := 0.0;
    bNewCyclePrev  := bNewCycle;
    RETURN;
END_IF

// 任意波 (nWaveType=5)：事件型 / 逐点 ILC 两条路径，跳过 vMin/vMax 仿射重映射
// 事件型：iPointToEvent 在 LUT 空间，扫描索引先映射；不受 iPointsPerCycle 大小限制
// 逐点 ILC：rCorrTable5 在扫描空间，iPointsPerCycle > POINTS_MAX 时降级透传
IF nWaveType = 5 THEN
    IF bEventModeActive AND nSegmentPoints > 0 AND iPointsPerCycle > 0 THEN
        // 扫描空间 → LUT 空间
        iEvtLutIdx := REAL_TO_INT(INT_TO_REAL(iPointIndex) * INT_TO_REAL(nSegmentPoints)
                                / INT_TO_REAL(iPointsPerCycle));
        IF iEvtLutIdx < 0                 THEN iEvtLutIdx := 0;                  END_IF
        IF iEvtLutIdx >= nSegmentPoints   THEN iEvtLutIdx := nSegmentPoints - 1; END_IF
        iEvtK := iPointToEvent[iEvtLutIdx];
        IF iEvtK >= 0 AND iEvtK < nEventCount THEN
            iEvtCls := iEventClass[iEvtK];
            iEvtLen := iEventEnd[iEvtK] - iEventStart[iEvtK] + 1;
            iEvtLocal := iEvtLutIdx - iEventStart[iEvtK];
            IF iEvtLocal < 0           THEN iEvtLocal := 0;            END_IF
            IF iEvtLocal >= iEvtLen    THEN iEvtLocal := iEvtLen - 1;  END_IF
            IF iEvtLen >= 1 THEN
                rEvtFrac := INT_TO_REAL(iEvtLocal) / INT_TO_REAL(iEvtLen);
            ELSE
                rEvtFrac := 0.0;
            END_IF
            iEvtBinIdx := REAL_TO_INT(rEvtFrac * 8.0) + 1;
            IF iEvtBinIdx < 1 THEN iEvtBinIdx := 1; END_IF
            IF iEvtBinIdx > 8 THEN iEvtBinIdx := 8; END_IF
            rVirtualTarget := rTargetRaw + rEvtBinCorr[iEvtCls, iEvtBinIdx];
        ELSE
            // 基线段：透传
            rVirtualTarget := rTargetRaw;
        END_IF
    ELSIF NOT bEventModeActive AND iPointsPerCycle <= POINTS_MAX THEN
        // 逐点 ILC（回退路径，扫描空间表，受 POINTS_MAX 限制）
        iIdx5 := iPointIndex;
        IF iIdx5 < 0                THEN iIdx5 := 0;                  END_IF
        IF iIdx5 >= iPointsPerCycle THEN iIdx5 := iPointsPerCycle - 1; END_IF
        rVirtualTarget := rTargetRaw + rCorrTable5[iIdx5];
    ELSE
        // 既未走事件型也超出逐点 ILC 容量：透传
        rVirtualTarget := rTargetRaw;
    END_IF
    rOutput        := rVirtualTarget - rTargetRaw;
    bNewCyclePrev  := bNewCycle;
    RETURN;
END_IF

// 源波形 rSourceTarget：
//   正弦(1) / 三角(2) → α 8 段相位重映射后再按各自基波形重建
//   其他波形         → 直通 rTargetRaw
IF nWaveType = 1 OR nWaveType = 2 THEN
    rT1 := rAlphaCmd[1];
    rT2 := rT1 + rAlphaCmd[2];
    rT3 := rT2 + rAlphaCmd[3];
    rT4 := rT3 + rAlphaCmd[4];
    rT5 := rT4 + rAlphaCmd[5];
    rT6 := rT5 + rAlphaCmd[6];
    rT7 := rT6 + rAlphaCmd[7];

    IF rPhi < rT1 THEN
        IF rT1 > 0.001 THEN rPhiStd := rPhi / rT1 * 0.125; ELSE rPhiStd := 0.0; END_IF
    ELSIF rPhi < rT2 THEN
        rDelta := rT2 - rT1;
        IF rDelta > 0.001 THEN rPhiStd := 0.125 + (rPhi - rT1) / rDelta * 0.125; ELSE rPhiStd := 0.125; END_IF
    ELSIF rPhi < rT3 THEN
        rDelta := rT3 - rT2;
        IF rDelta > 0.001 THEN rPhiStd := 0.250 + (rPhi - rT2) / rDelta * 0.125; ELSE rPhiStd := 0.250; END_IF
    ELSIF rPhi < rT4 THEN
        rDelta := rT4 - rT3;
        IF rDelta > 0.001 THEN rPhiStd := 0.375 + (rPhi - rT3) / rDelta * 0.125; ELSE rPhiStd := 0.375; END_IF
    ELSIF rPhi < rT5 THEN
        rDelta := rT5 - rT4;
        IF rDelta > 0.001 THEN rPhiStd := 0.500 + (rPhi - rT4) / rDelta * 0.125; ELSE rPhiStd := 0.500; END_IF
    ELSIF rPhi < rT6 THEN
        rDelta := rT6 - rT5;
        IF rDelta > 0.001 THEN rPhiStd := 0.625 + (rPhi - rT5) / rDelta * 0.125; ELSE rPhiStd := 0.625; END_IF
    ELSIF rPhi < rT7 THEN
        rDelta := rT7 - rT6;
        IF rDelta > 0.001 THEN rPhiStd := 0.750 + (rPhi - rT6) / rDelta * 0.125; ELSE rPhiStd := 0.750; END_IF
    ELSE
        rDelta := 1.0 - rT7;
        IF rDelta > 0.001 THEN rPhiStd := 0.875 + (rPhi - rT7) / rDelta * 0.125; ELSE rPhiStd := 0.875; END_IF
    END_IF

    IF nWaveType = 1 THEN
        // 正弦：基波形 = (1 - cos(2π·φ_std)) / 2
        rWarpedY := (1.0 - COS(TWO_PI * rPhiStd)) / 2.0;
    ELSE
        // 三角：基波形 = 0→1→0 线性三角，尖峰在 φ_std = 0.5
        IF rPhiStd < 0.5 THEN
            rWarpedY := 2.0 * rPhiStd;
        ELSE
            rWarpedY := 2.0 * (1.0 - rPhiStd);
        END_IF
    END_IF
    rSourceTarget := rPrevTargetMin + rWarpedY * rPrevTargetRange;

ELSIF nWaveType = 3 OR nWaveType = 4 THEN
    // 梯形 / 矩形：12 段相位重映射 + 梯形模板
    // 模板（标准振幅 0..1）：
    //   底平(0) → 升 0→0.2→0.4→0.6→0.8→1 → 顶平(1) → 降 1→0.8→0.6→0.4→0.2→0
    rT1  := rAlpha12Cmd[1];
    rT2  := rT1  + rAlpha12Cmd[2];
    rT3  := rT2  + rAlpha12Cmd[3];
    rT4  := rT3  + rAlpha12Cmd[4];
    rT5  := rT4  + rAlpha12Cmd[5];
    rT6  := rT5  + rAlpha12Cmd[6];
    rT7  := rT6  + rAlpha12Cmd[7];
    rT8  := rT7  + rAlpha12Cmd[8];
    rT9  := rT8  + rAlpha12Cmd[9];
    rT10 := rT9  + rAlpha12Cmd[10];
    rT11 := rT10 + rAlpha12Cmd[11];

    IF rPhi < rT1 THEN
        rWarpedY := 0.0;
    ELSIF rPhi < rT2 THEN
        rDelta := rT2 - rT1;
        IF rDelta > 0.001 THEN rWarpedY := (rPhi - rT1) / rDelta * 0.2;
        ELSE rWarpedY := 0.1; END_IF
    ELSIF rPhi < rT3 THEN
        rDelta := rT3 - rT2;
        IF rDelta > 0.001 THEN rWarpedY := 0.2 + (rPhi - rT2) / rDelta * 0.2;
        ELSE rWarpedY := 0.3; END_IF
    ELSIF rPhi < rT4 THEN
        rDelta := rT4 - rT3;
        IF rDelta > 0.001 THEN rWarpedY := 0.4 + (rPhi - rT3) / rDelta * 0.2;
        ELSE rWarpedY := 0.5; END_IF
    ELSIF rPhi < rT5 THEN
        rDelta := rT5 - rT4;
        IF rDelta > 0.001 THEN rWarpedY := 0.6 + (rPhi - rT4) / rDelta * 0.2;
        ELSE rWarpedY := 0.7; END_IF
    ELSIF rPhi < rT6 THEN
        rDelta := rT6 - rT5;
        IF rDelta > 0.001 THEN rWarpedY := 0.8 + (rPhi - rT5) / rDelta * 0.2;
        ELSE rWarpedY := 0.9; END_IF
    ELSIF rPhi < rT7 THEN
        rWarpedY := 1.0;
    ELSIF rPhi < rT8 THEN
        rDelta := rT8 - rT7;
        IF rDelta > 0.001 THEN rWarpedY := 1.0 - (rPhi - rT7) / rDelta * 0.2;
        ELSE rWarpedY := 0.9; END_IF
    ELSIF rPhi < rT9 THEN
        rDelta := rT9 - rT8;
        IF rDelta > 0.001 THEN rWarpedY := 0.8 - (rPhi - rT8) / rDelta * 0.2;
        ELSE rWarpedY := 0.7; END_IF
    ELSIF rPhi < rT10 THEN
        rDelta := rT10 - rT9;
        IF rDelta > 0.001 THEN rWarpedY := 0.6 - (rPhi - rT9) / rDelta * 0.2;
        ELSE rWarpedY := 0.5; END_IF
    ELSIF rPhi < rT11 THEN
        rDelta := rT11 - rT10;
        IF rDelta > 0.001 THEN rWarpedY := 0.4 - (rPhi - rT10) / rDelta * 0.2;
        ELSE rWarpedY := 0.3; END_IF
    ELSE
        rDelta := 1.0 - rT11;
        IF rDelta > 0.001 THEN rWarpedY := 0.2 - (rPhi - rT11) / rDelta * 0.2;
        ELSE rWarpedY := 0.1; END_IF
    END_IF
    rSourceTarget := rPrevTargetMin + rWarpedY * rPrevTargetRange;

ELSE
    rSourceTarget := rTargetRaw;
END_IF

// 仿射重映射 [tMin, tMax] → [vMin, vMax]
rNorm          := (rSourceTarget - rPrevTargetMin) / rPrevTargetRange;
rVirtualTarget := rVMin + rNorm * (rVMax - rVMin);

// 梯形/矩形平台 2 段幅值修正：按 cmd phase 落在哪个子段叠加对应 MPa 偏置
IF bPlatCorrEnable AND (nWaveType = 3 OR nWaveType = 4) THEN
    IF rPhi < rT1Cached THEN
        IF rPhi < rBotMidPhase THEN
            rVirtualTarget := rVirtualTarget + rPlatBotA;
        ELSE
            rVirtualTarget := rVirtualTarget + rPlatBotB;
        END_IF
    ELSIF rPhi >= rT6Cached AND rPhi < rT7Cached THEN
        IF rPhi < rTopMidPhase THEN
            rVirtualTarget := rVirtualTarget + rPlatTopA;
        ELSE
            rVirtualTarget := rVirtualTarget + rPlatTopB;
        END_IF
    END_IF
END_IF

rOutput := rVirtualTarget - rTargetRaw;

bNewCyclePrev := bNewCycle;

END_FUNCTION_BLOCK
