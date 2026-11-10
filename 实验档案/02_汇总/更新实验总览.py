"""从两张登记索引生成 Markdown 总览。运行：python 实验档案/02_汇总/更新实验总览.py"""
import csv
import os
from pathlib import Path
from tempfile import NamedTemporaryFile
from urllib.parse import quote

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent.parent
STAGES = {
    "E0": "复现基线", "E1": "确定范围", "E2": "定位单边敏感度", "E2-M": "比较统一与逐边字长",
    "E3": "联合量化与回退", "E3-H": "比较搜索策略", "E4": "检验独立样本", "E5": "核算真实实现",
}
STATES = ["PLANNED", "RUNNING", "COMPLETE", "PARTIAL", "ERROR"]


def read_rows(filename, key):
    with (HERE / filename).open(encoding="utf-8-sig", newline="") as source:
        rows = list(csv.DictReader(source))
    seen = set()
    for line, row in enumerate(rows, 2):
        identifier = row[key].strip()
        if not identifier or identifier in seen:
            raise ValueError(f"{filename} 第 {line} 行标识为空或重复")
        seen.add(identifier)
    return rows


def cell(value):
    return " ".join(value.splitlines()).replace("|", "&#124;")


def evidence(label, relative):
    if not relative.strip():
        return "待补"
    target = (PROJECT / relative).resolve()
    target.relative_to(PROJECT)
    if not target.is_file():
        raise ValueError(f"索引引用的文件不存在：{relative}")
    path = Path(os.path.relpath(target, HERE)).as_posix()
    return f"[{label}]({quote(path, safe='/._-')})"


def main():
    runs = read_rows("运行索引.csv", "run_id")
    claims = read_rows("结论索引.csv", "claim_id")
    ids = {row["run_id"] for row in runs}
    for row in runs:
        if row["experiment"] not in STAGES or row["execution_status"] not in STATES:
            raise ValueError(f"未知实验或执行状态：{row['run_id']}")
    lines = ["# 实验总览", "", "每行汇总同一问题的运行次数。完成数表示已执行，科学判断见下方结论及其适用范围。"
             "历史 80 帧已另作[回归图例](../03_图表/历史80帧/图源说明.md)，未计作新运行。", "",
             "|阶段|研究问题|待执行|运行中|完成|部分完成|报错|结论条数|", "|---|---|---:|---:|---:|---:|---:|---:|"]
    for stage, question in STAGES.items():
        subset = [row for row in runs if row["experiment"] == stage]
        run_ids = {row["run_id"] for row in subset}
        counts = [sum(row["execution_status"] == state for row in subset) for state in STATES]
        n_claims = sum(bool(set(c["run_id"].split(";")) & run_ids) for c in claims)
        lines.append("|" + "|".join([stage, question, *map(str, counts), str(n_claims)]) + "|")
    lines += ["", "## 结论与依据", ""]
    if not claims:
        lines.append("尚无新运行登记结论。")
    for c in claims:
        refs = set(c["run_id"].split(";"))
        if not refs <= ids:
            raise ValueError(f"{c['claim_id']} 引用了未登记的运行")
        lines += [f"### {cell(c['claim_id'])}　{cell(c['question'])}", "",
                  f"**{cell(c['decision'])}**　{cell(c['result'])}", "",
                  f"比较：{cell(c['comparison'])}。候选：{cell(c['candidate_id'])}。范围：{cell(c['scope'])}。",
                  f"指标：{cell(c['metric'])}。判据：{cell(c['criterion'])}。局限：{cell(c['limitation'])}。",
                  "", f"运行 {cell(c['run_id'])}　"+ " · ".join(evidence(t, c[k]) for t, k in
                     [("数值底表","source_table"), ("主图","figure"), ("报告","report")]), ""]
    lines += ["", "[逐次运行登记](运行索引.csv) · [完整结论索引](结论索引.csv)", ""]
    with NamedTemporaryFile("w", encoding="utf-8", dir=HERE, delete=False) as f:
        f.write("\n".join(lines))
    Path(f.name).replace(HERE / "实验总览.md")


if __name__ == "__main__":
    main()
