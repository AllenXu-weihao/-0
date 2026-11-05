# MIMO v2 MATLAB 位宽实验（2026-11-05）

状态：代码已编写并做静态检查；本机无 MATLAB，尚未执行 MATLAB 测试与BER实验。不可当作已验证的HDL黄金。

原始 `MIMO.m` 和 `deployment.mat` 保持不变。`experiments/mimo_instrumented.m` 为原代码的派生插桩版本；原文件SHA256记录在 `experiments/SOURCE_SHA256.txt`。不需要Fixed-Point Designer。建议 MATLAB R2021b 或更新版本，实际兼容性待执行确认。

## 第一次运行

在 MATLAB 切换至本文件夹：

```matlab
addpath(pwd);
addpath(fullfile(pwd,'experiments'));
audit_v2_deployment();
test_experiments();
cases = make_cases(20,1105); % 每SNR 20帧，仅冒烟测试
runs = exp_mvm_A2('A2_out',[24 12;22 12;20 12;20 10],cases);
exp_storage();
```

每个候选独立目录保存到 `experiments/results/`，含 report.md（目的/结果/结论/分析）、inputs.mat、result.mat、per_frame.csv、summary.csv。失败候选保存异常。结果目录默认不进入Git；需要归档时精选报告，不上传全部大轨迹。

## 每份实验控制什么变量

|入口|可选单一量化点|时间阶段|
|---|---|---|
|exp_mvm_A2|A2_x/w/out/product/acc|先验消息|
|exp_mvm_A13|A13_x/w/out/product/acc|证据融合|
|exp_mvm_A5|A5_x/w/out/product/acc|后验|
|exp_sort|alpha|排序前分数|
|exp_statistics|exp/sum_exp/prob/mu/var|软统计|
|exp_likelihood|residual/weighted/mix_a/mix_b/mix_output/lambda/ai|似然|
|exp_feedback|raw/rate/damp_product_old/damp_product_new/damp_sum/beta|反馈|
|exp_frontend|input_y/H/nv/iv、frontend_gram/rhs/center/cov/variance/score/local|前端|
|exp_readout|llr|最终限幅后LLR|
|exp_storage|无量化，按包统计矩阵|存储评估|

例如 `exp_feedback('beta',[24 12;20 12;18 10],cases)` 只量化β写回；不是整个反馈通路同时18位。每次修改同一边界在所有帧与所有轮次的格式。格式矩阵每行为[总位宽W 小数位F]；必须按通路单独设计扫描，不将入口的默认冒烟列表当作推荐格式。rate建议从[18 16]起，weight从[18 14]起，product/acc应使用它们对应的42.26/45.26等起点。

## 数值与实验边界

- 所有量化均为有符号、最近舍入、半值远离零、饱和；复数实虚分别处理。U概率格式尚未实现；本版使用signed候选时要保留足够整数位。
- 未选边界保持double，每次候选完整运行算法；两条原始float/fixed_mvm基线都保留。候选不以fixed_mvm为内部基准，避免隐藏多个同时变化因素。
- product/acc入口采用按列非零项顺序MAC，会同时引入求和顺序变化。应先做足够宽度的顺序MAC对照，再做缩位宽；不能把顺序差异误归因为字长。
- 乘积/累加入口当前是double运算后在指定边界量化的误差模型，并非任意宽度下位精确的整数RTL MAC。没有全FP32逐算术模型、LUT近似或矩阵求解器内部定点实现。
- 非正方差/概率分母会失败并保存报告，不自动加下限修复。候选集合变化自然传播，但本版尚无候选召回/排序翻转专项统计。
- make_cases采用归一化Rayleigh及独立混合噪声，背景SNR=0/10/20/30dB，第二状态总方差=25nv，ε读取pack.config；不代表卫星实际场景。truth只用于评价，不传入检测器。
- 默认80帧只用于跑通；无置信区间和自动通过阈值，不支持性能验收。BLER未接入。可传自建cases扩充场景，每个元素必须包含input、24位truth、snrDB、seed。
- test_experiments先验证两黄金、prepared/raw无量化插桩等价、舍入饱和、简单顺序MAC；任何失败都应先排查，不能修改golden绕过。
- run_quantized支持多个format字段用于后续联合候选，但单边实验入口只启用一个字段；联合实验正式报告流程与统计验收仍需后续完善。

## 版本与上传

仅本目录建立独立Git仓库，不纳入上层LDPC、论文和其他工程。上传步骤见 `GITHUB上传指南.md`。上传代码不代表运行验证完成。
