# 单次实验协议

冻结于联合采集之前。

先在同一 inputs.mat 上复现 mild。复现之后只把 alpha 改为 S(21,12)、raw 改为 S(21,13)、beta 改为 S(21,14)。其余边保持 mild。

进入网格的条件：mild 为 181/61/5/0 且硬判差 13；联合配置 10 dB 候选错不超过 69/480。未通过则从联合起点每次只把一条边恢复成 mild。
输入：C:/Users/123/Desktop/星地通信1109/01_MIMO/MIMO_工程管理/MIMO_v2_matlab/实验档案/01_运行记录/E0_baseline_s1105_a01_20261109_145449_tpcdb53181_74d4_4723_9e0e_efe47567de32/raw/stitch/inputs.mat
