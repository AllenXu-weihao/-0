"""E2 单边扫宽。同一 run 的 formats、输入载荷和浮点基线经核对后分 SNR 作图。
从 MIMO_v2_matlab 根目录运行（Python 3.9+，仅标准库）：
  python "实验档案/03_图表/绘制单边扫宽.py" "实验档案/01_运行记录/<run_id>"
默认输出到 实验档案/03_图表/<run_id>/单边扫宽；可用 --out-dir 指定新的输出目录。
manifest.matrix_arithmetic 须写明实际算术。输入文件由 archive_edge_runs 归档。
"""
import argparse
import csv
import hashlib
import json
import math
import sys
import tempfile
from collections import defaultdict
from pathlib import Path
from xml.etree import ElementTree as ET


def require(condition, msg):
    if not condition:
        raise ValueError(msg)


def rows(path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def metadata(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def mat_digest(path):
    """忽略 Level-5 (MATLAB v6/v7) 头部的 116 字节说明/时间，逐字节比较余下内容。"""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        header = stream.read(128)
        require(len(header) == 128, f"输入快照不完整：{path}")
        digest.update(header[116:] if header.startswith(b"MATLAB 5.0 MAT-file") else header)
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def count(value):
    number = int(value)
    require(number >= 0, "出现负数计数")
    return number


def finite(value):
    number = float(value)
    require(math.isfinite(number), "出现非有限数")
    return number


def read_candidate(run, manifest, folder):
    src = metadata(folder / "source.json")
    cid = src["candidate_id"]
    require(cid == folder.name and src["run_id"] == manifest["run_id"], f"来源标识不一致：{cid}")
    require(src["status"] in ("UNVERIFIED", "OK", "COMPLETE") and not src["error"],
            f"{cid} 来源状态为 {src['status']}；请保留错误记录，补齐试验后再比较全组")
    require(src["reference"] == "MIMO(float)", "当前图只接受 MIMO(float) 对照")
    arithmetic = manifest["matrix_arithmetic"]
    require(src.get("matrix_arithmetic", arithmetic) == arithmetic, f"{cid} 矩阵算术不一致")
    require(len(src["formats"]) == 1, f"{cid} 不是单边配置")
    edge, fmt = next(iter(src["formats"].items()))
    width, frac = fmt["W"], fmt["F"]
    require(isinstance(width, int) and isinstance(frac, int) and 0 <= frac < width,
            f"{cid} 的 W/F 无效")
    require(cid == f"{edge}_W{width}_F{frac}", f"{cid} 与归档格式不符")
    raw = (run / src["raw_path"]).resolve()
    require(raw.parent == (run / "raw").resolve() and raw.name == src["original_run_id"],
            f"{cid} 原始归档路径无效")
    input_hash = mat_digest(raw / "inputs.mat")

    keys = {}
    grouped = defaultdict(list)
    def check_identity(row):
        require(row["candidate_id"] == cid and row["run_id"] == manifest["run_id"]
                and int(row["seed"]) == manifest["seed"], f"{cid} 的表与清单不一致")

    for row in rows(folder / "per_frame.csv"):
        check_identity(row)
        snr, frame = finite(row["snr_db"]), count(row["case_index"])
        bits, ref, cand = (count(row[k]) for k in ("n_bits", "reference_errors", "candidate_errors"))
        require(frame > 0 and frame not in keys and bits == 24, f"{cid} 帧重复或分母无效")
        require(max(ref, cand) <= bits, f"{cid} 误码数超出分母")
        bad, good, flips = (count(row[k]) for k in ("became_wrong", "became_correct", "disagreements"))
        require(bad-good == cand-ref and bad+good == flips and good <= ref and bad <= bits-ref,
                f"{cid} 违反配对计数恒等式")
        keys[frame] = (snr, bits, ref)
        grouped[snr].append(row)
    require(keys and set(keys) == set(range(1, len(keys)+1)), f"{cid} 源表帧序号不连续")

    values = {}
    for row in rows(folder / "per_snr.csv"):
        check_identity(row)
        snr = finite(row["snr_db"])
        require(snr in grouped and snr not in values, f"{cid} 汇总分档缺失或重复")
        frames = grouped[snr]
        for k in ("n_bits", "reference_errors", "candidate_errors", "became_wrong",
                  "became_correct", "disagreements"):
            require(count(row[k]) == sum(count(f[k]) for f in frames), f"{cid} 分档 {snr:g} 的 {k} 不符")
        require(count(row["n_frames"]) == len(frames), f"{cid} 帧数不符")
        bits = int(row["n_bits"])
        delta = (int(row["candidate_errors"]) - int(row["reference_errors"])) / bits
        require(math.isclose(finite(row["delta_ber"]), delta, abs_tol=1e-12), f"{cid} ΔBER 不符")
        llrs = [finite(f["llr_max_abs"]) for f in frames if f.get("llr_max_abs", "").strip()]
        require(all(v >= 0 for v in llrs), f"{cid} LLR 绝对差出现负数")
        sats = [count(f["saturations"]) for f in frames if f.get("saturations", "").strip()]
        sat = sum(sats) if len(sats) == len(frames) else None
        if sat is not None and row.get("saturations", "").strip():
            require(sat == count(row["saturations"]), f"{cid} 饱和计数不符")
        values[snr] = dict(run_id=manifest["run_id"], candidate_id=cid, edge=edge, W=width, F=frac,
                           seed=manifest["seed"], reference=src["reference"], snr_db=snr, n_frames=len(frames),
                           n_bits=bits, reference_errors=int(row["reference_errors"]),
                           candidate_errors=int(row["candidate_errors"]), delta_ber_pp=100*delta,
                           llr_max_abs=max(llrs) if len(llrs) == len(frames) else None,
                           saturations=sat, first_idx_change="未采集", matrix_arithmetic=arithmetic,
                           inputs_sha256=input_hash, source_path=f"candidates/{cid}/source.json")
    require(values.keys() == grouped.keys(), f"{cid} 分档表与逐帧表不符")
    return edge, width, frac, input_hash, keys, values


def build_table(run):
    m = metadata(run / "manifest.json")
    require(m["experiment"] == "E2" and isinstance(m.get("matrix_arithmetic"), str)
            and m["matrix_arithmetic"].strip(), "请选 E2 运行并在 manifest 中写明矩阵算术")
    require(m["status"] not in ("ERROR", "PARTIAL"), "运行报告为错误或部分完成；请先核查候选覆盖与错误")
    require(m["run_id"] == run.name, "目录名与 run_id 不符")
    folders = sorted(p for p in (run / "candidates").iterdir() if p.is_dir())
    require(len(folders) >= 2, "至少两档实测单边结果方可比较")
    if m.get("candidate_ids"):
        require(set(m["candidate_ids"]) == {p.name for p in folders}, "预登记候选未全部归档")
    candidates = [read_candidate(run, m, p) for p in folders]
    edge, _, _, digest, frames, _ = candidates[0]
    for other_edge, _, _, other_digest, other_frames, _ in candidates:
        require(edge == other_edge and digest == other_digest and frames == other_frames,
                "候选的边、输入快照、帧键或逐帧浮点基线不一致，停止配对比较")
    formats = [(w, f) for _,w,f,_,_,_ in candidates]
    require(len(set(formats)) == len(formats), "W/F 重复")
    require(len({w-f for w,f in formats}) == 1 or len({f for _,f in formats}) == 1,
            "同时改变整数位和小数位；请先按预定的唯一自变量拆分试验")
    candidates.sort(key=lambda entry: entry[1])
    return [group[snr] for snr in sorted(candidates[0][-1])
            for _, _, _, _, _, group in candidates]


def add(parent, tag, **attrs):
    return ET.SubElement(parent, tag, {k.replace("_", "-"): str(v) for k,v in attrs.items()})


def make_plot(table, dest):
    snrs = sorted({r["snr_db"] for r in table})
    formats = sorted({(r["W"], r["F"]) for r in table})
    width = max(900, len(formats)*96+125)
    metrics = [("delta_ber_pp", "ΔBER（百分点）", "#ae532e"),
               ("llr_max_abs", "相对浮点的最大 |ΔLLR|", "#426d9f"),
               ("saturations", "该边饱和次数", "#267366")]
    panel_w = width-170
    height = 160+len(snrs)*365
    svg = ET.Element("svg", xmlns="http://www.w3.org/2000/svg", width=str(width),
                     height=str(height), viewBox=f"0 0 {width} {height}")
    add(svg,"title").text = "单边扫宽；同种子、同输入、按背景 SNR 配对"
    add(svg,"rect",width=width,height=height,fill="white")
    g = add(svg,"g",font_family="Microsoft YaHei, sans-serif",fill="#19383d")
    def text(x,y,s,size=15,anchor="start"):
        add(g,"text",x=x,y=y,font_size=size,text_anchor=anchor).text=str(s)
    leading=table[0]
    text(32,39,f"{leading['edge']} 单边扫宽 · 相同输入与 MIMO(float) 比较",26)
    text(32,69,f"运行 {leading['run_id']}  ·  种子 {leading['seed']}",14)
    text(32,96,"横轴各档为实际 (W,F)；同一指标在所有 SNR 使用相同纵轴。饱和按次数统计；首次 idx 变化未采集。",15)
    for i,snr in enumerate(snrs):
        records=[r for r in table if r["snr_db"]==snr]
        top=135+i*365
        text(32,top,f"背景 SNR {snr:g} dB   /   每档 {records[0]['n_frames']} 帧，{records[0]['n_bits']} bit",19)
        for j,(key,title,color) in enumerate(metrics):
            y0=top+36+j*99
            all_values=[r[key] for r in table if r[key] is not None]
            lower=min([0]+all_values)
            upper=max([0]+all_values)
            if upper==lower:
                upper=lower+1
            y=lambda val:y0+65-(val-lower)*50/(upper-lower)
            x=lambda idx:125+panel_w*idx/(len(formats)-1)
            text(32,y0,title,15)
            add(g,"path",d=f"M110 {y(0)}H{width-30}",stroke="#a7b6b3")
            for val in (lower,upper):
                text(93,y(val)+4,f"{val:.4g}",13,"end")
            prior=None
            for idx,r in enumerate(records):
                val=r[key]
                if val is None:
                    text(x(idx),y0+38,"缺测",13,"middle")
                    prior=None
                else:
                    px,py=x(idx),y(val)
                    if prior is not None:
                        add(g,"path",d=f"M{prior[0]} {prior[1]}L{px} {py}",stroke=color,fill="none")
                    add(g,"circle",cx=px,cy=py,r=3.7,fill=color)
                    text(px,py-6,f"{val:.4g}",13,"middle")
                    prior=(px,py)
                if j==2:
                    text(x(idx),y0+89,f"({r['W']},{r['F']})",14,"middle")
    text(32,height-20,"各点为已完成回放的描述统计。未采集的量及独立验收结论另见本次运行报告。",15)
    tree=ET.ElementTree(svg)
    ET.indent(tree)
    tree.write(dest,encoding="utf-8",xml_declaration=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run",type=Path)
    parser.add_argument("--out-dir",type=Path)
    args=parser.parse_args()
    run=args.run.resolve()
    out=(args.out_dir or Path(__file__).resolve().parent / run.name / "单边扫宽").resolve()
    require(not out.exists(),"目标已存在，请选择新的输出目录")
    table=build_table(run)
    out.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(dir=out.parent) as temporary:
        build=Path(temporary)/"图表"
        build.mkdir()
        with (build/"单边扫宽.csv").open("w",encoding="utf-8-sig",newline="") as stream:
            writer=csv.DictWriter(stream,fieldnames=table[0].keys())
            writer.writeheader()
            writer.writerows(table)
        make_plot(table,build/"单边扫宽.svg")
        build.rename(out)
    print(f"已写入 {out}")

if __name__=="__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as exc:
        sys.exit(f"无法生成 E2 配对图：{exc}")
