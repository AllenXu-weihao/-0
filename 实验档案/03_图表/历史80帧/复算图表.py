"""从保存的逐帧计数生成 T0–T5 六段格式拼接的历史回归图。仅使用 Python 标准库。"""

import csv
from pathlib import Path
import xml.etree.ElementTree as ET


HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
SOURCE = PROJECT / "experiments/matlab位宽建模实验2_单计算过程协同压窄/result/拼接/per_frame.csv"
EXPECTED_SNRS = (0, 10, 20, 30)
BITS_PER_VECTOR = 24
GATE_SNR = 10
MAX_NET_NEW_ERRORS = 8


def summarize():
    totals = {}
    with SOURCE.open(encoding="utf-8-sig", newline="") as stream:
        for line, row in enumerate(csv.DictReader(stream), start=2):
            snr = int(row["backgroundSNR"])
            ref = int(row["floatErrors"])
            candidate = int(row["candidateErrors"])
            flips = int(row["disagreements"])
            # wrong_after - corrected = candidate - ref
            # wrong_after + corrected = flips
            twice_added = flips + candidate - ref
            if twice_added % 2:
                raise ValueError(f"第 {line} 行硬判分歧与误码数不自洽")
            added = twice_added // 2
            corrected = flips - added
            both_wrong = ref - corrected
            both_right = BITS_PER_VECTOR - added - corrected - both_wrong
            if min(added, corrected, both_wrong, both_right) < 0:
                raise ValueError(f"第 {line} 行含不可能的配对计数")
            if snr not in totals:
                totals[snr] = dict(background_snr_db=snr, frames=0, bits=0, ref_errors=0,
                                   candidate_errors=0, correct_to_wrong=0, wrong_to_correct=0)
            group = totals[snr]
            group["frames"] += 1
            group["bits"] += BITS_PER_VECTOR
            group["ref_errors"] += ref
            group["candidate_errors"] += candidate
            group["correct_to_wrong"] += added
            group["wrong_to_correct"] += corrected

    if tuple(sorted(totals)) != EXPECTED_SNRS or any(g["frames"] != 20 for g in totals.values()):
        raise ValueError("历史图要求四档背景 SNR、每档 20 帧；请检查输入来源")
    groups = [totals[snr] for snr in EXPECTED_SNRS]
    for group in groups:
        net = group["correct_to_wrong"] - group["wrong_to_correct"]
        group["net_new_errors"] = net
        group["delta_ber_pp"] = round(100 * net / group["bits"], 6)
    return groups


def element(parent, tag, **attrs):
    return ET.SubElement(parent, tag, {k.replace("_", "-"): str(v) for k, v in attrs.items()})


def label(parent, x, y, value, size=16, align="start", color="#19383d", weight=400):
    element(parent, "text", x=x, y=y, font_size=size, text_anchor=align,
            fill=color, font_weight=weight).text = str(value)


