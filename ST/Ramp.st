FUNCTION_BLOCK Ramp
VAR_INPUT
	Enable : BOOL;
	Stop : BOOL;
	Incre : REAL; // 每秒增量设定
	InPut : REAL; // 给定值
	Cycle : TIME; // 中断周期值
END_VAR
VAR_OUTPUT
	RampOut : REAL;
	CF : BOOL; // 数据变化标志
END_VAR
VAR
	AddValue : REAL; // 增加量△Add
	bChange_Flag : BOOL; // 数据变化标志位
	TempVar : ARRAY[0..5] OF REAL;
	K : REAL; // 斜率K
	RTRIGInst_1 : R_TRIG;
END_VAR


AddValue:=Incre/DINT_TO_REAL((1000/TIME_TO_DINT(Cycle))); //根据程序执行周期和设定的每秒增量计算每个扫描周期应该增加的△Add

IF Enable=TRUE THEN
	     //*******************************************************//
		 {判断输入的数据是否有变化}
         IF InPut<>TempVar[0] THEN   
             bChange_Flag:=TRUE;
         ELSE 
             bChange_Flag:=FALSE;
         END_IF
         CF:=bChange_Flag;//数据变化信号输出	
		 
         RTRIGInst_1(CLK:=bChange_Flag);  //检测输入信号上升沿 
         IF RTRIGInst_1.Q THEN
	         TempVar[1]:=TempVar[0];
         END_IF

         TempVar[0]:=InPut;
        //*******************************************************//
		
		{将相邻两次输入的数据临时保存}
        TempVar[3]:=TempVar[0]; //新输入的数据
        TempVar[4]:=TempVar[1]; //变化前的数据

        K:=TempVar[3] - TempVar[4];   //斜率计算
		
		IF Stop=TRUE THEN
               //判定斜率为正[数值增加]
               IF K > 0 AND TempVar[5] < TempVar[3] THEN
	                TempVar[5]:= TempVar[5] + AddValue;
               ELSIF K > 0 AND TempVar[5] > TempVar[3] THEN
	                TempVar[5]:= TempVar[3];
               END_IF

              //判定判定斜率为负[数值减小]
              IF K < 0 AND TempVar[5] > TempVar[3] THEN
	                 TempVar[5]:= TempVar[5] - AddValue;
              ELSIF K < 0 AND TempVar[5] < TempVar[3] THEN
	                 TempVar[5]:= TempVar[3];
              END_IF
	    END_IF
		
ELSIF Enable=FALSE THEN
	
	TempVar[5]:=0.0;
	
END_IF

RampOut:=TempVar[5];//Ramp输出

END_FUNCTION_BLOCK