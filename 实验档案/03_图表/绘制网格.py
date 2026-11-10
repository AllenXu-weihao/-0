"""E2-M 64 点网格。从 MIMO_v2_matlab 根目录运行：
  python "实验档案/03_图表/绘制网格.py" "实验档案/01_运行记录/<run_id>"
输出到 实验档案/03_图表/<run_id>/网格。
"""
import csv
import sys
from pathlib import Path

WIDTHS = [15, 17, 19, 21]
GATE = 69
FLOAT10 = 61


def rows(path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def svg_text(parts):
    return "<?xml version='1.0' encoding='utf-8'?>\n" + "\n".join(parts) + "\n"


def heatmap(table, beta, out):
    lookup = {(int(r["Wa"]), int(r["Wr"])): r for r in table if int(r["Wb"]) == beta}
    w, h = 640, 560
    parts = [
        f"<svg xmlns='http://www.w3.org/2000/svg' width='{w}' height='{h}' viewBox='0 0 {w} {h}'>",
        f"<title>Wβ={beta} 的 10 dB 错数</title>",
        f"<rect width='{w}' height='{h}' fill='white'/>",
        "<g font-family='Microsoft YaHei, sans-serif' fill='#19383d'>",
        f"<text x='32' y='40' font-size='24'>10 dB 错数 · Wβ = {beta}</text>",
        "<text x='32' y='68' font-size='14'>横轴 Wα，纵轴 Wraw。门槛 69。粗框是三条边总宽相同的格子。</text>",
        "<text x='318' y='530' font-size='15' text-anchor='middle'>Wα</text>",
        "<text x='28' y='300' font-size='15' text-anchor='middle' transform='rotate(-90 28 300)'>Wraw</text>",
    ]
    x0, y0, cell = 110, 100, 110
    for i, wa in enumerate(WIDTHS):
        parts.append(f"<text x='{x0 + i*cell + cell/2}' y='96' font-size='15' text-anchor='middle'>{wa}</text>")
    for j, wr in enumerate(reversed(WIDTHS)):
        parts.append(f"<text x='98' y='{y0 + j*cell + cell/2 + 5}' font-size='15' text-anchor='end'>{wr}</text>")
    for i, wa in enumerate(WIDTHS):
        for j, wr in enumerate(reversed(WIDTHS)):
            x = x0 + i * cell
            y = y0 + j * cell
            hit = lookup.get((wa, wr))
            if hit is None:
                fill, label, extra = "#ece7df", "未测", ""
            else:
                e10 = int(hit["e10"])
                fill = "#d7e4dc" if e10 <= GATE else "#e7c7b8"
                label = str(e10)
                extra = ""
            parts.append(f"<rect x='{x}' y='{y}' width='{cell-8}' height='{cell-8}' fill='{fill}' stroke='#19383d' stroke-width='1'/>")
            if hit is not None and wa == wr == beta:
                parts.append(f"<rect x='{x+4}' y='{y+4}' width='{cell-16}' height='{cell-16}' fill='none' stroke='#19383d' stroke-width='3'/>")
                extra = "统一"
            parts.append(f"<text x='{x + (cell-8)/2}' y='{y + 48}' font-size='28' text-anchor='middle'>{label}</text>")
            if extra:
                parts.append(f"<text x='{x + (cell-8)/2}' y='{y + 74}' font-size='13' text-anchor='middle'>{extra}</text>")
    parts += ["</g>", "</svg>"]
    out.write_text(svg_text(parts), encoding="utf-8")


def scatter(table, out):
    costs = [int(r["C"]) for r in table]
    lo, hi = min(costs) - 1500, max(costs) + 1500
    gate_y = (GATE - FLOAT10) / 480
    w, h = 860, 520
    left, right, top, bottom = 90, 790, 90, 430

    def px(c):
        return left + (c - lo) / (hi - lo) * (right - left)

    def py(v):
        return bottom - (v - (-0.004)) / (0.024 - (-0.004)) * (bottom - top)

    parts = [
        f"<svg xmlns='http://www.w3.org/2000/svg' width='{w}' height='{h}' viewBox='0 0 {w} {h}'>",
        "<title>逻辑搬运代理对 10 dB ΔBER</title>",
        f"<rect width='{w}' height='{h}' fill='white'/>",
        "<g font-family='Microsoft YaHei, sans-serif' fill='#19383d'>",
        "<text x='32' y='40' font-size='24'>C 对 10 dB ΔBER</text>",
        "<text x='32' y='68' font-size='14'>ΔBER = (10 dB 候选错 − 61) / 480。虚线是 69 错对应的 0.0167。方块是统一总宽 U，圆点是其余逐边配置。</text>",
        f"<line x1='{left}' y1='{top}' x2='{left}' y2='{bottom}' stroke='#19383d'/>",
        f"<line x1='{left}' y1='{bottom}' x2='{right}' y2='{bottom}' stroke='#19383d'/>",
        f"<line x1='{left}' y1='{py(0):.1f}' x2='{right}' y2='{py(0):.1f}' stroke='#a7b6b3'/>",
        f"<line x1='{left}' y1='{py(gate_y):.1f}' x2='{right}' y2='{py(gate_y):.1f}' stroke='#ae532e' stroke-dasharray='6 4'/>",
        f"<text x='{right-4}' y='{py(gate_y)-6:.1f}' font-size='13' text-anchor='end' fill='#ae532e'>69/480</text>",
        f"<text x='78' y='{py(0)+4:.1f}' font-size='13' text-anchor='end'>0</text>",
        f"<text x='78' y='{py(gate_y)+4:.1f}' font-size='13' text-anchor='end'>0.0167</text>",
        f"<text x='{(left+right)/2:.0f}' y='470' font-size='15' text-anchor='middle'>C（bit/向量）</text>",
        "<text x='22' y='270' font-size='15' text-anchor='middle' transform='rotate(-90 22 270)'>10 dB ΔBER</text>",
    ]
    for c in costs:
        if c in (min(costs), max(costs)) or c % 7920 == 0:
            parts.append(f"<text x='{px(c):.1f}' y='{bottom+22}' font-size='12' text-anchor='middle'>{c}</text>")
    best = min(costs)
    for r in table:
        c = int(r["C"])
        y = (int(r["e10"]) - FLOAT10) / 480
        uniform = r["Wa"] == r["Wr"] == r["Wb"]
        if c == best:
            continue
        if uniform:
            parts.append(f"<rect x='{px(c)-6:.1f}' y='{py(y)-6:.1f}' width='12' height='12' fill='#426d9f'/>")
        else:
            parts.append(f"<circle cx='{px(c):.1f}' cy='{py(y):.1f}' r='5' fill='#7f9a92'/>")
    parts.append(f"<polygon points='{px(best):.1f},{py(0)-11:.1f} {px(best)+9:.1f},{py(0):.1f} {px(best):.1f},{py(0)+11:.1f} {px(best)-9:.1f},{py(0):.1f}' fill='#ae532e'/>")
    parts.append(f"<text x='{px(best)+14:.1f}' y='{py(0)-14:.1f}' font-size='14'>最低 C：U 与 M 都是 W15_15_15</text>")
    parts += [
        f"<circle cx='120' cy='500' r='5' fill='#7f9a92'/>",
        "<text x='132' y='505' font-size='13'>逐边 M</text>",
        "<rect x='210' y='494' width='12' height='12' fill='#426d9f'/>",
        "<text x='228' y='505' font-size='13'>统一 U</text>",
        "</g>", "</svg>",
    ]
    out.write_text(svg_text(parts), encoding="utf-8")


def main():
    run = Path(sys.argv[1])
    table = rows(run / "raw" / "grid_summary.csv")
    if len(table) != 64 or len({r["name"] for r in table}) != 64:
        raise SystemExit(f"需要 64 个不重复配置，实际 {len(table)}")
    out = Path("实验档案") / "03_图表" / run.name / "网格"
    out.mkdir(parents=True, exist_ok=True)
    for beta in WIDTHS:
        heatmap(table, beta, out / f"热图_Wb{beta}.svg")
    scatter(table, out / "散点.svg")
    print(out)


if __name__ == "__main__":
    main()
