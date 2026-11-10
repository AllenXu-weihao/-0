# -*- coding: utf-8 -*-
"""Draw the log2 magnitude histograms already stored in result/hist.csv."""
import csv
from collections import defaultdict
from pathlib import Path

root = Path(__file__).resolve().parent
result = root / "result"
for name in ("hist.csv", "range.csv", "snr_peak.csv"):
    path = result / name
    path.write_bytes(path.read_text(encoding="utf-8-sig").encode("utf-8-sig"))
hist = defaultdict(lambda: defaultdict(int))
with (result / "hist.csv").open(encoding="utf-8-sig", newline="") as f:
    for row in csv.DictReader(f):
        hist[row["wire"]][row["log2Floor"]] += int(row["count"])

ranges = {}
with (result / "range.csv").open(encoding="utf-8-sig", newline="") as f:
    for row in csv.DictReader(f):
        ranges[row["wire"]] = row

order = {"片上": 0, "端口": 1, "片外": 2}
wires = sorted(ranges, key=lambda w: (order.get(ranges[w]["role"], 9), w))


def pct_ge(wire, threshold):
    bins = hist[wire]
    total = sum(bins.values())
    if total == 0:
        return 0.0, 0
    ge = 0
    for key, count in bins.items():
        if key in ("under", "over", "zero"):
            continue
        if int(key) >= threshold:
            ge += count
    return 100.0 * ge / total, total


def bars(wire):
    bins = hist[wire]
    numeric = sorted(int(k) for k in bins if k not in ("under", "over", "zero"))
    if not numeric:
        return "", 0
    lo, hi = numeric[0], numeric[-1]
    counts = []
    for k in range(lo, hi + 1):
        counts.append((k, bins.get(str(k), 0)))
    peak = max(c for _, c in counts) or 1
    parts = []
    for k, c in counts:
        height = 0 if c == 0 else max(1, round(120 * c / peak))
        kind = "hot" if k >= 3 else "cool"
        share = 100.0 * c / sum(bins.values())
        parts.append(
            f'<div class="col" title="[2^{k}, 2^{k+1})  {c} 个  {share:.1f}%">'
            f'<div class="bar {kind}" style="height:{height}px"></div>'
            f'<span>{k}</span></div>'
        )
    return "".join(parts), peak


sections = []
current = None
cards = []


def flush():
    if cards:
        sections.append(f'<section><h2>{current}</h2><div class="grid">{"".join(cards)}</div></section>')
        cards.clear()


for wire in wires:
    role = ranges[wire]["role"]
    if role != current:
        flush()
        current = role
    ge8, total = pct_ge(wire, 3)
    body, _ = bars(wire)
    info = ranges[wire]
    zero = hist[wire].get("zero", 0)
    under = hist[wire].get("under", 0)
    over = hist[wire].get("over", 0)
    notes = []
    if zero:
        notes.append(f"零值 {100.0 * zero / total:.1f}%")
    if under:
        notes.append(f"低于 2^-40：{under}")
    if over:
        notes.append(f"高于 2^16：{over}")
    note = " · ".join(notes)
    cards.append(
        f'<article class="card"><header><b>{wire}</b>'
        f'<span>{role} · {total} 个样本 · 峰值 {float(info["peak"]):.4g} · '
        f'含符号整数位 {info["signIntBits"]} · |x|≥8 占 {ge8:.1f}%</span></header>'
        f'<div class="plot">{body}</div>'
        f'<p class="foot">横轴 floor(log2|x|)，柱高按本图最高柱拉满。{note}</p></article>'
    )
flush()

html = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>线级幅度直方图</title>
<style>
  :root {{
    --ink:#1c1b19; --muted:#5e5a54; --line:#ddd8cf; --bg:#f6f5f2; --card:#fff;
    --accent:#1d4e89; --hot:#9b3b32;
  }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 "Segoe UI","PingFang SC","Microsoft YaHei",sans-serif; }}
  main {{ max-width:1180px; margin:0 auto; padding:28px 20px 64px; }}
  h1 {{ font-size:26px; font-weight:600; margin:0 0 8px; }}
  h2 {{ font-size:18px; margin:28px 0 12px; }}
  .muted {{ color:var(--muted); font-size:13px; }}
  .legend {{ display:flex; gap:16px; margin:14px 0 0; font-size:13px; color:var(--muted); }}
  .sw {{ display:inline-block; width:10px; height:10px; margin-right:4px; vertical-align:-1px; }}
  .grid {{ display:grid; grid-template-columns:1fr; gap:14px; }}
  .card {{ background:var(--card); border:1px solid var(--line); padding:12px 14px 8px; }}
  header b {{ display:block; font-size:16px; }}
  header span {{ color:var(--muted); font-size:12px; }}
  .plot {{ display:flex; align-items:flex-end; gap:2px; height:148px; margin-top:10px; overflow-x:auto; border-bottom:1px solid var(--line); }}
  .col {{ display:flex; flex-direction:column; align-items:center; justify-content:flex-end; min-width:18px; height:100%; }}
  .bar {{ width:14px; }}
  .bar.cool {{ background:var(--accent); }}
  .bar.hot {{ background:var(--hot); }}
  .col span {{ color:var(--muted); font-size:10px; line-height:16px; }}
  .foot {{ color:var(--muted); font-size:12px; margin:6px 0 4px; }}
</style>
</head>
<body>
<main>
  <h1>线级幅度直方图</h1>
  <p class="muted">80 帧，种子 1105，双精度，未量化。数据来自 result/hist.csv 与 result/range.csv，2026-11-06。每一柱是半开区间 [2^k, 2^(k+1))，k 标在柱下。纵轴不是统一刻度：每张图的最高柱拉到同一高度，读的是形状和 |x|≥8 的占比。</p>
  <div class="legend"><span><i class="sw" style="background:#1d4e89"></i>|x| &lt; 8</span><span><i class="sw" style="background:#9b3b32"></i>|x| ≥ 8，蓝图 S10.6 的整数部分装不下</span></div>
  {''.join(sections)}
</main>
</body>
</html>
"""
(root / "直方图.html").write_text(html, encoding="utf-8")
print("HTML", root / "直方图.html", "wires", len(wires))
