"""
Render the V3.6 control architecture block diagram.
Output: /tmp/arch_diagram.png  (used by gen_doc.py)
"""
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch, Circle
import matplotlib.font_manager as fm

# Find a CJK font
cjk_fonts = ['Noto Sans CJK SC', 'Microsoft YaHei', 'WenQuanYi Zen Hei', 'PingFang SC', 'SimHei', 'DejaVu Sans']
for fn in cjk_fonts:
    try:
        fp = fm.findfont(fn, fallback_to_default=False)
        if fp and 'DejaVu' not in fp:
            plt.rcParams['font.family'] = fn
            print(f'Using CJK font: {fn}  ({fp})')
            break
    except Exception:
        continue

plt.rcParams['axes.unicode_minus'] = False

fig, ax = plt.subplots(figsize=(9.5, 7.5), dpi=160)
ax.set_xlim(0, 10)
ax.set_ylim(0, 13)
ax.axis('off')

# 颜色方案
C_WAVE = '#4F81BD'   # 蓝 - 波形发生
C_ILC  = '#9BBB59'   # 绿 - ILC
C_PID  = '#C0504D'   # 红 - PID
C_VALV = '#8064A2'   # 紫 - 执行/物理
C_SUM  = '#404040'   # 灰 - 加和节点
C_ARROW = '#202020'
C_FB    = '#7F7F7F'  # 浅灰 - 反馈回路


def box(x, y, w, h, label, color, fc=None):
    """绘制圆角块, label 多行字符串."""
    if fc is None:
        fc = color + '22'  # transparent fill
    bb = FancyBboxPatch(
        (x, y), w, h,
        boxstyle="round,pad=0.04,rounding_size=0.15",
        edgecolor=color, facecolor=fc, linewidth=2,
    )
    ax.add_patch(bb)
    ax.text(x + w/2, y + h/2, label, ha='center', va='center',
            fontsize=10, color=color, weight='bold')


def arrow(x1, y1, x2, y2, label=None, color=C_ARROW, lw=1.6, style='-|>'):
    a = FancyArrowPatch(
        (x1, y1), (x2, y2),
        arrowstyle=style, mutation_scale=14,
        color=color, linewidth=lw,
    )
    ax.add_patch(a)
    if label:
        mx, my = (x1 + x2) / 2, (y1 + y2) / 2
        ax.text(mx + 0.15, my, label, fontsize=8.5, color=color, va='center')


def sum_node(x, y, sign1='+', sign2='+'):
    """加和圆圈节点."""
    c = Circle((x, y), 0.25, fc='white', ec=C_SUM, lw=1.6)
    ax.add_patch(c)
    ax.plot([x-0.15, x+0.15], [y, y], color=C_SUM, lw=1.2)
    ax.plot([x, x], [y-0.15, y+0.15], color=C_SUM, lw=1.2)
    # signs around node
    ax.text(x-0.45, y+0.05, sign1, fontsize=10, ha='center', color=C_SUM, weight='bold')
    ax.text(x+0.45, y+0.05, sign2, fontsize=10, ha='center', color=C_SUM, weight='bold')


# ===== 布局 =====
# top: FB_WaveformGen
box(0.6, 11.0, 3.2, 1.3,
    'FB_WaveformGen\nrTarget (MPa)',
    C_WAVE)

# top-right: FB_ILC (parallel to wavegen)
box(6.0, 11.0, 3.3, 1.3,
    'FB_ILC\nrIlcCorrection (MPa)',
    C_ILC)

# arrow: WaveGen 提供 rTargetRaw 给 ILC (顶部水平)
arrow(3.8, 11.65, 6.0, 11.65, label='rTargetRaw', color=C_WAVE, lw=1.4)

# sum node 1: rTarget + rIlcCorrection
sum_node(7.65, 9.4, '+', '+')
ax.text(8.0, 9.4, '', fontsize=10)

# WaveGen → sum_1 (左侧下行)
arrow(2.2, 11.0, 2.2, 9.4, color=C_WAVE)
arrow(2.2, 9.4, 7.4, 9.4, color=C_WAVE)
# ILC → sum_1 (右侧下行)
arrow(7.65, 11.0, 7.65, 9.65, color=C_ILC)

# rTargetCorrected
ax.text(7.65, 8.7, 'rTargetCorrected (MPa)',
        ha='center', va='top', fontsize=9.5, style='italic', color='#333333')

# sum node 2: error = rTargetCorrected - rActual
sum_node(7.65, 7.0, '+', '-')

# sum_1 → sum_2
arrow(7.65, 9.15, 7.65, 7.25, color=C_ARROW)

# error label
ax.text(8.05, 6.55, 'rError (MPa)', fontsize=9, color='#555', style='italic')

# FB_PID box
box(6.0, 4.6, 3.3, 1.4,
    'FB_PID\n(Kp·e + Ki·∫e + Kd·de/dt)\nrOutput (V)',
    C_PID)

# sum_2 → PID
arrow(7.65, 6.75, 7.65, 6.0, color=C_ARROW)

# rUTotal label + limiter
ax.text(7.65, 4.2, 'rUTotal = rUPid', ha='center', fontsize=9.5,
        color='#333', weight='bold')
ax.text(7.65, 3.85, '(±10V 限幅 → FPGA)', ha='center', fontsize=8.5, color='#666',
        style='italic')

# 比例伺服阀
box(6.2, 2.4, 3.0, 1.1,
    '比例伺服阀',
    C_VALV)

# PID → 阀
arrow(7.65, 4.6, 7.65, 3.5, color=C_ARROW)

# 试验腔
box(6.2, 0.5, 3.0, 1.1,
    '试验腔 / 被试件',
    C_VALV)
# 阀 → 试验腔
arrow(7.65, 2.4, 7.65, 1.6, color=C_ARROW)

# 反馈传感器 (左下角)
box(0.6, 0.5, 3.0, 1.1,
    '压力传感器\n+ 低通滤波 (PP_Oil_Filter)',
    C_FB)

# 试验腔 → 传感器 (底部回流)
arrow(6.2, 1.05, 3.6, 1.05, color=C_FB, lw=1.4)
ax.text(4.9, 1.25, '物理压力', ha='center', fontsize=8.5, color=C_FB, style='italic')

# 传感器 → rActual → sum_2 减号 (左侧上行)
arrow(2.1, 1.6, 2.1, 7.0, color=C_FB, lw=1.4)
arrow(2.1, 7.0, 7.4, 7.0, color=C_FB, lw=1.4)
ax.text(2.3, 4.3, 'rActual (MPa)\n反馈', fontsize=9, color=C_FB, style='italic')

# 标题
ax.text(5, 12.7, '控制架构: ILC 修指令 + PID 反馈',
        ha='center', fontsize=12.5, weight='bold', color='#1f3864')

# 注释框 (右侧)
note_y = 9.7
ax.text(4.6, 10.5, 'ILC 输入 rTargetRaw,\n学包络外的误差,\n输出 MPa 修正量', fontsize=8,
        color='#555', ha='left', style='italic')

plt.tight_layout()
out = '/tmp/arch_diagram.png'
fig.savefig(out, dpi=180, bbox_inches='tight', facecolor='white')
print(f'Saved: {out}')
