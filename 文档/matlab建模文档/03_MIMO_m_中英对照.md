# MIMO.m 中英对照

源文件：[MIMO.m](../../MIMO.m)（286 行，一个文件里的全部局部函数）。  
英文原注释保留；中文是给人看的转义，不改算法。

读法：每节先看「这段在干什么」（白话），再看代码和符号表。`channel` / `ldpc` 分支在本任务包里**不会走到**（入口把 `task` 写死为 `'mimo'`），对照里仍译出来，避免和源码对不上。

---

## 先用一句话说完整份文件

参考模型为四发八收，每个发符号是 64-QAM（6 bit），一帧要解 **24 bit**。穷举是 \(64^4\) 种组合，核里做不起。

这份 `.m` 干的事是：

1. **先砍候选**：每个发符号从 64 点里只留 **9 个**像样的点，并给这 9 个点打一个先验分数。
2. **再猜三次**：用三块学好的稀疏矩阵（A2、A13、A5）和「别人当干扰、自己逐点试」的软抵消，把这 9 个点的分数改三轮。
3. **最后读比特**：看 9 个点上「这一位更像 0 还是更像 1」，吐出 24 个 LLR，负的当 1。

它不是发射机，也不是信道估计器。`H` 当已知量喂进来；发送的真比特**不许**进核，只用来事后对误码。

---

## 0. 文件头在干什么

| English (file header) | 中文 |
|---|---|
| Standalone MATLAB implementation for FPGA translation | 独立 MATLAB，给翻成 FPGA 用，不依赖 common / Python |
| `MIMO()` runs included golden example | 无参数：跑包里的黄金样例 |
| `'float'` = reference | 全浮点参考 |
| `'fixed_mvm'` quantizes array interfaces only | **只**把 A2/A13/A5 的矩阵口收成定点；排序、λ、阻尼仍是浮点 |
| Nonlinear peripherals are algorithm references, not completed HDL or LUT IP | log/exp/混合高斯 **不是**已经做完的查表 IP |

---

## 1. 入口 `MIMO(input, mode)`

### 这段在干什么

这是整份文件的总开关，本身不算数。它只做四件事：**装配置 → 必要时做前端 → 跑三轮核 → 把分数翻成比特**。人直接敲 `MIMO` 不给参数时，它用包里自带的一帧当作业，跑完和黄金答案比一眼，用来证明这个 `.m` 和 `.mat` 配对没坏。

两行模式的意思：

- `'float'`：矩阵乘法用双精度，当算法正确答案。
- `'fixed_mvm'`：只有 A2/A13/A5 三处乘矩阵按定点口收数；排序、对数、阻尼仍是浮点。所以它**不是**「整颗芯片都定点了」，只是阵列口的黄金模型。

`task` 写死 `'mimo'`：这份入口不会去做信道估计，也不会去做 LDPC。下面 `readout` 里那两支是历史内核留下的，读的时候可以当死代码。

### 按行白话

| 代码在干什么 | 白话 |
|---|---|
| 没给 `mode` 就当 `'float'` | 默认用双精度参考 |
| `assert` 只认两个字符串 | 写错模式直接停，防止 silently 跑飞 |
| `p=load_package()` | 打开旁边的 `deployment.mat`：矩阵、缩放、样例、黄金输出都在里面 |
| `nargin==0` → 用 `p.example` | 无输入＝自测；有输入＝真解调 |
| `task='mimo'` | 后面所有分支按 MIMO 走 |
| 没有 `local` 字段就调 `frontend` | 你只给了天线收到的 `y` 和信道 `H`，核还不认识；前端负责变成「每符号 9 个候选 + 先验分数」。若含 `local`，分支会直接跳过前端；预处理输入还须一并提供候选坐标和标签、H、y 及噪声参数 |
| `pkg_vf_infer(..., fixed_passes, mode)` | **真正干活的循环**。`fixed_passes` 本包是 3：同一套更新跑三遍。吐出 `z`＝每一轮、四个符号、各 9 个分数 |
| `result=readout(...)` | 只看最后一轮分数，翻成 24 个 LLR 和硬判比特 |
| `demo` 时和 `expectedFloat/Fixed` 比 | 最大绝对误差要 `<1e-9`。这只证明「这份代码能复现打包时的那一帧」，**不是**字长够不够、误码能不能交卷的停手条件 |

