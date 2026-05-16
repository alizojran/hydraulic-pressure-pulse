FUNCTION_BLOCK AnalogOutput_X1
VAR_INPUT
	Input : REAL; // 输入(目标设定值)
	In_Hi_Limit : REAL; // 工程量上限
	In_Lo_Limit : REAL; // 工程量下限
	Out_Hi_Limit : INT; // (模块)数字量输出上限
	Out_Lo_Limit : INT; // (模块)数字量输出上限
END_VAR
VAR_OUTPUT
	OutPut : INT; // 转换输出
END_VAR

//模拟量模块输出函数
//设定在正常范围内
IF Input>=In_Lo_Limit AND Input<=In_Hi_Limit THEN
   OutPut := REAL_TO_INT ( ( ( Out_Hi_Limit - Out_Lo_Limit ) * ( Input - In_Lo_Limit ) / ( In_Hi_Limit - In_Lo_Limit ) ) + Out_Lo_Limit ) ;
END_IF
//输出低限_限幅
IF Input<In_Lo_Limit  THEN
   OutPut := Out_Lo_Limit;
END_IF
//输出高限_限幅
IF  Input>In_Hi_Limit THEN
	OutPut := Out_Hi_Limit;
END_IF

END_FUNCTION_BLOCK