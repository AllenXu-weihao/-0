# MIMO v2 实验档案

从[论文 11 第四、五节](../文档/matlab建模文档/11_四流64QAM迭代检测器定点化论文梗概.md)确定本次要回答的问题、规定图号及判定标准。每个 run 表示按一份预定协议对同一批输入作的一组配对比较；一次扫宽可以包含多个 candidate。历史图版仅作示范，独立验收使用预留数据。

|位置|工作站执行者放什么|
|---|---|
|[00_交接/最新.md](00_交接/最新.md)|上一台机器留下的反思和下一步。开工前先读。做完只改这一份，再上传一次。|
|[00_实验设计](00_实验设计/单次实验协议.md)|协议模板。每次在计算前将具体假设、控制变量、配置、验收标准填入该 run 的 protocol.md。|
|01_运行记录/<run_id>/|本次 protocol.md、manifest.json、raw/ 原始记录、candidates/<candidate_id>/ 标准表及 source.json。只有实跑的配置进入该目录。|
|[02_汇总](02_汇总/运行索引.csv)|运行索引每个 run 一行；[结论索引](02_汇总/结论索引.csv)每项可独立核查的结论一行。给出选中、排除、失败、待定的记录。|
|03_图表/<run_id> 或一个明确的跨 run 对比名/|同名图、作图脚本和图源数据或相对路径。主文用 SVG，另按需要导出 PNG。标注样本、分母、来源 run 和图号。|
|[04_分析报告](04_分析报告/报告模板.md)|使用模板写 <run_id>.md；跨阶段汇总另起报告，列出贡献运行和对应候选。|

## 先建 run，再运行

在工程根目录 `MIMO_v2_matlab` 的 MATLAB 命令窗口执行。第一句为两个示例共同的环境设置。

```matlab
addpath(fullfile(pwd,'实验档案'),fullfile(pwd,'experiments'));
R = new_run('E0','baseline',1105,1);
```

打开 `R.dir/protocol.md` 和 `R.manifest` 填完本次协议；在运行索引登记其路径。记录数据集用途、精确命令、参考与候选、算术及架构版本、脚本修订或驱动文件摘要。启用 JVM 时初始化函数会写入 `deployment.mat` 和 `MIMO.m` 的 SHA-256；关闭 JVM 时以操作系统哈希工具计算后补入。涉及新增/修改驱动或 helper 的运行应固定其提交号或在 raw 下归档源文件及摘要。凡是写进清单、CSV、报告的路径均为相对路径。将清单状态置为 RUNNING 后运行：

```matlab
diary(fullfile(R.raw,'matlab.log'))
run_wire_range(fullfile(R.raw,'wire_range'));
run_stitch_variants(fullfile(R.raw,'stitch'));
diary off
```

E0 在本次 stitch 目录另存 inputs.mat 和 per_frame.csv，每个配置单独按 80 帧汇总，避免将复用同一输入的不同配置重复计入分母。核对 `wire_range/观察.txt`、`range.csv`，以及 `stitch/summary.csv` 的配置与分档计数。只对有原始证据的字段填数；汇总文件无法恢复逐帧分歧时在报告写“未记录”。若脚本报错，执行 `diary off`，保留部分文件，记录错误、状态和复现命令。

第二个示例是 E2 的单边扫宽，单独建立 run 并预登记后运行：

```matlab
R = new_run('E2','alpha',1105,1);
% 先填本次 protocol.md / manifest.json，再运行以下三句。
cases = make_cases(20,1105);
runs = exp_sort('alpha',[21 12; 19 10; 17 8; 15 6],cases);
archive_edge_runs(R,runs);
```

现有 `exp_sort` 为每档创建 `experiments/results/<脚本runID>`。`archive_edge_runs` 把原始目录快照存入本次 `raw/<脚本runID>`，保留 `inputs.mat`、`result.mat` 及原生报告，再为每个成功档产生标准逐帧和分档 CSV。以 `candidates/alpha_W21_F12/source.json` 查到原执行路径、格式与原始状态。同一候选同一源已完整归档时可重复调用；如候选已有另一份结果，应创建新 attempt，在清单 previous_run_id 登记前次运行。工作站同时开展多个 run 时，每个执行者独占自己的 run 文件夹；完成后由汇总人按 run_id 合并索引。

