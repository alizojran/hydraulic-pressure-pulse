"""
Render the V3.6 control architecture block diagram.
Output: /tmp/arch_diagram.png  (used by gen_doc.py)

Labels are placed off-axis from arrows to avoid overlap.
"""
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch, Circle
import matplotlib.font_manager as fm

# CJK font
for fn in ['Noto Sans CJK SC', 'Microsoft YaHei', 'WenQuanYi Zen Hei', 'PingFang SC', 'SimHei']:
    try:
        fp = fm.findfont(fn, fallback_to_default=False)
        if fp and 'DejaVu' not in fp:
            plt.rcParams['font.family'] = fn
            print(f'Using CJK font: {fn}')
            break
    except Exception:
        continue

plt.rcParams['axes.unicode_minus'] = False

fig, ax = plt.subplots(figsize=(10, 8), dpi=160)
ax.set_xlim(0, 10)
ax.set_ylim(0, 13)
ax.axis('off')

# 颜色
C_WAVE  = '#4F81BD'  # 蓝
C_ILC   = '#9BBB59'  # 绿
C_PID   = '#C0504D'  # 红
C_VALV  = '#8064A2'  # 紫
C_SUM   = '#404040'  # 灰
C_ARROW = '#202020'
C_FB    = '#7F7F7F'  # 反馈 浅灰


def box(x, y, w, h, label, color, fc=None):
    if fc is None:
        fc = color + '22'
    bb = FancyBboxPatch(
        (x, y), w, h,
        boxstyle="round,pad=0.04,rounding_size=0.18",
        edgecolor=color, facecolor=fc, linewidth=2,
    )
    ax.add_patch(bb)
    ax.text(x + w/2, y + h/2, label, ha='center', va='center',
            fontsize=10, color=color, weight='bold')


def arrow(x1, y1, x2, y2, color=C_ARROW, lw=1.6, style='-|>'):
    a = FancyArrowPatch(
        (x1, y1), (x2, y2),
        arrowstyle=style, mutation_scale=14,
        color=color, linewidth=lw,
    )
    ax.add_patch(a)


def line(x1, y1, x2, y2, color=C_ARROW, lw=1.6):
    """无箭头线段, 用于折线的非末端段."""
    ax.plot([x1, x2], [y1, y2], color=color, linewidth=lw, solid_capstyle='round')


def label_h(x, y, text, color=C_ARROW, size=9, dy=0.25):
    """水平箭头标签: 放在上方."""
    ax.text(x, y + dy, text, ha='center', va='bottom', fontsize=size, color=color, style='italic')


def label_v(x, y, text, color=C_ARROW, size=9, dx=0.35):
    """垂直箭头标签: 放在右侧."""
    ax.text(x + dx, y, text, ha='left', va='center', fontsize=size, color=color, style='italic')


def sum_node(x, y, sign_left='+', sign_top='+'):
    c = Circle((x, y), 0.28, fc='white', ec=C_SUM, lw=1.8)
    ax.add_patch(c)
    ax.plot([x-0.17, x+0.17], [y, y], color=C_SUM, lw=1.4)
    ax.plot([x, x], [y-0.17, y+0.17], color=C_SUM, lw=1.4)
    ax.text(x-0.50, y, sign_left, fontsize=11, ha='center', va='center', color=C_SUM, weight='bold')
    ax.text(x+0.50, y, sign_top,  fontsize=11, ha='center', va='center', color=C_SUM, weight='bold')


# ============================================================
# 坐标布局
# ============================================================
# 上排两个并排块
WAVE_X, WAVE_Y, WAVE_W, WAVE_H = 0.5, 11.0, 3.0, 1.3
ILC_X,  ILC_Y,  ILC_W,  ILC_H  = 6.5, 11.0, 3.0, 1.3

# 第一加和节点 (右下方, 由 WaveGen + ILC 汇入)
SUM1_X, SUM1_Y = 7.95, 9.3

# 第二加和节点 (rTargetCorrected 与 rActual 求差)
SUM2_X, SUM2_Y = 7.95, 7.2

# PID 块
PID_X, PID_Y, PID_W, PID_H = 6.3, 4.8, 3.3, 1.4

# 阀块
VALV_X, VALV_Y, VALV_W, VALV_H = 6.5, 2.7, 3.0, 1.0
# 试验腔
CHAM_X, CHAM_Y, CHAM_W, CHAM_H = 6.5, 0.7, 3.0, 1.0
# 传感器+滤波 (左下)
SEN_X, SEN_Y, SEN_W, SEN_H = 0.5, 0.7, 3.2, 1.0

# ============================================================
# 块
# ============================================================
box(WAVE_X, WAVE_Y, WAVE_W, WAVE_H, 'FB_WaveformGen\nrTarget (MPa)', C_WAVE)
box(ILC_X,  ILC_Y,  ILC_W,  ILC_H,  'FB_ILC\nrIlcCorrection (MPa)', C_ILC)
box(PID_X,  PID_Y,  PID_W,  PID_H,  'FB_PID\n(Kp·e + Ki·∫e + Kd·de/dt)\nrOutput (V)', C_PID)
box(VALV_X, VALV_Y, VALV_W, VALV_H, '比例伺服阀', C_VALV)
box(CHAM_X, CHAM_Y, CHAM_W, CHAM_H, '试验腔 / 被试件', C_VALV)
box(SEN_X,  SEN_Y,  SEN_W,  SEN_H,  '压力传感器 + 低通滤波\n(PP_Oil_Filter)', C_FB)

