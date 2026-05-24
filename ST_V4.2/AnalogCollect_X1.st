FUNCTION_BLOCK AnalogCollect_X1
VAR_INPUT
	Input : INT; // 采集模块输入
	In_Hi_Limit : INT; // 采集模块输入上限
	In_Lo_Limit : INT; // 采集模块输入下限
	Out_Hi_Limit : REAL; // 工程量换算上限
	Out_Lo_Limit : REAL; // 工程量换算下限
END_VAR
VAR_OUTPUT
	Collect_Out : REAL; // 采集信号输出
END_VAR
//模拟量采集函数
//输入信号在正常范围内
IF Input>=In_Lo_Limit AND Input<=In_Hi_Limit THEN
   Collect_Out := ((Out_Hi_Limit - Out_Lo_Limit) * (Input - In_Lo_Limit) / (In_Hi_Limit - In_Lo_Limit)) + Out_Lo_Limit; //包含有隐式转换
END_IF

//该限幅--仅在单极性下适用
//输入信号低值_限幅
IF Input<In_Lo_Limit THEN
	Collect_Out :=Out_Lo_Limit ;
END_IF

//输入信号高值_限幅
IF Input>In_Hi_Limit THEN
	Collect_Out :=Out_Hi_Limit;
END_IF
END_FUNCTION_BLOCK