def make_figure(groups):
    svg = ET.Element("svg", xmlns="http://www.w3.org/2000/svg", width="1000", height="608",
                     viewBox="0 0 1000 608", role="img", **{"aria-labelledby": "title desc"})
    element(svg, "title", id="title").text = "六段格式拼接的分档误码与配对翻转"
    element(svg, "desc", id="desc").text = (
        "同一批历史样本浮点与拼接方案的逐位配对比较。每档 20 帧、480 比特。"
        "左向条表示浮点错而候选正确的数量，右向条表示浮点正确而候选错的数量。"
        "10 dB 固定回归的门槛为候选比浮点净增不超过 8 个错比特。"
    )
    element(svg, "rect", width=1000, height=608, fill="#ffffff")
    canvas = element(svg, "g", font_family="Microsoft YaHei, Noto Sans CJK SC, sans-serif")
    corrected_color, added_color = "#21766b", "#ac4e28"
    label(canvas, 36, 48, "六段格式拼接后的误码变化", 31, weight=700)
    label(canvas, 37, 81, "历史回归集  ·  同帧比较 float 与六段拼接  ·  种子 1105  ·  每个背景 SNR 含 20 帧 / 480 bit", 17)
    element(canvas, "path", d="M36 100H964", stroke="#b7c9c5")

    label(canvas, 36, 139, "A　同一组比特上，哪些判决发生了变化？", 21, weight=700)
    for x, title in [(75, "SNR (dB)"), (204, "浮点错数"), (319, "拼接错数")]:
        label(canvas, x, 178, title, 16, "middle")
    label(canvas, 604, 178, "← 由错变对", 16, "end", corrected_color, 700)
    label(canvas, 685, 178, "由对变错 →", 16, color=added_color, weight=700)
    label(canvas, 960, 178, "单位：bit", 14, "end")
    baseline = 645
    peak = max(max(g["wrong_to_correct"], g["correct_to_wrong"]) for g in groups)
    scale = 225 / max(peak, 1)
    for i, group in enumerate(groups):
        y = 212 + 42 * i
        element(canvas, "path", d=f"M36 {y+19}H964", stroke="#e0e8e6")
        for x, key in [(75, "background_snr_db"), (204, "ref_errors"), (319, "candidate_errors")]:
            label(canvas, x, y + 6, group[key], 18, "middle")
        for direction, key, color in [(-1, "wrong_to_correct", corrected_color),
                                      (1, "correct_to_wrong", added_color)]:
            value = group[key]
            width = value * scale
            end = baseline + direction * width
            element(canvas, "rect", x=min(end, baseline), y=y - 7, width=width, height=14,
                    fill=color)
            label(canvas, end + direction * 7, y + 6, value, 16,
                  "end" if direction == -1 else "start", color, 700)
    element(canvas, "path", d=f"M{baseline} 192V353", stroke="#8fa5a3")

    label(canvas, 36, 403, "B　10 dB 回归判据：相比浮点，候选最多多错 8 bit", 21, weight=700)
    gate = next(g for g in groups if g["background_snr_db"] == GATE_SNR)
    net = gate["net_new_errors"]
    net_low = min(0, net)
    net_high = max(10, net + 1)
    def xpos(n):
        return 130 + (n - net_low) * 740 / (net_high - net_low)
    element(canvas, "path", d=f"M{xpos(net_low)} 481H{xpos(net_high)}", stroke="#97aba7", stroke_width=2)
    for tick in range(net_low, net_high + 1):
        x = xpos(tick)
        element(canvas, "path", d=f"M{x} 481V489", stroke="#97aba7")
        label(canvas, x, 510, tick, 15, "middle")
    gate_x, net_x = xpos(MAX_NET_NEW_ERRORS), xpos(net)
    element(canvas, "path", d=f"M{gate_x} 445V482", stroke="#566967", stroke_dasharray="4 3", stroke_width=2)
    label(canvas, gate_x, 438, "回归上限 +8", 16, "middle")
    element(canvas, "circle", cx=net_x, cy=481, r=7, fill=added_color)
    label(canvas, net_x, 465, f"实测净增 {net:+d}", 17, "middle", added_color, 700)
    label(canvas, 500, 539, "净新增错比特数（候选 − 浮点）", 16, "middle")
    label(canvas, 36, 573,
          f"10 dB：{gate['correct_to_wrong']} 个由对变错，{gate['wrong_to_correct']} 个由错变对，"
          f"净差 {net:+d}/{gate['bits']}，ΔBER = {gate['delta_ber_pp']:+.2f} 个百分点。", 16)
    label(canvas, 36, 597, "门槛适用于这批固定样本。独立样本的总体性能需另用预留种子和配对置信上界验收。", 15)
    tree = ET.ElementTree(svg)
    ET.indent(tree)
    tree.write(HERE / "分档误码与配对翻转.svg", encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    groups = summarize()
    with (HERE / "分档配对计数.csv").open("w", newline="", encoding="utf-8-sig") as out:
        writer = csv.DictWriter(out, fieldnames=groups[0].keys())
        writer.writeheader()
        writer.writerows(groups)
    make_figure(groups)
