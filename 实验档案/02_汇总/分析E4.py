"""E4 固定样本、单配置、分背景 SNR 的配对验收。Python 3.8+，仅用标准库。

从 MIMO_v2_matlab 根目录运行：
  python "实验档案/02_汇总/分析E4.py" "某次E4运行/per_frame.csv"
输出在输入文件旁的新目录 E4_analysis，也可用 --out-dir 指定新目录。
默认按 make_cases(4096,9110527) 的 1 基 cases 序号和 SNR 分块检查输入。
若默认种子已用于开发，在生成验收输入前登记新的未用种子，运行时加
--expected-seed 新种子。更换种子不能用于重复挑选验收结果。
输入应为已独立预留的同帧配对结果。运行前冻结配置、样本、种子及唯一主档；
独立性、配置冻结和是否重复解盲由实验记录审计，单靠 CSV 不能验证。
每档满 4096 帧后一次解盲；样本未齐时只输出进度，不显示效果估计。

Maurer & Pontil (2009), Empirical Bernstein Bounds and Sample Variance
Penalization, Theorem 4, https://arxiv.org/pdf/0907.3740 。
定义 d=(候选错误数−参考错误数)/24∈[-1,1]。把定理用于 (d+1)/2
后变换回原尺度。单侧 U≤8/480 为本版 10 dB 非劣条件。其余档的
上界是逐档 95% 描述，不能解读为同时 95% 置信或全工况非劣。
"""

import argparse
import csv
import hashlib
import math
import statistics
import sys
import tempfile
from collections import defaultdict
from html import escape
from pathlib import Path


SNRS = (0, 10, 20, 30)
TARGET_N = 4096
BITS = 24
MARGIN = 8 / 480
ALPHA = 0.05
REQUIRED = {"run_id", "candidate_id", "seed", "case_index", "snr_db", "n_bits",
            "reference_errors", "candidate_errors"}
FIELDS = ("run_id candidate_id seed source_sha256 snr_db n_frames n_bits reference_errors "
          "candidate_errors became_wrong became_correct reference_ber candidate_ber "
          "delta_ber upper95_delta_ber decision_margin decision").split()


def nonnegative(value):
    v = int(value)
    if v < 0:
        raise ValueError("计数或编号为负数")
    return v


def flips(row, ref, cand):
    """方向明细可缺省。给定二分类判决分歧总数时，可用净差还原两方向。"""
    wrong, correct, diff = (row.get(k, "") for k in
                            ("became_wrong", "became_correct", "disagreements"))
    diff = nonnegative(diff) if diff else None
    if bool(wrong) != bool(correct):
        raise ValueError("两个方向的翻转数需成对填写")
    if wrong:
        wrong, correct = nonnegative(wrong), nonnegative(correct)
    elif diff is not None:
        if (diff + cand - ref) % 2:
            raise ValueError("判决分歧数与错误数净差的奇偶性不一致")
        wrong = (diff + cand - ref) // 2
        correct = diff - wrong
    else:
        return None
    if not (0 <= wrong <= BITS - ref and 0 <= correct <= ref):
        raise ValueError("翻转数超出二分类配对表可行范围")
    if wrong - correct != cand - ref or (diff is not None and wrong + correct != diff):
        raise ValueError("翻转数与净差或判决分歧数不一致")
    return wrong, correct


