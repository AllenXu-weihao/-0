"""阻尼舍入 A/B 的配对图。从 MIMO_v2_matlab 根目录运行：
  python "实验档案/03_图表/绘制阻尼.py" "实验档案/01_运行记录/<run_id>"
bootstrap 顺序固定：宽度先 W15_15_15 后 W21_19_17，比较先 B-A、再 A-float、再 B-float，SNR 按 0、10、20、30。
分析种子 271113。每个格子用 stdlib random.Random 抽 10000 个帧均值，取排序后第 250 与第 9750 个（下标 249 与 9749）。
"""
import csv
import random
import sys
from pathlib import Path

WIDTHS = ["W15_15_15", "W21_19_17"]
COLORS = {"W15_15_15": "#ae532e", "W21_19_17": "#426d9f"}
LABELS = {"W15_15_15": "15/15/15", "W21_19_17": "21/19/17"}
LEVELS = [0, 10, 20, 30]
COMPARISONS = ["B-A", "A-float", "B-float"]
DRAWS = 10000
SEED = 271113


def read_rows(path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def pair_frames(rows):
    grouped = {}
    for row in rows:
        key = (row["name"], int(float(row["backgroundSNR"])))
        grouped.setdefault(key, {}).setdefault(row["arith"], {})[int(row["case_index"])] = row
    return grouped


def series(grouped, name, level, comparison):
    left = grouped[(name, level)]
    frames = sorted(left["A"])
    values = []
    for index in frames:
        a = left["A"][index]
        b = left["B"][index]
        if comparison == "B-A":
            values.append((int(b["candidateErrors"]) - int(a["candidateErrors"])) / 24)
        elif comparison == "A-float":
            values.append((int(a["candidateErrors"]) - int(a["floatErrors"])) / 24)
        else:
            values.append((int(b["candidateErrors"]) - int(b["floatErrors"])) / 24)
    return values


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


def analyze(rows, rng):
    grouped = pair_frames(rows)
    found = []
    for name in WIDTHS:
        for comparison in COMPARISONS:
            for level in LEVELS:
                values = series(grouped, name, level, comparison)
                mean, lo, hi = bootstrap(rng, values)
                frames = len(values)
                found.append({
                    "name": name, "comparison": comparison, "snr": level,
                    "frames": frames, "bits": frames * 24,
                    "excess_errors": int(round(mean * frames * 24)),
                    "mean_delta_ber": mean, "low": lo, "high": hi,
                    "degenerate_zero": int(lo == 0 and hi == 0),
                    "zero_hard_upper": bound(frames) if lo == 0 and hi == 0 else "",
                })
    return found


def write_table(path, found):
    fields = ["name", "comparison", "snr", "frames", "bits", "excess_errors",
              "mean_delta_ber", "low", "high", "degenerate_zero", "zero_hard_upper"]
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fields)
        writer.writeheader()
        writer.writerows(found)


def y_of(value, top, bottom, lo, hi):
    return bottom - (value - lo) / (hi - lo) * (bottom - top)


def panel_delta(found, comparison, x0, y0):
    subset = [r for r in found if r["comparison"] == comparison]
    top, bottom = y0 + 28, y0 + 210
    left, right = x0 + 56, x0 + 500
    values = [r["mean_delta_ber"] for r in subset] + [r["low"] for r in subset] + [r["high"] for r in subset]
    lo = min(min(values), 0)
    hi = max(max(values), 0)
    pad = max((hi - lo) * 0.12, 1e-5)
    lo -= pad
    hi += pad
    parts = [
        f"<line x1='{left}' y1='{top}' x2='{left}' y2='{bottom}' stroke='#19383d'/>",
        f"<line x1='{left}' y1='{y_of(0, top, bottom, lo, hi):.1f}' x2='{right}' y2='{y_of(0, top, bottom, lo, hi):.1f}' stroke='#a7b6b3'/>",
        f"<text x='{left-8}' y='{y_of(0, top, bottom, lo, hi)+4:.1f}' font-size='12' text-anchor='end'>0</text>",
    ]
    for i, level in enumerate(LEVELS):
        cx = left + 55 + i * 108
        parts.append(f"<text x='{cx}' y='{bottom+22}' font-size='13' text-anchor='middle'>{level} dB</text>")
        for j, name in enumerate(WIDTHS):
            row = next(r for r in subset if r["name"] == name and r["snr"] == level)
            x = cx + (j - 0.5) * 18
            y = y_of(row["mean_delta_ber"], top, bottom, lo, hi)
            y1 = y_of(row["low"], top, bottom, lo, hi)
            y2 = y_of(row["high"], top, bottom, lo, hi)
            parts.append(f"<line x1='{x}' y1='{y1:.1f}' x2='{x}' y2='{y2:.1f}' stroke='{COLORS[name]}'/>")
            parts.append(f"<circle cx='{x}' cy='{y:.1f}' r='4.5' fill='{COLORS[name]}'/>")
    return parts


