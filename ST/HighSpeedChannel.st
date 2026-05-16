FUNCTION HighSpeedChannel : REAL
VAR_INPUT
	Axis : PWmotion.AxisData;
	Channel : INT;
END_VAR

CASE Channel OF
	0:
	HighSpeedChannel := PWmotion.fpgadata.AD.AD_Volt[0];
	1:
	HighSpeedChannel := PWmotion.fpgadata.AD.AD_Volt[1];	
	2:
	HighSpeedChannel := PWmotion.fpgadata.AD.AD_Volt[2];
	3:
	HighSpeedChannel := PWmotion.fpgadata.AD.AD_Volt[3];
	4:
	HighSpeedChannel := PWmotion.fpgadata.AD.AD_Volt[4];
	5:
	HighSpeedChannel := PWmotion.fpgadata.AD.AD_Volt[5];	
	6:
	HighSpeedChannel := PWmotion.fpgadata.AD.AD_Volt[6];
	7:
	HighSpeedChannel := PWmotion.fpgadata.AD.AD_Volt[7];
	8:
	HighSpeedChannel := Axis.Pos_KP;
	9:
	HighSpeedChannel := Axis.Pos_Ki;	
	10:
	HighSpeedChannel := Axis.Pos_VelocityFFCoefficient;		
	11:
	HighSpeedChannel := Axis.Pos_VelocityFWCoefficient;		
	12:
	HighSpeedChannel := Axis.Pressure_KP;
	13:
	HighSpeedChannel := Axis.Pressure_Ki;	
	14:
	HighSpeedChannel := Axis.Force_KP;		
	15:
	HighSpeedChannel := Axis.Force_Ki;		
	16:
	HighSpeedChannel := Axis.Force_VelocityFFCoefficient;
	17:
	HighSpeedChannel := Axis.Force_ForceFFCoefficient;	
	18:
	HighSpeedChannel := Axis.Force_VelocityFWCoefficient;		
	19:
	HighSpeedChannel := Axis.PIDout;		
	20:
	HighSpeedChannel := Axis.PositionCMD;		
	21:
	HighSpeedChannel := Axis.PressureCMD;		
	22:
	HighSpeedChannel := Axis.ForceCMD;
	23:
	HighSpeedChannel := Axis.PositionError;	
	24:
	HighSpeedChannel := Axis.PressureError;		
	25:
	HighSpeedChannel := Axis.ForceError;	
    
	
END_CASE

END_FUNCTION