人要看的结果在 `result.llr` / `result.bits`。`audit` 是记账：调了几次矩阵乘、有没有饱和，给定点对照用，解调业务不读它。

```matlab
function [result,audit]=MIMO(input,mode)
if nargin<2,mode='float';end
assert(any(strcmp(mode,{'float','fixed_mvm'})));
p=load_package();
demo=nargin==0;
if demo,input=p.example;end
task='mimo';
if ~isfield(input,'local'),input=frontend(task,input,p);end
[z,audit]=pkg_vf_infer(task,input,p.profile,p.profile.fixed_passes,mode);
result=readout(task,z,input);
if demo
  expected=p.expectedFloat;
  if strcmp(mode,'fixed_mvm'),expected=p.expectedFixed;end
  audit.goldenMaxError=max(abs(z-expected),[],'all');
  assert(audit.goldenMaxError<1e-9);
  fprintf('%s golden PASS, %d iterations, error %g\n', ...
          task,p.profile.fixed_passes,audit.goldenMaxError);
end
end
```

### 符号表（词典，不是正文）

| 符号 | English | 中文 |
|---|---|---|
| `input` | observations / prepared fields | 观测：至少 `y,H,noiseVar,impulseExtraVar`；若已有 `local` 则跳过前端 |
| `mode` | `'float'` or `'fixed_mvm'` | 见上 |
| `p` | pack from `deployment.mat` | 权重、配置、样例、黄金输出 |
| `demo` | no arguments | 自检模式 |
| `z` | trajectory `B × steps × 4 × 9` | 每轮四个符号、各 9 个后验分数 |
| `fixed_passes` | iteration count in profile | 本包是 **3** |
| golden | `max abs error < 1e-9` | 只保证包内样例，不是字长停手 |

一条链：没有 `local` → 前端造候选和先验 → 推断 3 轮 → 后验变为 24 个 LLR，对应 24 个调制比特。

---

## 2. `load_package` / `restore_audit`

### 这段在干什么

权重和配置不写在 `.m` 里，而在同目录 `deployment.mat` 的 `pack` 里。`load_package` 第一次打开后塞进 `persistent`，同一 MATLAB 会话里再调 `MIMO` 不再读盘。人分析时要盯的是 `pack` 里的矩阵尺寸、`fixed_passes=3`、阻尼 `rate=0.3`，不是这几行 load。

`restore_audit` 给旧的全局审计挂钩用。**本入口从不调用**，可以当死函数。

```matlab
function p=load_package()
persistent cached
if isempty(cached)
  s=load(fullfile(fileparts(mfilename('fullpath')),'deployment.mat'),'pack');
  cached=s.pack;
end
p=cached;
end
```

**English:** load `pack` once from the `.mat` next to this `.m`.  
**中文：** 和 `MIMO.m` 同目录的 `deployment.mat`，只读一次缓存在 `persistent` 里。`pack` 里有 `profile, config, example, expectedFloat, expectedFixed`，三张矩阵位于 `profile.matrix`。

`restore_audit` 写全局 `VFINAL_MATRIX_AUDIT`。本入口没用它，是旧内核留下的挂钩。

---

## 3. `frontend` 观测前端（真值进不来）

### 这段在干什么

核不会对 64 点全搜。前端的任务是：**只看收到的 8 个数和 8×4 信道，给每个发符号挑 9 个最像的星座点，并给这 9 个点打分。**

注释里 Observation-only 的意思：发送端真正发了哪 24 bit、真实信道若另有一份「真值」，都**不许**当输入。否则这不是解调器，是作弊器。`H` 是接收机认为已知的信道矩阵，和「标签里的真信道」不是一回事。

具体动作：检查 `y` 正好 8 个复数、噪声方差和脉冲方差合法 → 查 64-QAM 表 → 调候选构造 → 把实部虚部、9 个点、先验、比特标签拆开，排成核喜欢的张量。比特标签来自星座图（这个点 Gray 编码是哪 6 bit），**不是**发送机告诉你的答案；后面读出 LLR 时用来问「这些点里谁代表 bit=0」。

