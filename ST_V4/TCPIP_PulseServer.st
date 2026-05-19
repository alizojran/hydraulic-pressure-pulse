PROGRAM TCPIP_PulseServer
VAR
	ServerPORT : UINT := 502; // ---- 服务器参数 ----
	IP_ADR_server : NBS.IP_ADDR; // 控制器 IP，按实际修改
	TCP_Server_open : NBS.TCP_Server; // ---- NBS 功能块 ----
 功能块链路：TCP_Server_open → TCP_Connection → server_read / server_write
 TCP_Server_open: 打开服务端，绑定IP和端口，输出 hServer
	TCP_Connection : NBS.TCP_Connection; // TCP_Connection: 在 hServer 上等待客户端连接，输出 hConnection
	server_read : NBS.TCP_Read; // server_read: 通过 hConnection 读取上位机下发的数据
	server_write : NBS.TCP_Write; // server_write: 通过 hConnection 将 PLC 数据发送给上位机
	server_en : BOOL := TRUE; // ---- 控制标志 ----
	initial_run : BOOL := TRUE;
	connectNG : BOOL;
	re_connection : R_TRIG;
	i_for : UINT; // ---- 写控制（每帧交替触发上升沿） ----
 NBS.TCP_Write 的 xExecute 端口需要上升沿才能触发发送，
 连续为 TRUE 时只执行一次，后续不会重复发送。
 因此使用 write_mark_bool = [FALSE, TRUE] 交替触发方案：
   - i_for=0 时 write_mark_bool[0]=FALSE → 不触发（产生下降沿）
   - i_for=1 时 write_mark_bool[1]=TRUE  → 触发发送（产生上升沿）
 下一周期再次循环，FALSE→TRUE 形成新的上升沿，确保每周期都能发送一次。
 这种 FALSE/TRUE 交替模式使得 xExecute 在每次循环中都经历
 FALSE→TRUE 的跳变，满足 NBS.TCP_Write 对上升沿的要求。
	write_mark_bool : ARRAY[0..1] OF BOOL;
	write_done_bool : ARRAY[0..1] OF BOOL;
	write_busy_bool : ARRAY[0..1] OF BOOL;
	write_error_bool : ARRAY[0..1] OF BOOL;
	mark_for_mun : UINT := 1; // ==2026-05-10，mark_for_mun初始化值为1
	blink_server : blink_num_hjj; // ---- 服务器异常重启 FT ----
 blink_server 容错重启机制：
 当 TCP_Server_open 报错（xError=TRUE）或服务器句柄无效（hServer=0）时，
 说明服务器进入异常状态，无法正常工作。
 此时调用 blink_server 闪烁 server_en 使能信号（F_num=5次，T_num=50ms周期），
 即 server_en 在短时间内被反复置 FALSE/TRUE，产生多次下降沿和上升沿。
 每次上升沿相当于对 TCP_Server_open 重新使能（xEnable 从 FALSE→TRUE），
 从而自动触发服务器重新打开（open→listen），实现异常后的自动恢复。
 当服务器恢复正常后，server_en 保持为 TRUE，不再闪烁。
	cishuhaha : INT; // ---- 通讯统计 ----
	FrameTick : DINT; // ---- 10 ms 周期帧计数 ----
END_VAR