`archive_edge_runs` 适用于 `run_edge_experiment` 的返回结构，它比较候选与 MIMO(float)。原始脚本返回 ERROR 时只归档错误记录；返回 UNVERIFIED 时需另按协议判定。联合配置、预留样本与硬件试验按各自的独立协议运行；现有单边接口仅用于单边诊断。E3-H 起点应加载完整配置再覆盖一条边。E4 的参考与候选须共同使用同一组预留输入，预留集首次查看结果后固定为验收资料。

## 从归档表生成分析

- 回归图的版式与复算方式见[历史 80 帧的分档误码和配对翻转](03_图表/历史80帧/图源说明.md)。沿用图号与列名比较新的数据；图题写本轮实际运行 ID。
- E4 在配置、预留集和规则冻结后执行。以工程根目录为起点运行 `python "实验档案/02_汇总/分析E4.py" "<候选的per_frame.csv路径>"`，保留报告使用的表与原始输入摘要。脚本一次接收一个候选的独立帧表。[E4 统计工具与输入约定](02_汇总/分析E4.py)

## 原始计数与判断

逐帧表和分档表的列见 [per_frame 模板](01_运行记录/per_frame.template.csv) 和 [per_snr 模板](01_运行记录/per_snr.template.csv)。每个候选各存一份，数字使用无量纲比率（例如 0.01）；图若转换成百分数，BER 差使用“百分点”。seed 指生成该批输入的种子，case_index 是 `inputs.mat` 中同一 cases 序列的 MATLAB 索引，从 1 开始；跨种子或工况汇总时同时保留 run_id、seed、case_index 与 snr_db。

|字段|度量与检查|
|---|---|
|n_bits、n_frames|一帧对应一个检测向量和 24 个调制比特；每档 n_bits 和 n_frames 均由保留的输入标识汇总。缺帧/重复帧应核对并披露原因及影响，再判定覆盖是否满足协议。|
|reference_errors、candidate_errors|各自硬判与发送真值不符的位数，输出硬判规则及标签位序在 manifest/protocol 中锁定。|
|became_wrong、became_correct、disagreements|分别为对→错、错→对、两种硬判不一致的位数。二元硬判共享同一真值时，前两者之和为 disagreements，差为 candidate_errors−reference_errors。三列不可从总 BER 净差单独推断。|
|reference_ber、candidate_ber、delta_ber|每档先累加误码数和分母，再分别求 BER；delta_ber 为候选减参考，正值表示误码劣化。各 SNR 独立列示。|
|llr_max_abs、saturations|本帧 24 个 LLR 相对浮点的最大绝对偏差；E2 是该边的饱和次数。其它驱动注明覆盖的边、元素及调用口径。未采集字段留空并注明原因，真实零值填 0。|

登记两个独立状态。manifest 与运行索引的执行状态取 PLANNED、RUNNING、COMPLETE、ERROR 或 PARTIAL；候选结论取“回归通过”“独立验收通过”“不通过”“证据不足”“未评估”。出现执行错误的档位不能进入最佳可行配置评选。补跑产生新的 run_id 与 attempt，在协议中说明变化。每个成功或部分成功的 run 均要在 raw_sources 中列原始相对路径，在 figures 和 report 中列交付文件；将报告与结论索引双向关联。全工程内的通用路径从 MIMO_v2_matlab 根目录起算；清单中以 `raw/`、`candidates/` 开头的路径从该 run 根目录起算。


## 生成阶段主图与跨实验总览

从 MIMO_v2_matlab 根目录执行（路径占位符替换为实际运行）。E2 的运行必须已完成归档。E4 的输入必须来自冻结候选与独立验证集。

```text
python "实验档案/03_图表/绘制单边扫宽.py" "<E2运行目录>"
python "实验档案/02_汇总/分析E4.py" "<E4运行目录>/candidates/<候选>/per_frame.csv" --out-dir "实验档案/03_图表/<E4运行号>"
python "实验档案/02_汇总/更新实验总览.py"
```

每次阶段评审后更新两张 CSV 索引，再刷新[实验总览](02_汇总/实验总览.md)。结论索引的 run_id 可用英文分号连接多个登记编号；source_table、figure、report 填以工程根为起点的单个相对文件路径，其他佐证放报告正文。历史图来自[已归档的 80 帧](03_图表/历史80帧/图源说明.md)。