def panel_flips(path, x0, y0):
    rows = read_rows(path)
    top, bottom = y0 + 28, y0 + 210
    left = x0 + 56
    peak = max(max(int(r["wrongAtoB"]), int(r["rightAtoB"])) for r in rows)
    peak = max(peak, 1)
    parts = []
    for i, level in enumerate(LEVELS):
        cx = left + 55 + i * 108
        parts.append(f"<text x='{cx}' y='{bottom+22}' font-size='13' text-anchor='middle'>{level} dB</text>")
        for j, name in enumerate(WIDTHS):
            row = next(r for r in rows if r["name"] == name and int(float(r["snr"])) == level)
            x = cx + (j - 0.5) * 18
            up = (bottom - top) * int(row["wrongAtoB"]) / peak
            down = (bottom - top) * int(row["rightAtoB"]) / peak
            mid = (top + bottom) / 2
            parts.append(f"<rect x='{x-6}' y='{mid-up:.1f}' width='12' height='{max(up, 0):.1f}' fill='{COLORS[name]}'/>")
            parts.append(f"<rect x='{x-6}' y='{mid:.1f}' width='12' height='{max(down, 0):.1f}' fill='{COLORS[name]}' opacity='0.45'/>")
    return parts


def panel_rounds(path, x0, y0):
    rows = read_rows(path)
    top, bottom = y0 + 36, y0 + 250
    left = x0 + 48
    parts = []
    metrics = [("localSumDiff", "items", "和差"), ("localBetaDiff", "items", "写回差"), ("idxDiffPorts", "ports", "口序差")]
    for block, (numer, denom, title) in enumerate(metrics):
        bx = left + block * 340
        parts.append(f"<text x='{bx}' y='{y0+16}' font-size='15'>{title}</text>")
        peak = 0.0
        prepared = []
        for row in rows:
            rate = int(row[numer]) / int(row[denom])
            prepared.append((row, rate))
            peak = max(peak, rate)
        peak = max(peak, 1e-6)
        for i, level in enumerate(LEVELS):
            for t in (1, 2, 3):
                cx = bx + 28 + i * 78 + (t - 1) * 16
                if i == 0 and t == 2:
                    parts.append(f"<text x='{cx}' y='{bottom+20}' font-size='12' text-anchor='middle'>{level}</text>")
                elif t == 2:
                    parts.append(f"<text x='{cx}' y='{bottom+20}' font-size='12' text-anchor='middle'>{level}</text>")
                for j, name in enumerate(WIDTHS):
                    rate = next(v for row, v in prepared if row["name"] == name and int(float(row["snr"])) == level and int(row["round"]) == t)
                    h = (bottom - top) * rate / peak
                    x = cx + (j - 0.5) * 6
                    parts.append(f"<rect x='{x-2.5:.1f}' y='{bottom-h:.1f}' width='5' height='{h:.1f}' fill='{COLORS[name]}' opacity='{0.45 + 0.25 * t:.2f}'/>")
    parts.append(f"<text x='{x0}' y='{bottom+42}' font-size='12'>每一档三根柱从左到右是第 1、2、3 轮。和差与写回差的分母是 512×180，口序差的分母是 512×20。</text>")
    return parts


def svg(found, pair_csv, round_csv, out):
    width, height = 1100, 980
    parts = [
        f"<svg xmlns='http://www.w3.org/2000/svg' width='{width}' height='{height}' viewBox='0 0 {width} {height}'>",
        "<title>阻尼舍入 A 与 B 的配对差</title>",
        f"<rect width='{width}' height='{height}' fill='white'/>",
        "<g font-family='Microsoft YaHei, sans-serif' fill='#19383d'>",
        "<text x='32' y='34' font-size='24'>阻尼舍入：B 相对 A 的配对差</text>",
        "<text x='32' y='58' font-size='14'>每个向量的差是（B 错数−A 错数）/24。竖线是 10000 次配对 bootstrap 的 2.5% 到 97.5%，分析种子 271113。实心柱是对变错，浅色柱是错变对。</text>",
        "<text x='32' y='92' font-size='16'>B−A 的平均 ΔBER</text>",
    ]
    parts.extend(panel_delta(found, "B-A", 32, 100))
    parts.append("<text x='560' y='92' font-size='16'>对变错（上）与错变对（下）</text>")
    parts.extend(panel_flips(pair_csv, 560, 100))
    parts.append("<text x='32' y='390' font-size='16'>A 相对 float、B 相对 float 的平均 ΔBER</text>")
    parts.append("<text x='32' y='414' font-size='14'>左为 A−float，右为 B−float。同一分析种子的后续随机流。</text>")
    parts.extend(panel_delta(found, "A-float", 32, 420))
    parts.extend(panel_delta(found, "B-float", 560, 420))
    parts.append("<text x='32' y='700' font-size='16'>同一条 A 轨迹上的局部差，以及完整回放的口序差</text>")
    parts.extend(panel_rounds(round_csv, 32, 710))
    x = 32
    for name in WIDTHS:
        parts.append(f"<rect x='{x}' y='948' width='14' height='14' fill='{COLORS[name]}'/>")
        parts.append(f"<text x='{x+20}' y='960' font-size='13'>{LABELS[name]}</text>")
        x += 140
    parts += ["</g>", "</svg>"]
    out.write_text("<?xml version='1.0' encoding='utf-8'?>\n" + "\n".join(parts) + "\n", encoding="utf-8")


def main():
    run = Path(sys.argv[1])
    rng = random.Random(SEED)
    found = analyze(read_rows(run / "raw" / "per_frame.csv"), rng)
    out = Path("实验档案") / "03_图表" / run.name / "阻尼"
    out.mkdir(parents=True, exist_ok=True)
    write_table(out / "区间.csv", found)
    svg(found, run / "raw" / "配对.csv", run / "raw" / "轮差.csv", out / "配对.svg")
    print(out)


if __name__ == "__main__":
    main()