```matlab
y = 8×1 复数拉成行向量
nv = noiseVar      % 热噪声方差，必须有限且 >0
iv = impulseExtraVar
H  = 8×4
[constellation, bitTable] = qam64_table()          % 64 点、每点 6 bit Gray
[~,~,local,idx] = pkg_mimo_candidate_frontend(...) % 每发符号 9 个候选下标
```

写出给核的字段：

| 字段 | 形状 | 中文 |
|---|---|---|
| `yReal,yImag` | 1×8 | 接收实虚部 |
| `noiseVar,impulseVar` | 标量 | 两高斯混合的方差 |
| `candidateReal/Imag` | 1×9×4 | 四个符号各 9 个星座点 |
| `local` | 1×36 | 先验分数（已减最大值） |
| `Hreal,Himag` | 1×8×4 | 信道 |
| `candidateBit` | 1×9×4×6 | 每个候选的 6 个映射比特（给 readout，不是真值） |

---

## 4. `qam64_table` / `stable_logadd`

### 这段在干什么

`qam64_table` 造一张死表：I、Q 各 8 个奇数电平（-7…7），Gray 编码，除以 \(\sqrt{42}\) 让平均功率为 1。核和前端以后只认「第几个点」，点在复平面上哪儿、对应哪 6 bit，都可查这张表。前端选定后连同标签交付候选；工程实现可用 ROM 或组合映射。

`stable_logadd` 是防溢出的 \(\log(e^a+e^b)\)：先减两者较大的那个再指数。**入口从不调用它。** 真正干活的是后面同公式的 `vf_infer__mix`。留着是因为同一文件曾给 LDPC/信道共用。

---

## 5. `readout` 读出

### 这段在干什么

核吐的是「每个符号 9 个点各有一个分数」，人要的是 **24 个比特的软信息**。`readout` 只看**最后一轮**（前两轮轨迹给人画图，硬件不必存）。

对 MIMO：每个符号 6 bit，每个 bit 把 9 个点分成两堆——这一位是 0 的点、是 1 的点。两堆里各取最高分相减，就是这个 bit 的 LLR。参考模型把软值钳到 ±20。LLR 为负判 1。

把不符合该比特的点改成 `-1e6`，就是用一个极小值把它们踢出 max。这是 max-log，不是把 9 个点的指数加起来。

`ldpc` / `channel` 两支：前者当 LDPC 核直接出 38 个 LLR；后者把候选当信道采样做加权平均。**这份入口进不来。**

| `task` | 做什么 |
|---|---|
| `'ldpc'` | 38 个 LLR，负为 1；前 25 个信息比特。本包入口不会进来。 |
| `'channel'` | softmax 后对候选求均值当信道估计。本包不会进来。 |
| **`'mimo'`（实际）** | 对每个符号、每个比特：在「该位为 0 / 为 1」的候选上分别取 max，相减得 LLR；限幅 ±20；拼成 **24** 个数。`bits = llr<0`。 |

`-1e6` 用来把不符合该比特值的候选打到极小，等价于从 9 个点里做 max-log。`candidateBit` 来自星座 ROM，不是发送端真值。

`result.trajectory` 是全程 3 轮分数，**硬件不必存**；只要最后一次后验和 LLR。

---

## 6. `pkg_vf_quantize` 定点舍入

### 这段在干什么

把一个浮点数收成「有符号定点数」：乘 \(2^F\)、四舍五入（一半往远离 0）、超出能表示的范围就钳死并记一次饱和。Inf/NaN 直接报错，作者要求另做 valid 标志，不要用静默 NaN 当状态。

它本身不解调。阵列口和权重都靠它变成整数，好在 MATLAB 里模拟将来的 MAC。

**中文：**

```
q = saturate( round(x * 2^F) )   再 mentally / 2^F
位宽 bits（含符号），小数 F，区间 [-2^{W-1}, 2^{W-1}-1]
```

计饱和次数。非有限数直接 assert。这是阵列口和系数共用的收数函数。

