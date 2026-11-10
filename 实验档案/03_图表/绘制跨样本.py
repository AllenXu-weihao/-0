"""三配置跨样本配对图。从 MIMO_v2_matlab 根目录运行：
  python "实验档案/03_图表/绘制跨样本.py" "实验档案/01_运行记录/<run_id>"
bootstrap 顺序固定：先新样本后历史样本，候选按 W15_15_15、W21_19_17、W21_21_21，SNR 按 0、10、20、30。
分析种子 271112，每个格子 10000 次。
"""
import csv
import random
import sys
from pathlib import Path

CANDIDATES = ["W15_15_15", "W21_19_17", "W21_21_21"]
COLORS = {"W15_15_15": "#ae532e", "W21_19_17": "#426d9f", "W21_21_21": "#2f6f4e"}
LABELS = {"W15_15_15": "15/15/15", "W21_19_17": "21/19/17", "W21_21_21": "21/21/21"}
LEVELS = [0, 10, 20, 30]
DRAWS = 10000
SEED = 271112


def read_rows(path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def groups(rows):
    out = {}
    for row in rows:
        out.setdefault(row["name"], {}).setdefault(int(float(row["backgroundSNR"])), []).append(row)
    return out


def bootstrap(rng, values):
    n = len(values)
    means = []
    for _ in range(DRAWS):
        total = 0.0
        for _frame in range(n):
            total += values[rng.randrange(n)]
        means.append(total / n)
    means.sort()
    return sum(values) / n, means[249], means[9749]


def bound(n_frames):
    return 1 - 0.05 ** (1 / n_frames)


def analyze(rows, sample, rng):
    grouped = groups(rows)
    found = []
    for name in CANDIDATES:
        for level in LEVELS:
            frame_rows = grouped[name][level]
            delta = [(int(r["candidateErrors"]) - int(r["floatErrors"])) / 24 for r in frame_rows]
            mean, lo, hi = bootstrap(rng, delta)
            wrong = sum(int(r["became_wrong"]) for r in frame_rows)
            right = sum(int(r["became_correct"]) for r in frame_rows)
            dis = sum(int(r["disagreements"]) for r in frame_rows)
            frames = len(frame_rows)
            bits = frames * 24
            upper = bound(frames) if dis == 0 else ""
            found.append({
                "sample": sample, "name": name, "snr": level, "frames": frames, "bits": bits,
                "excess_errors": sum(int(r["candidateErrors"]) - int(r["floatErrors"]) for r in frame_rows),
                "mean_delta_ber": mean, "low": lo, "high": hi,
                "became_wrong": wrong, "became_correct": right, "disagreements": dis,
                "zero_disagreement_upper": upper,
            })
    return found


def write_table(path, found):
    fields = ["sample", "name", "snr", "frames", "bits", "excess_errors", "mean_delta_ber", "low", "high",
              "became_wrong", "became_correct", "disagreements", "zero_disagreement_upper"]
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fields)
        writer.writeheader()
        writer.writerows(found)


def svg(found, out):
    width, height = 1100, 860
    parts = [
        f"<svg xmlns='http://www.w3.org/2000/svg' width='{width}' height='{height}' viewBox='0 0 {width} {height}'>",
        "<title>三配置跨样本配对 ΔBER 与双向翻转</title>",
        f"<rect width='{width}' height='{height}' fill='white'/>",
        "<g font-family='Microsoft YaHei, sans-serif' fill='#19383d'>",
        "<text x='32' y='36' font-size='24'>三配置相对 float 的配对 ΔBER 与双向翻转</text>",
        "<text x='32' y='62' font-size='14'>每个向量的差是（候选错数−浮点错数）/24。竖线是 10000 次配对 bootstrap 的 2.5% 到 97.5%，分析种子 271112。新样本虚线是 8/480，只作参考。</text>",
    ]
    panels = [("新样本", "new", 40), ("历史样本", "historical", 570)]
    for title, sample, x0 in panels:
        subset = [r for r in found if r["sample"] == sample]
        parts.append(f"<text x='{x0}' y='100' font-size='18'>{title}</text>")
        parts.extend(panel_delta(subset, x0, 120, sample == "new"))
        parts.extend(panel_flips(subset, x0, 470))
    x = 40
    for name in CANDIDATES:
        parts.append(f"<rect x='{x}' y='820' width='14' height='14' fill='{COLORS[name]}'/>")
        parts.append(f"<text x='{x+20}' y='832' font-size='13'>{LABELS[name]}</text>")
        x += 150
    parts += ["</g>", "</svg>"]
    out.write_text("<?xml version='1.0' encoding='utf-8'?>\n" + "\n".join(parts) + "\n", encoding="utf-8")