# ============================================================
# 箭头
# ============================================================
WAVE_CX = WAVE_X + WAVE_W/2  # 2.0
ILC_CX  = ILC_X  + ILC_W/2   # 8.0
PID_CX  = PID_X  + PID_W/2   # 7.95
VALV_CX = VALV_X + VALV_W/2  # 8.0
CHAM_CX = CHAM_X + CHAM_W/2
SEN_CX  = SEN_X  + SEN_W/2   # 2.1

# 1) WaveGen → ILC 顶部水平 (传 rTargetRaw)
arrow(WAVE_X + WAVE_W, WAVE_Y + WAVE_H*0.55, ILC_X, ILC_Y + ILC_H*0.55, color=C_WAVE, lw=1.5)
ax.text((WAVE_X+WAVE_W + ILC_X)/2, WAVE_Y + WAVE_H*0.55 + 0.25,
        'rTargetRaw', ha='center', va='bottom', fontsize=9, color=C_WAVE, style='italic')

# 2) WaveGen → SUM1 (左侧下行 + 横折到 SUM1 左侧 +)
#    折线: 下行段无箭头, 末段才出箭头
line(WAVE_CX, WAVE_Y, WAVE_CX, SUM1_Y, color=C_WAVE, lw=1.7)
arrow(WAVE_CX, SUM1_Y, SUM1_X - 0.28, SUM1_Y, color=C_WAVE, lw=1.7)

# 3) ILC → SUM1 (顶部下行)
arrow(ILC_CX, ILC_Y, SUM1_X, SUM1_Y + 0.28, color=C_ILC, lw=1.7)

# SUM1 标号 (用作 rTargetCorrected)
sum_node(SUM1_X, SUM1_Y, sign_left='+', sign_top='+')

# 4) SUM1 → SUM2 (输出 rTargetCorrected)
arrow(SUM1_X, SUM1_Y - 0.28, SUM2_X, SUM2_Y + 0.28, color=C_ARROW, lw=1.7)
label_v(SUM1_X, (SUM1_Y - 0.28 + SUM2_Y + 0.28)/2, 'rTargetCorrected (MPa)', color='#333', size=9)

# SUM2 节点 (+ -)
sum_node(SUM2_X, SUM2_Y, sign_left='+', sign_top='-')

# 5) SUM2 → PID (rError 下行)
arrow(SUM2_X, SUM2_Y - 0.28, PID_CX, PID_Y + PID_H, color=C_ARROW, lw=1.7)
label_v(SUM2_X, (SUM2_Y - 0.28 + PID_Y + PID_H)/2, 'rError (MPa)', color='#333', size=9)

# 6) PID → 阀 (rUTotal 下行)
arrow(PID_CX, PID_Y, VALV_CX, VALV_Y + VALV_H, color=C_ARROW, lw=1.7)
label_v(PID_CX, (PID_Y + VALV_Y + VALV_H)/2, 'rUTotal = rUPid (V)\n(±10V 限幅 → FPGA)', color='#333', size=8.5)

# 7) 阀 → 试验腔
arrow(VALV_CX, VALV_Y, CHAM_CX, CHAM_Y + CHAM_H, color=C_VALV, lw=1.7)

# 8) 试验腔 → 传感器 (底部回流, 水平左移)
arrow(CHAM_X, CHAM_Y + CHAM_H/2, SEN_X + SEN_W, SEN_Y + SEN_H/2, color=C_FB, lw=1.5)
ax.text((CHAM_X + SEN_X + SEN_W)/2, SEN_Y + SEN_H/2 + 0.25,
        '物理压力', ha='center', va='bottom', fontsize=8.5, color=C_FB, style='italic')

# 9) 传感器 → SUM2 - 输入 (左侧上行 + 横折; 折线末端才出箭头)
FB_X = SEN_CX  # 2.1
line(FB_X, SEN_Y + SEN_H, FB_X, SUM2_Y, color=C_FB, lw=1.5)
arrow(FB_X, SUM2_Y, SUM2_X - 0.28, SUM2_Y, color=C_FB, lw=1.5)
# rActual 标签放线左侧
ax.text(FB_X - 0.30, (SEN_Y + SEN_H + SUM2_Y)/2, 'rActual (MPa)\n反馈',
        ha='right', va='center', fontsize=9, color=C_FB, style='italic')

# ============================================================
# 注释 (ILC 说明) — 放在两个顶部块下方中间空白处, 不压线
# ============================================================
ax.text((WAVE_X + WAVE_W + ILC_X)/2, WAVE_Y - 0.7,
        'ILC 输入 rTargetRaw, 学包络外采样的误差,\n输出 MPa 域的指令修正量',
        ha='center', va='top', fontsize=8.5, color='#555', style='italic',
        bbox=dict(boxstyle='round,pad=0.4', facecolor='#f5f5f5', edgecolor='#bbb', lw=0.8))

# 标题
ax.text(5, 12.7, '控制架构: ILC 修指令 + PID 反馈',
        ha='center', fontsize=13, weight='bold', color='#1f3864')

plt.tight_layout()
out = '/tmp/arch_diagram.png'
fig.savefig(out, dpi=180, bbox_inches='tight', facecolor='white')
print(f'Saved: {out}')