---

## 7. `pkg_vf_fixed_mvm` 阵列口整数乘加

### 这段在干什么

模拟「向量 × 矩阵」这块阵列将来怎么收数：输入 S24.12、权重 S18.14、整数乘加、累加器不超过 53 bit（表上 45 bit）、再右对齐收成输出。用来回答「定点之后和浮点差多少、有没有溢出」，**不是**功耗、也不是完整 RTL（没有时钟、没有握手、矩阵里的零仍按稠密乘）。

**中文：** `y ≈ x * A`，但按规格量化：

| 量 | 格式 |
|---|---|
| 输入 `x` | 默认 24 位、12 小数（S24.12） |
| 权重 `A` | 18 位、14 小数（S18.14） |
| 累加 `xi*wi` | 整数，宽度 `accumulator_bits`（表上 45） |
| 输出 | `acc / 2^26` 再收成 24.12，即右移 14 位小数对齐后再量化 |

`audit` 里有饱和次数、相对纯浮点 `x*A` 的最大误差。**不能拿来当 pJ。**

---

## 8. `pkg_vf_infer` 推断主核（本文件的核心）

### 这段在干什么

这是解调器的肚子。前面已经把每个符号收成 9 个候选；这里做 **3 轮「互相看看、改分数」**。

直观图像：四个发符号彼此在天线里搅在一起。核不敢同时穷举，于是：

1. 先用当前分数，把每个符号收成一个软均值（「我现在觉得你大概在这儿」）和方差（「我有多不确定」）。
2. 对某一根接收天线、某一个自己的候选：把别人用均值扣掉，自己保留 9 种假设，看残差像不像噪声（还要防脉冲噪声）。这叫软干扰抵消。
3. 把这些似然和新的分数送进学好的矩阵，更新「口与口之间的消息」，阻尼一下免得来回抖，再合成四个符号的后验。

矩阵 A2 / A13 / A5 是训练出来的稀疏线性层，不是手工写的校验矩阵。`fixed_mvm` 只把这三处收成定点；中间的排序、指数、对数仍按浮点参考，作者明确说**不能声称已经有完整定点 RTL**。

### 8.1 组、口、长度（为什么不是 8 根天线 × 9）

```matlab
groups = p.runtime.groups     % 5 组接收天线（0 基，+1 变 MATLAB 下标）
mimo 时每组 scope = 1:4       % 四个发射符号都出现
pv = 把各组的 1:4 拼起来      % 长度 P=20
L = 9                         % 每口 9 候选
S = P*L = 180                 % β / α 的平铺长度
```

| English | 中文 |
|---|---|
| `P` ports | 20 个「口」：5 组 × 4 变量，不是 8 根天线 |
| `c` | 4×9，该帧四个符号的候选复数 |
| `beta` | 1×180，消息，第一轮全 0 |
| `steps` | 3 |

`channel` 任务会改 `L=21`、改 `scope`、用 `pilot` 矩阵。入口 `task='mimo'` 时那一整段 `else` **不执行**。

天线顺序：`vf_infer__receiver_order` 把 `H,y` 行重排后再进循环（每帧一次）。

消息不按「8 根天线」排，而按 **5 个接收机组 × 每组都带着 4 个发符号**，所以有 **20 个口**，每口 9 个数，平铺 180。第一轮 `beta` 全 0：还没有邻居消息，只靠前端先验。

`channel` 那套导频、`L=21`，入口进不来。

天线顺序：进循环前按能量和相关性把 `H`、`y` 的行重排一次，让后面的组划分固定。每帧一次。

### 8.2 一轮 `for t=1:steps`（mimo）——白话版流程

每一轮都在回答同一句话：**在别人当前的软猜测下，我这 9 个点谁更像。**

**① A2：把「邻居消息 + 先验」揉成每个口上 9 个新分数 α**  
输入把 180 维 β 和 36 维先验拼成 216。矩阵把它们混一下，吐回 180。每个口减掉自己的最大值，分数变成相对值，避免后面指数爆炸。配置里的 `mimoAlphaScale` 一般是 1，等于没缩放。