def y_of(value, top, bottom, lo, hi):
    return bottom - (value - lo) / (hi - lo) * (bottom - top)


def panel_delta(subset, x0, y0, show_line):
    top, bottom = y0 + 20, y0 + 250
    left, right = x0 + 50, x0 + 470
    values = [r["mean_delta_ber"] for r in subset] + [r["low"] for r in subset] + [r["high"] for r in subset]
    if show_line:
        values.append(8 / 480)
    lo = min(min(values), 0) - 0.002
    hi = max(max(values), 0) + 0.002
    parts = [
        f"<line x1='{left}' y1='{top}' x2='{left}' y2='{bottom}' stroke='#19383d'/>",
        f"<line x1='{left}' y1='{y_of(0, top, bottom, lo, hi):.1f}' x2='{right}' y2='{y_of(0, top, bottom, lo, hi):.1f}' stroke='#a7b6b3'/>",
        f"<text x='{left-8}' y='{y_of(0, top, bottom, lo, hi)+4:.1f}' font-size='12' text-anchor='end'>0</text>",
    ]
    if show_line:
        y = y_of(8 / 480, top, bottom, lo, hi)
        parts.append(f"<line x1='{left}' y1='{y:.1f}' x2='{right}' y2='{y:.1f}' stroke='#ae532e' stroke-dasharray='5 4'/>")
        parts.append(f"<text x='{right}' y='{y-6:.1f}' font-size='12' text-anchor='end' fill='#ae532e'>8/480</text>")
    for i, level in enumerate(LEVELS):
        cx = left + 50 + i * 100
        parts.append(f"<text x='{cx}' y='{bottom+22}' font-size='13' text-anchor='middle'>{level} dB</text>")
        for j, name in enumerate(CANDIDATES):
            row = next(r for r in subset if r["name"] == name and r["snr"] == level)
            x = cx + (j - 1) * 16
            y = y_of(row["mean_delta_ber"], top, bottom, lo, hi)
            y1 = y_of(row["low"], top, bottom, lo, hi)
            y2 = y_of(row["high"], top, bottom, lo, hi)
            parts.append(f"<line x1='{x}' y1='{y1:.1f}' x2='{x}' y2='{y2:.1f}' stroke='{COLORS[name]}'/>")
            parts.append(f"<circle cx='{x}' cy='{y:.1f}' r='4.5' fill='{COLORS[name]}'/>")
    parts.append(f"<text x='{x0+8}' y='{(top+bottom)/2:.0f}' font-size='13' transform='rotate(-90 {x0+8} {(top+bottom)/2:.0f})' text-anchor='middle'>平均 ΔBER</text>")
    return parts


def panel_flips(subset, x0, y0):
    top, bottom = y0 + 24, y0 + 250
    left = x0 + 50
    peak = max(max(r["became_wrong"], r["became_correct"]) for r in subset)
    peak = max(peak, 1)
    parts = [f"<text x='{x0}' y='{y0+12}' font-size='15'>对变错（上）与错变对（下）</text>"]
    for i, level in enumerate(LEVELS):
        cx = left + 50 + i * 100
        parts.append(f"<text x='{cx}' y='{bottom+22}' font-size='13' text-anchor='middle'>{level} dB</text>")
        for j, name in enumerate(CANDIDATES):
            row = next(r for r in subset if r["name"] == name and r["snr"] == level)
            x = cx + (j - 1) * 18
            hw = 6
            up = (bottom - top) * row["became_wrong"] / peak
            down = (bottom - top) * row["became_correct"] / peak
            mid = (top + bottom) / 2
            parts.append(f"<rect x='{x-hw}' y='{mid-up:.1f}' width='12' height='{up:.1f}' fill='{COLORS[name]}'/>")
            parts.append(f"<rect x='{x-hw}' y='{mid:.1f}' width='12' height='{down:.1f}' fill='{COLORS[name]}' opacity='0.45'/>")
    return parts


def main():
    run = Path(sys.argv[1])
    rng = random.Random(SEED)
    found = analyze(read_rows(run / "raw" / "per_frame.csv"), "new", rng)
    found += analyze(read_rows(run / "raw" / "bridge_per_frame.csv"), "historical", rng)
    out = Path("实验档案") / "03_图表" / run.name / "跨样本"
    out.mkdir(parents=True, exist_ok=True)
    write_table(out / "区间.csv", found)
    svg(found, out / "配对.svg")
    print(out)


if __name__ == "__main__":
    main()