// ============================================================
// 每周期首先执行数据打包（PLC→PC）
// 这是最先执行的步骤：将 PLC 当前所有需要上传的状态、数据
// 写入 INPUT_REGISTER 缓冲区，为后续 TCP_Write 发送做准备。
// 必须在 TCP_Write 之前调用，否则发送的是上一周期的旧数据。
// ============================================================
TCP_PLC_to_PC();
(*
// ============================================================
// 初始化：动态计算 FOR 循环上界
// mark_for_mun = SIZEOF(write_mark_bool) - 1
// 仅在首次执行时计算一次，后续周期不再重复计算（因为数组大小固定）
// ============================================================
IF initial_run THEN
    mark_for_mun := SIZEOF(write_mark_bool) - 1;
END_IF

// ============================================================
// 服务器异常后 FT 自动重启使能
// 容错重启机制：
//   当 TCP_Server_open 出现错误（xError=TRUE）或句柄丢失（hServer=0）时，
//   blink_server 开始闪烁 server_en（反复 FALSE/TRUE），产生上升沿触发重新打开服务器。
//   当服务器恢复正常（xError=FALSE 且 hServer≠0）时，server_en 保持 TRUE，闪烁停止。
// ============================================================
IF TCP_Server_open.xError OR (TCP_Server_open.hServer = 0) THEN
    blink_server(i_enable := TRUE, out_bool => server_en);
ELSE
    server_en := TRUE;
    blink_server(i_enable := FALSE);
END_IF

// ============================================================
// 启动/重启 TCP Server
// 服务器生命周期第一步：open（打开套接字）
//   - xEnable 上升沿触发：绑定 IP_ADR_server + ServerPORT，开始监听
//   - 输出 xBusy=TRUE 表示正在监听，hServer 为服务器句柄（供 TCP_Connection 使用）
//   - 输出 xDone=TRUE 表示服务器已关闭（xEnable 下降沿时）
//   - 输出 xError=TRUE 表示打开失败
// 当 connectNG（连接丢失）或首次运行时，重新调用以确保服务器处于监听状态
// ============================================================
IF connectNG OR initial_run THEN
    cishuhaha := cishuhaha + 1;
    TCP_Server_open(
        xEnable  := server_en,
        ipAddr   := IP_ADR_server,
        uiPort   := ServerPORT,
        xDone    => ,
        xBusy    => ,
        xError   => ,
        eError   => ,
        hServer  => );
END_IF

// ============================================================
// 检测客户端连接
// 服务器生命周期第二步：accept（接受客户端连接）
//   - xEnable 持续为 TRUE 时，TCP_Connection 等待客户端连接
//   - hServer 由 TCP_Server_open 提供，标识在哪个服务器上等待连接
//   - 连接成功后 xActive=TRUE，hConnection 为连接句柄（供 Read/Write 使用）
//   - xError=TRUE 表示连接失败
//   re_connection 检测连接丢失的上升沿（connectNG 从 FALSE→TRUE），
//   短暂禁用 TCP_Connection 以触发重新等待连接
// ============================================================
connectNG := (TCP_Connection.hConnection = 0);
re_connection(CLK := connectNG);

TCP_Connection(
    xEnable     := TCP_Server_open.xBusy AND NOT re_connection.Q,
    hServer     := TCP_Server_open.hServer,
    xDone       => ,
    xBusy       => ,
    xError      => ,
    eError      => ,
    xActive     => ,
    hConnection => );

// ============================================================
// READ：接收上位机数据 → HOLDING_REGISTER
// 服务器生命周期第三步：read（读取数据）
//   - xEnable 持续为 TRUE 时，每周期尝试从已建立的连接中读取数据
//   - hConnection 由 TCP_Connection 提供
//   - szSize 指定读取长度 = HOLDING_REGISTER 的大小
//   - pData 指向 HOLDING_REGISTER 的地址，数据直接写入该缓冲区
//   - xReady=TRUE 表示有新数据到达（可在此触发解析）
//   - xDone=TRUE 表示读取完成
//   - 读取到的数据将由最后的 TCP_PC_to_PLC() 进行解析
// ============================================================
server_read(
    xEnable     := TCP_Connection.xActive,
    hConnection := TCP_Connection.hConnection,
    szSize      := SIZEOF(TCP_PC_to_PLC.HOLDING_REGISTER),
    pData       := ADR(TCP_PC_to_PLC.HOLDING_REGISTER),
    xDone       => ,
    xBusy       => ,
    xError      => ,
    eError      => ,
    xReady      => ,
    szCount     => );

// ============================================================
// WRITE：发送 INPUT_REGISTER → 上位机（每周期写一次，交替触发）
// 服务器生命周期第四步：write（写入数据）
//   使用 FOR 循环 + write_mark_bool 交替触发方案：
//   - i_for=0: write_mark_bool[0]=FALSE → xExecute=FALSE（下降沿，为下次上升沿做准备）
//   - i_for=1: write_mark_bool[1]=TRUE  → xExecute=TRUE（上升沿，触发本次发送）
//   每个扫描周期内，同一个 server_write 功能块被调用两次：
//     第一次(FALSE)复位内部状态，第二次(TRUE)产生上升沿触发发送。
//   这是因为 NBS.TCP_Write 的 xExecute 需要上升沿触发，
//   如果 xExecute 始终为 TRUE 则只会发送一次，不会持续发送。
//   交替触发确保每个 10ms 周期都能成功发送一帧数据。
//   发送的数据是 INPUT_REGISTER，由 TCP_PLC_to_PC() 在周期开始时打包完毕。
// ============================================================
FOR i_for := 0 TO mark_for_mun DO
    server_write(
        xExecute    := TCP_Connection.xActive AND write_mark_bool[i_for],
        udiTimeOut  := 3008,
        hConnection := TCP_Connection.hConnection,
        szSize      := SIZEOF(TCP_PLC_to_PC.INPUT_REGISTER),
        pData       := ADR(TCP_PLC_to_PC.INPUT_REGISTER),
        xDone       => write_done_bool[i_for],
        xBusy       => write_busy_bool[i_for],
        xError      => write_error_bool[i_for],
        eError      => );
END_FOR


// ============================================================
// 结束初始化标志
// ============================================================
IF initial_run THEN
    initial_run := FALSE;
END_IF

// ============================================================
// 解析上位机数据（PC→PLC）
// 这是最后执行的步骤：从 HOLDING_REGISTER 中提取上位机下发的
// 各项参数（如设定值、命令等），写入对应的 PLC 变量。
// 必须在 TCP_Read 之后调用，因为此时 HOLDING_REGISTER 中才有最新接收的数据。
// 执行顺序总结：打包(TCP_PLC_to_PC) → 发送(TCP_Write) → 接收(TCP_Read) → 解析(TCP_PC_to_PLC)
// ============================================================

*)
// ============================================================
// 10 ms 帧计数递增（PLC→PC 帧计数器）
// FrameTick 每周期 +1，写入 PP_FrameCounter_PLC，
// 上位机可通过此值判断 PLC 是否在正常运行和通讯
// ============================================================
FrameTick := FrameTick + 1;
GVL_PulsePressure.PP_FrameCounter_PLC := DINT_TO_REAL(FrameTick);

TCP_PC_to_PLC();
END_PROGRAM