**② 排序：分数大的候选排前面**  
每个口 9 个数从高到低排。后面软均值、A13 都在「已排序的名单」上干活，所以星座点 `cs` 也按这个名单重排。硬件上这是比较器网络，不是矩阵。

**③ 收成软符号：均值 μ 和方差**  
把排序后的分数变成概率（softmax；温度默认 1）。9 个点加权平均得到 μ＝「这个口现在猜的复数」；方差＝「猜得散不散」。别人当你的干扰时，用你的 μ 扣你，用你的方差给残差加一点不确定度。

**④ λ：8 根天线 × 4 个符号，做软干扰抵消 + 像不像噪声**

```matlab
residual = y(rx) - H(rx,:)*mu(本组四变量) + H(rx,v)*(mu(q)-cs(q,:))
% 即：用别人的均值抵消，自己保留 9 个候选假设
extra = max(0, 别人方差加权和) * mimoSoftIcVarianceScale
lambda 追加 mix(residual, nv+extra, iv+extra, epsilon)   % 得到 1×9
```

8×4=32 次 mix，每次 9 个数 → **λ 长度 288**。再乘 `mimoLambdaScale`。白话：对「我是这 9 个点之一」分别问天线：扣掉别人之后，残差更像热噪声还是更像脉冲。这是核里最不像矩阵、最像通信公式的一块。

**⑤ 给 A13 准备「排序域摘要」**  
`ai` 几乎等于排好序的 `a`，但第一列改成这 9 个数的 log-sum-exp（「这一口总质量」）。再和 288 维 λ 拼成 468 个数。意思是：矩阵不仅要看见每个候选的似然，还要看见这一口整体有多自信。

**⑥ A13：把似然和摘要再揉回 180 维消息**  
输出仍按排序名单排。必须用 `idx` **反排**回原来的 9 个候选顺序，否则下一轮 A2 会对错点。减最大、乘 `mimoBetaScale`。

**⑦ 阻尼：新消息不要一次换完**  
`β ← 0.7×旧 + 0.3×新`。防止一轮改太猛下一轮抖回来。0.3 不是 2 的幂，上硬件要换成移位凑 1。

**⑧ A5：用当前消息和先验合成四个符号的后验**  
再一次 216→36。这 36 个数就是这一轮对外的答案，写入 `z` 的第 `t` 页。三轮过后，`readout` 只用第 3 页。

三轮共 **9 次**矩阵乘（每轮 A2、A13、A5 各一次）。去掉 MVM 的实现里这 9 次变成等外面算完；完整功能里应改成按非零项乘加，不要按稠密 216×180 报面积。

### 8.3 嵌套 `vf_infer__mv(stage,x)`

这是三处矩阵乘的统一入口：计数、在 `float` 和 `fixed_mvm` 之间切换。人读算法时把它当成 `y = x * A_stage` 即可。

| `mode` | 行为 |
|---|---|
| `'float'` | `y = x * A.(stage)` 稠密乘（很多零） |
| `'fixed_mvm'` | 走 `pkg_vf_fixed_mvm` |

`audit.mvmCalls` 计数。硬件应改成按非零项乘加，数值顺序要另做对照。

---

## 9. `vf_infer__mix` 混合高斯对数似然

### 这段在干什么

天线残差有两种故事：多数时候是普通热噪声（方差 `nv`），偶尔是脉冲（方差 `iv`，权重 `ε`）。函数对每个残差算「这两种故事的对数似然再加起来」。先减峰值再 `log(e^a+e^b)`，防止 exp 下溢。

这就是 1BOX 文里那种「公式对、电路会炸」的函数：硬件要 LUT，不能当已经综合完的算术。

```
a = log(1-ε) - log(π nv) - |r|^2 / nv
b = log(ε)   - log(π iv) - |r|^2 / iv
y = logaddexp(a,b)          % 对 r 的每个候选（9 个数）
```

**中文：** 正常噪声 + 脉冲噪声的似然。和前端 `mixture_log_likelihood_vector` 同一式。该函数属于核外似然服务；若服务端选用 LUT 近似，需验证误码并将其延迟、搬运和功耗计入整链。

