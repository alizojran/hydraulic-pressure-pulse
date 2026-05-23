FUNCTION FN_PulseWave : REAL
// 根据相位计算单点目标压力。被 FB_WaveformGen 在多处复用：
//   - 主波形 (当前相位)
//   - MFF 超前 (φ + lead·Δφ)
//   - 误差包络 (φ ± rEnvPctT)
// 段宽参数 rR/rH/rF/rRing/rPeakOS 在调用前已由调用方归一化并保护过。
VAR_INPUT
	rPhaseIn : REAL; // 相位 (0~1)
	rPMin : REAL; // 最低压力 (MPa)
	rPMax : REAL; // 最高压力 (MPa)
	iWaveType : INT; // 0=正弦 1=梯形 2=ARP1383水锤
	rR : REAL; // 上升段占比 (已归一化)
	rH : REAL; // 保持段占比
	rF : REAL; // 下降段占比
	rRing : REAL; // (仅水锤) 过冲后稳定段占比
	rPeakOS : REAL; // (仅水锤) 过冲峰压力 (MPa)
END_VAR
VAR CONSTANT
	PI : REAL := 3.14159265358979;
END_VAR


CASE iWaveType OF

0:  // 正弦波 (-cos 形式，从 PMin 平滑起步)
    FN_PulseWave := (rPMax + rPMin) / 2.0
                    - (rPMax - rPMin) / 2.0 * COS(2.0 * PI * rPhaseIn);

1:  // 梯形波
    IF rPhaseIn < rR THEN
        FN_PulseWave := rPMin + (rPMax - rPMin) * (rPhaseIn / rR);
    ELSIF rPhaseIn < (rR + rH) THEN
        FN_PulseWave := rPMax;
    ELSIF rPhaseIn < (rR + rH + rF) THEN
        FN_PulseWave := rPMax - (rPMax - rPMin) * ((rPhaseIn - rR - rH) / rF);
    ELSE
        FN_PulseWave := rPMin;
    END_IF

2:  // ARP1383C 水锤波 (五段：过冲峰 / 过冲后稳定 / 保压 / 下降 / 低保持)
    IF rPhaseIn < rR THEN
        FN_PulseWave := rPeakOS;
    ELSIF rPhaseIn < (rR + rRing) THEN
        FN_PulseWave := rPMax;
    ELSIF rPhaseIn < (rR + rRing + rH) THEN
        FN_PulseWave := rPMax;
    ELSIF rPhaseIn < (rR + rRing + rH + rF) THEN
        FN_PulseWave := rPMax - (rPMax - rPMin) * ((rPhaseIn - rR - rRing - rH) / rF);
    ELSE
        FN_PulseWave := rPMin;
    END_IF

ELSE
    // 默认正弦
    FN_PulseWave := (rPMax + rPMin) / 2.0
                    - (rPMax - rPMin) / 2.0 * COS(2.0 * PI * rPhaseIn);
END_CASE

// 限幅保护
IF FN_PulseWave < 0.0 THEN FN_PulseWave := 0.0; END_IF
IF FN_PulseWave > 50.0 THEN FN_PulseWave := 50.0; END_IF

END_FUNCTION
