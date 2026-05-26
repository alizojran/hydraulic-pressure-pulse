FUNCTION_BLOCK blink_num_hjj
VAR_INPUT
	i_enable : BOOL := FALSE;
	F_num : UINT := 1;
	T_num : UINT := 1;
END_VAR
VAR_OUTPUT
	out_bool : BOOL;
END_VAR
VAR
	P_num : UINT := 0;
	run_num : UINT := 0;
END_VAR
IF i_enable THEN
	P_num:=F_num+T_num;
	
	IF P_num<=0 THEN
	    out_bool:=FALSE;
	ELSE
	    run_num:=run_num+1;
	    out_bool:=(run_num>F_num);
	END_IF
	
	IF run_num>=P_num THEN
	   	 run_num:=0;
	END_IF
	
ELSE 
	out_bool:=FALSE;	
	run_num:=0;
END_IF
END_FUNCTION_BLOCK