---

## 10. `vf_infer__receiver_order` 接收天线重排

### 这段在干什么

按行能量从低到高重排。对 `correlation_groups`，固定最弱天线，枚举余下 7 根中任取两根的组合，挑选“三对归一化相关平方之和 + 加权相对能量”最小的三元组。再从余下五根中选代价最小的二元组，其余三根各占一个单天线槽。以同一排列置换 H 的行与 y 的元素，每帧计算一次，三轮共用。若策略为 `energy`，只按能量重排。

---

## 11. `pkg_mimo_candidate_frontend` Top-9 候选

### 这段在干什么

核约定：**每个发符号永远正好 9 个状态**，矩阵尺寸才锁得住。这个函数负责从 64 点里挑这 9 个。

做法：先做 4×4 LMMSE，得到每个符号一个粗估计和方差——「大概在星座图的哪儿」。64 个点按离这个粗估计的远近打分；再假装去掉这个符号、把残差拿去过混合高斯，看哪个点让天线更像噪声。两份分数加权（残差权重 0.25）后排序，取前 9。然后补比特覆盖（下一节）。同一套前端供全 1 矩阵与学习权重方案复用，避免两条前端对不齐。

硬件上这整块可以放在核外（主机或另一块 IP），和 1BOX 把 QR 放核外是同一类决定。

**中文步骤（每个发射符号 `v`）：**

1. `xhat = (H'H+σI) \ H'y`，4×4 LMMSE。  
2. `scoreLmmse = -|s - xhat_v|² / (2 var_v)`，64 点，减最大。  
3. 去掉符号 `v` 的贡献后，对 64 个星座再算混合高斯残差和，减最大。  
4. `score = LMMSE + 0.25 * residual`（`residualWeight`）。  
5. 降序后取 9 个，再跑比特覆盖：若 9 个点某比特全是 0 或全是 1，且存在分数不太差的反码点，就换掉一个可删点（`coverageGap=2`）。  
6. `localScore` = 留下的 9 个分数再减最大。

输出 `candidateIndex` 是 64 点里的下标。硬件上这整块是 **前端**，与 1BOX 的 QR 一样可以留在核外。

---

## 12. `confidence_gated_bit_coverage`

### 这段在干什么

若挑出的 9 个点在某一 bit 上全是 0（或全是 1），读出时有一组没有真实候选可供取峰，其值由掩码哨兵和限幅共同决定。所以：发现缺反码时，从名单更后面找一个反码点；若它和第一名分差不超过 `coverageGap=2`，就换掉 9 个里「删了对别的 bit 还留得住两边」的那个点。始终保持正好 9 个，再按分数排回去。

**中文：** 防止 9 个候选在某一比特上缺反码，否则 readout 的 max-log 只能填常数。循环最多 6 个比特轮次；换完按分数再排。`keep` 始终长度 9。

---

## 13. 和硅上模块怎么对

前三轮 z 为 MATLAB 轨迹；论文当前采用以下硬件分工。

| MATLAB 步骤 | 反馈控制器对应位置 |
|---|---|
| frontend、候选、接收行重排 | 核外前端，整链计时从原始 y/H 输入开始 |
| A2、A13、A5，均值/方差、mix、logsumexp | 核外服务；请求、返回、有序分数与候选配对及等待由接口规定 |
| 减峰、sort、idx 散回、阻尼 | 核内。浮点以 r≈0.3 更新，定点 307/717 的舍入位置单独登记 |
| readout | 核内末级形成 24 个 LLR。每轮 A5 的 MATLAB 路径与仅末轮 A5 的现有 RTL 分开对拍；范围还取决于输出格式 |

硬件边界及验收以 [11 论文主稿](11_四流64QAM迭代检测器定点化论文梗概.md) 为准。

更短的模块表见 [01_MATLAB代码研读.md](01_MATLAB代码研读.md)；语法与计算过程（与行号一一对应）见 [04_MIMO_m_语法与计算过程.md](04_MIMO_m_语法与计算过程.md)；架构体例见 [02_架构与FPGA_体例提纲.md](02_架构与FPGA_体例提纲.md)。