def load_frames(path, expected_seed):
    by_snr = defaultdict(list)
    keys = set()
    identity = None
    with path.open(encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        names = reader.fieldnames or []
        if not REQUIRED.issubset(names) or len(set(names)) != len(names):
            raise ValueError("缺列或重复表头。必需字段：" + ", ".join(sorted(REQUIRED)))
        for row in reader:
            try:
                if None in row or any(row[k] is None for k in REQUIRED):
                    raise ValueError("行列数与表头不符")
                run, candidate = row["run_id"].strip(), row["candidate_id"].strip()
                if not run or not candidate:
                    raise ValueError("运行或配置 ID 为空")
                if identity is None:
                    identity = run, candidate
                elif identity != (run, candidate):
                    raise ValueError("同一文件混入多个运行或候选配置")
                seed, case = nonnegative(row["seed"]), nonnegative(row["case_index"])
                key = seed, case
                if not case or key in keys:
                    raise ValueError(f"case_index 应从 1 起，且 (seed,case_index) 须唯一：{key}")
                keys.add(key)
                snr = float(row["snr_db"])
                if snr not in SNRS or nonnegative(row["n_bits"]) != BITS:
                    raise ValueError("预设 SNR 为 0/10/20/30 dB，每检测向量 24 bit")
                if seed != expected_seed:
                    raise ValueError(f"与登记的独立验收种子 {expected_seed} 不符")
                offset = SNRS.index(int(snr)) * TARGET_N
                if not offset < case <= offset + TARGET_N:
                    raise ValueError("case_index 与 make_cases 的背景 SNR 分块不符")
                ref, cand = (nonnegative(row[k]) for k in ("reference_errors", "candidate_errors"))
                if max(ref, cand) > BITS:
                    raise ValueError("误码数超过每帧 24 bit")
                by_snr[int(snr)].append((ref, cand, flips(row, ref, cand)))
                if len(by_snr[int(snr)]) > TARGET_N:
                    raise ValueError("超过预先固定的分档样本量，请检查登记协议和输入文件")
            except (TypeError, ValueError) as err:
                raise ValueError(f"CSV 第 {reader.line_num} 行：{err}") from err
    if identity is None:
        raise ValueError("输入仅含表头或为空；需要逐帧记录")
    return identity, by_snr


def summarize(identity, by_snr, digest, seed):
    complete = all(len(by_snr[s]) == TARGET_N for s in SNRS)
    records = []
    for s in SNRS:
        frames = by_snr[s]
        n = len(frames)
        r = dict(run_id=identity[0], candidate_id=identity[1], seed=seed, source_sha256=digest,
                 snr_db=s, n_frames=n, n_bits=n * BITS,
                 decision_margin=MARGIN if s == 10 else "", decision="样本未齐")
        if complete:
            ref = sum(f[0] for f in frames)
            cand = sum(f[1] for f in frames)
            ds = [(f[1] - f[0]) / BITS for f in frames]
            mean = statistics.mean(ds)
            logterm = math.log(2 / ALPHA)
            upper = min(1.0, mean + math.sqrt(2 * statistics.variance(ds) * logterm / n)
                        + 14 * logterm / (3 * (n - 1)))
            decision = "描述性工作点"
            if s == 10:
                decision = "主档非劣通过" if upper <= MARGIN else "未证实主档非劣"
            r.update(reference_errors=ref, candidate_errors=cand,
                     reference_ber=ref/(n*BITS), candidate_ber=cand/(n*BITS),
                     delta_ber=mean, upper95_delta_ber=upper, decision=decision)
            if all(f[2] is not None for f in frames):
                r.update(became_wrong=sum(f[2][0] for f in frames),
                         became_correct=sum(f[2][1] for f in frames))
        records.append(r)
    return records, complete


def forest(records, complete):
    width, height = 1220, 540
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" '
             'role="img" aria-labelledby="title desc"><title id="title">E4 分档配对非劣验收</title>'
             '<desc id="desc">点为候选减参考的误码率差，右端为逐档单侧 95% 上界。'
             '10 dB 是唯一预设判定档。</desc><style>text{font-family:"Microsoft YaHei",'
             '"Noto Sans CJK SC",sans-serif;fill:#203b44}</style>'
             '<rect width="100%" height="100%" fill="white"/>']
    def label(x, y, text, size=17, anchor="start"):
        parts.append(f'<text x="{x}" y="{y}" text-anchor="{anchor}" font-size="{size}">'
                     f'{escape(str(text))}</text>')
    def line(x1, y1, x2, y2, color="#9aa9aa", thickness=1):
        parts.append(f'<line x1="{x1:.2f}" y1="{y1}" x2="{x2:.2f}" y2="{y2}" '
                     f'stroke="{color}" stroke-width="{thickness}"/>')
    label(35, 52, "E4　按背景 SNR 比较候选与浮点参考", 32)
    label(35, 88, "独立检测向量成对分析　｜　差值 = 候选 BER − 浮点 BER　｜　单位：百分点", 18)
    if complete:
        label(35, 124, "● 观察差值　　┤ 单侧 95% 上界　　橙线：10 dB 非劣界 +1.667 个百分点")
    else:
        label(35, 124, "未到预登记的固定样本终点，以下仅显示累计样本数。")
    label(35, 175, "SNR")
    label(112, 175, "独立向量")
    label(880, 175, "差值 / 上界")
    label(1060, 175, "判定")
    if complete:
        values = [100*r[k] for r in records for k in ("delta_ber", "upper95_delta_ber")]
        lo, hi = min(0, *values), max(100*MARGIN, *values)
        pad = (hi-lo)*0.08
        lo, hi = lo-pad, hi+pad
        def xpos(v):
            return 246 + (v-lo)*560/(hi-lo)
        for v in (0, 100*MARGIN):
            label(xpos(v), 450 if v == 0 else 474, f"{v:+.3f}", 15, "middle")
        line(xpos(0), 190, xpos(0), 416)
    for i, r in enumerate(records):
        y = 217 + 60*i
        label(35, y+5, f"{r['snr_db']} dB")
        label(112, y+5, f"{r['n_frames']} / {TARGET_N}")
        if complete:
            delta, upper = r["delta_ber"]*100, r["upper95_delta_ber"]*100
            if r["snr_db"] == 10:
                x = xpos(MARGIN*100)
                line(x,y-20,x,y+20,"#ca6917",3)
            x, u = xpos(delta), xpos(upper)
            line(x,y,u,y,"#136b72",4)
            line(u,y-8,u,y+8,"#136b72",3)
            parts.append(f'<circle cx="{x:.2f}" cy="{y}" r="5.8" fill="#136b72"/>')
            label(880, y+5, f"{delta:+.3f} / {upper:+.3f}")
        label(1060, y+5, r["decision"])
    label(35, 518, "分档精确计数、输入摘要与未四舍五入的界见同目录 CSV。其余三个 SNR 仅供诊断。", 16)
    return "".join(parts) + "</svg>"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("per_frame", type=Path)
    parser.add_argument("--out-dir", type=Path)
    parser.add_argument("--expected-seed", type=int, default=9110527,
                        help="运行前预登记的验收种子（默认 9110527）")
    args = parser.parse_args()
    out = args.out_dir or args.per_frame.parent / "E4_analysis"
    try:
        if out.exists():
            raise ValueError(f"输出目录已存在：{out}。请选择新的 --out-dir。")
        if not 0 <= args.expected_seed < 2**32 or args.expected_seed == 1105:
            raise ValueError("验收种子须在 MATLAB rng 的整数范围内，且不能为历史回归种子 1105")
        digest = hashlib.sha256(args.per_frame.read_bytes()).hexdigest()
        identity, by_snr = load_frames(args.per_frame, args.expected_seed)
        if hashlib.sha256(args.per_frame.read_bytes()).hexdigest() != digest:
            raise ValueError("输入文件在读取期间已变化")
        rows, complete = summarize(identity, by_snr, digest, args.expected_seed)
        out.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=out.parent) as stage:
            directory = Path(stage) / "report"
            directory.mkdir()
            with (directory/"分档配对验收.csv").open("w", encoding="utf-8-sig", newline="") as f:
                writer = csv.DictWriter(f, fieldnames=FIELDS)
                writer.writeheader()
                writer.writerows(rows)
            (directory/"分档配对验收.svg").write_text(forest(rows, complete), encoding="utf-8")
            directory.rename(out)
        print(f"{out}：{rows[1]['decision']}。")
    except (OSError, ValueError) as err:
        sys.exit(str(err))


if __name__ == "__main__":
    main()
