# MIMO.m 语法说明 × 计算过程（与源码一一对应）

源文件：[MIMO.m](../../MIMO.m)，行号与该文件一致。  
白话「做什么」见 [03_MIMO_m_中英对照.md](03_MIMO_m_中英对照.md)。本文只讲：**这一行 MATLAB 怎么读、这一行算了什么。**

通例：

- `%` 到行末是注释，不执行。
- 一行里逗号 `,` 是语句分隔（和分号 `;` 一样断开语句；分号还抑制命令窗打印）。
- `end` 结束 `function` / `if` / `for`。
- `'` 是共轭转置；`.'` 是不共轭转置。第 27、31 行的 y 仅换行列方向，用不共轭转置；第 197–198 行的 LMMSE 法方程使用 H 的共轭转置。
- `A(i,:)` 第 i 行；`A(:,j)` 第 j 列；`(:)` 按列拉成一列。
- `max(X,[],2)` 沿第 2 维（每行）；`max(...,[],'all')` 全体一个数。空的 `[]` 是 MATLAB 指定「沿哪一维」的占位。

源码每轮调用 A5，现有控制器只在末轮请求 A5。部署范围与验证计划见[11 论文主稿](11_四流64QAM迭代检测器定点化论文梗概.md)。

本包实际路径：`task='mimo'`，`steps=3`，`P=20`，`L=9`。标了「本包不走」的分支仍按语法译出。

---

## 行 1–13 入口 `MIMO`

```matlab
function [result,audit]=MIMO(input,mode)
% ... 文件头注释 ...
if nargin<2,mode='float';end
assert(any(strcmp(mode,{'float','fixed_mvm'})));
p=load_package();demo=nargin==0;if demo,input=p.example;end
task='mimo';
if ~isfield(input,'local'),input=frontend(task,input,p);end
[z,audit]=pkg_vf_infer(task,input,p.profile,p.profile.fixed_passes,mode);result=readout(task,z,input);
if demo,expected=p.expectedFloat;if strcmp(mode,'fixed_mvm'),expected=p.expectedFixed;end;audit.goldenMaxError=max(abs(z-expected),[],'all');assert(audit.goldenMaxError<1e-9);fprintf('%s golden PASS, %d iterations, error %g\n',task,p.profile.fixed_passes,audit.goldenMaxError);end
end
```

| 行 | 代码 | 语法 | 计算过程 |
|---|---|---|---|
| 1 | `function [result,audit]=MIMO(input,mode)` | 函数定义。方括号是**多个返回值**；圆括号是输入。同文件后面的 `function` 是局部函数，只给本文件调用。 | 定义入口。调用方写 `[r,a]=MIMO(in)` 或 `MIMO()`。 |
| 2–5 | `% ...` | 注释。第一行 `% MIMO ...` 会出现在 `help MIMO` 里。 | 不计算。声明：独立文件、两种 mode、非线性不是 HDL。 |
| 6 | `if nargin<2,mode='float';end` | `nargin`＝实际传入参数个数。逗号把 `if` 条件、赋值、`end` 挤在一行。 | 只传了 `input`、或什么都不传时，模式默认双精度参考。 |
| 7 | `assert(any(strcmp(mode,{'float','fixed_mvm'})));` | `strcmp` 对元胞里每个字符串比较，得到逻辑向量；`any` 有一个真就真；`assert` 假则报错停。 | 模式必须是这两个之一，否则后面定点/浮点分支无定义。 |
| 8 | `p=load_package();` | 调用局部函数，返回值赋给 `p`。 | 读 `deployment.mat` 的 `pack`：矩阵、配置、样例、黄金。 |
| 8 | `demo=nargin==0;` | `==` 得到逻辑标量，赋给 `demo`。 | 一个参数都没给 → 自测模式为真。 |
| 8 | `if demo,input=p.example;end` | 条件赋值。 | 自测时作业改成包里那一帧观测。 |
| 9 | `task='mimo';` | 字符行向量（单引号）。 | 后面所有 `strcmp(task,...)` 走 MIMO 支。不会进 channel/ldpc。 |
| 10 | `if ~isfield(input,'local'),input=frontend(...);end` | `isfield` 问结构体有没有这个字段；`~` 取反。 | 没有先验字段 → 先做前端，用返回的结构体**覆盖** `input`。有 `local` 则认为候选已备好。 |
| 11 | `[z,audit]=pkg_vf_infer(task,input,p.profile,p.profile.fixed_passes,mode);` | 点号 `p.profile` 取结构体字段。`fixed_passes` 当迭代次数传入。 | **主计算**：3 轮推断。`z` 形状 `B×3×4×9`（批 × 轮 × 4 符号 × 9 候选分数）。`audit` 记矩阵调用和饱和。 |
| 11 | `result=readout(task,z,input);` | 同一行第二条语句。 | 用最后一轮分数算 24 个 LLR 和硬判比特。 |
| 12 | `if demo, expected=...` | 一行里套了内层 `if`。 | 仅自测：按 mode 选 `expectedFloat` 或 `expectedFixed`。 |
| 12 | `audit.goldenMaxError=max(abs(z-expected),[],'all');` | `abs` 逐元素；`[]` 占位；`'all'` 全张量一个最大值。给结构体**加字段**。 | 轨迹与黄金的最大绝对误差。 |
| 12 | `assert(...<1e-9);` | 比较后断言。 | 超过 1e-9 视为包损坏。不是误码停手。 |
| 12 | `fprintf('%s ... %d ... %g\n', ...)` | C 风格打印。`%s` 字符串，`%d` 整数，`%g` 自动格式浮点。`\n` 换行。 | 打印任务名、迭代次数、误差。 |
| 13 | `end` | 结束 `function MIMO`。 | — |

---

## 行 15–19 `load_package`

| 行 | 代码 | 语法 | 计算过程 |
|---|---|---|---|
| 15 | `function p=load_package()` | 无输入、一个输出。 | — |
| 16 | `persistent cached` | 函数再次进入时变量还在，类似静态局部量。 | 第一次 `cached` 是 `[]`。 |
| 17 | `if isempty(cached), s=load(...'pack'); cached=s.pack; end` | `fileparts(mfilename('fullpath'))`＝本 `.m` 所在目录。`fullfile` 拼路径。`load(...,'pack')` 只读 MAT 里名为 `pack` 的变量，得到结构体 `s`，字段 `s.pack`。 | 第一次从盘读包并缓存；之后直接用内存。 |
| 18 | `p=cached;` | 赋值。 | 返回包。 |

---

## 行 20–23 `restore_audit`

| 行 | 代码 | 语法 | 计算过程 |
|---|---|---|---|
| 21 | `global VFINAL_MATRIX_AUDIT` | 声明工作区全局量。 | 入口从不调用本函数。 |
| 22 | `VFINAL_MATRIX_AUDIT=previous;` | 写全局。 | 恢复审计挂钩。 |

---

## 行 25–35 `frontend`

```matlab
function d=frontend(task,input,p)
y=double(input.y(:).');assert(numel(y)==8);nv=double(input.noiseVar);iv=double(input.impulseExtraVar);
assert(isscalar(nv)&&isscalar(iv)&&isfinite(nv)&&isfinite(iv)&&nv>0&&iv>0);
d=struct('yReal',real(y),'yImag',imag(y),'noiseVar',nv,'impulseVar',iv);
 H=double(input.H);assert(isequal(size(H),[8 4]));[constellation,bitTable]=qam64_table();
 [~,~,local,idx]=pkg_mimo_candidate_frontend(y.',H,nv,iv,constellation,bitTable,p.config);
 c=constellation(idx);d.candidateReal=reshape(real(c),1,9,4);d.candidateImag=reshape(imag(c),1,9,4);
 d.local=reshape(local,1,[]);d.Hreal=reshape(real(H),1,8,4);d.Himag=reshape(imag(H),1,8,4);
 cb=zeros(1,9,4,6);for v=1:4,cb(1,:,v,:)=reshape(bitTable(idx(:,v),:),1,9,1,6);end;d.candidateBit=cb;
end
```

| 行 | 代码 | 语法 | 计算过程 |
|---|---|---|---|
| 25 | `function d=frontend(task,input,p)` | `task` 传入但本函数体不用（历史接口）。 | 输出结构体 `d` 给核。 |
| 27 | `y=double(input.y(:).');` | `(:)` 拉成列；`.'` 再转成**行**；`double` 转双精度。 | `y` 变成 `1×8` 复数行向量。 |
| 27 | `assert(numel(y)==8);` | `numel`＝元素个数。 | 不是 8 根接收就停。 |
| 27 | `nv=double(input.noiseVar); iv=...` | 字段转双精度。 | 热噪声方差、脉冲方差。 |
| 28 | `assert(isscalar(...)&&...);` | `&&` 短路与：左边假则右边不算。`isfinite` 排除 Inf/NaN。 | 两个方差必须是有限正标量。 |
| 29 | `d=struct('yReal',real(y),...)` | `struct` 按「字段名,值」成对构造。`real`/`imag` 取实虚部。 | 核后面用实虚部分开的数组（方便定点），此处先拆开。`impulseVar` 字段名与输入 `impulseExtraVar` 不同。 |
| 30 | `H=double(input.H); assert(isequal(size(H),[8 4]));` | `size` 返回 `[行 列]`；`isequal` 比形状。行前空格无意义。 | `H` 必须 8 收 × 4 发。 |
| 30 | `[constellation,bitTable]=qam64_table();` | 双输出。 | `c`：64×1 复数星座；`b`：64×6 Gray 比特。 |
| 31 | `[~,~,local,idx]=pkg_mimo_candidate_frontend(...)` | `~` 丢弃该输出。四个输出里只要第 3、4 个。`y.'` 把行变回列，匹配该函数约定。 | **主计算**：每发符号 9 个候选。`local` 为 9×4 先验分数（已减最大）；`idx` 为 9×4 下标，取值 1…64。 |
| 32 | `c=constellation(idx);` | 用整数矩阵当下标，得到与 `idx` 同形状的复数。 | `c` 是 9×4 个候选星座点（不是 64 全表）。 |
| 32 | `d.candidateReal=reshape(real(c),1,9,4);` | `reshape` 按列优先重排成 1×9×4。 | 给核的候选实部。虚部同样。批维先占成 1。 |
| 33 | `d.local=reshape(local,1,[]);` | `[]` 让 MATLAB 自己算那一维：9×4 → 1×36。 | 先验平铺，以后和 180 维消息拼接。 |
| 33 | `d.Hreal=reshape(real(H),1,8,4);` | 8×4 → 1×8×4。 | 信道实虚部分开。 |
| 34 | `cb=zeros(1,9,4,6);` | 全零四维数组。 | 预放每个候选的 6 个比特。 |
| 34 | `for v=1:4, cb(1,:,v,:)=reshape(bitTable(idx(:,v),:),1,9,1,6); end` | `idx(:,v)` 是符号 v 的 9 个下标；`bitTable(那些行,:)` 是 9×6；reshape 成 1×9×1×6 才能赋进 `cb` 的切片。 | 第 v 个符号 9 个点的 Gray 比特写入 `cb`。 |
| 34 | `d.candidateBit=cb;` | 赋值。 | 给 `readout` 用，不是发送真值。 |

---

## 行 36–38 `stable_logadd`

| 行 | 代码 | 语法 | 计算过程 |
|---|---|---|---|
| 37 | `m=max(a,b);` | 二元 `max`：逐元素取较大。 | 峰值。 |
| 37 | `value=m+log(exp(a-m)+exp(b-m));` | 算术逐元素。`log`/`exp` 默认自然对数。 | \(\log(e^a+e^b)\)。先减 `m`，`exp(0)` 与 `exp(负数)` 不会溢出。**本入口不调用。** |

---

## 行 39–42 `qam64_table`

| 行 | 代码 | 语法 | 计算过程 |
|---|---|---|---|
| 40 | `level=-7:2:7;` | `start:step:end` 等差。 | I/Q 电平：-7,-5,…,7，共 8 个。 |
| 40 | `gray=bitxor(0:7,floor((0:7)/2));` | `0:7` 为 0…7；`floor` 向负无穷取整；`bitxor` 按位异或。这是二进制转 Gray：`n xor n>>1`。 | 8 个电平的 Gray 码 0…7。 |
| 40 | `c=zeros(64,1); b=zeros(64,6); q=0;` | 预分配。 | 64 个点、每点 6 bit。 |
| 41 | `for i=1:8, for r=1:8, ... end, end` | 双层循环挤在一行。`,` 也结束内层 `end`。 | 外层 I（`i`），内层 Q（`r`）。 |
| 41 | `q=q+1;` | 点序号 1…64。 | — |
| 41 | `c(q)=(level(i)+1i*level(r))/sqrt(42);` | `1i` 是虚数单位。 | 点 \( (I+jQ)/\sqrt{42} \)，平均功率 1。 |
| 41 | `b(q,1:3)=bitget(gray(i),3:-1:1);` | `bitget(x,k)` 取第 k 比特（1＝最低位）。`3:-1:1` 从高到低 3 bit。 | I 的 3 个 Gray 比特。Q 同理放 4:6。 |

---

## 行 43–56 `readout`

| 行 | 代码 | 语法 | 计算过程 |
|---|---|---|---|
| 44 | `result=struct('trajectory',z,'actualIterations',size(z,2));` | `size(z,2)` 第 2 维长度＝轮数。 | 先放下全程分数和实际迭代次数。 |
| 45 | `if strcmp(task,'ldpc'), ... return; end` | `return` 立刻离开函数。 | **本包不走。** 把最后一轮看成 38 个 LLR，负为 1，前 25 个信息位。 |
| 46 | `B=size(z,1); L=size(z,4); last=reshape(z(:,end,:,:),B,4,L);` | `end` 在下标里＝该维最后。`:` 取整维。 | `B` 批大小；`L` 候选数（MIMO＝9）。`last`＝最后一轮，`B×4×9`。 |
| 47–49 | `if strcmp(task,'channel')` | 分支。 | **本包不走。** `prob`＝沿候选维 softmax；对候选复数加权和当信道估计。`permute` 调维顺序好广播相乘。 |
| 51 | `assert(isfield(d,'candidateBit'),'...');` | 断言失败时显示后面字符串。 | MIMO 必须有比特标签才能算 LLR。 |
| 52 | `cb=permute(d.candidateBit,[1 3 2 4]);` | 原维顺序 1,2,3,4 → 新顺序第1,第3,第2,第4 维。 | `B×9×4×6` → `B×4×9×6`，与 `last` 的 `B×4×9` 对齐。 |
| 52 | `llr=zeros(B,4,6);` | 预分配。 | 4 符号 × 6 bit。 |
| 53 | `for bit=1:6` | 循环 6 个比特。 | — |
| 53 | `a=last; b=last;` | 复制两份后验。注意此处 `b` 不是批大小 `B`。 | 准备 0 堆 / 1 堆。 |
| 53 | `a(cb(:,:,:,bit)~=0)=-1e6;` | 逻辑下标：该 bit 不是 0 的位置写成 -1e6。`~= ` 不等于。 | 0 堆里把「bit=1 的点」打到极小，后面 `max` 等于只看 bit=0 的点。 |
| 53 | `b(cb(:,:,:,bit)==0)=-1e6;` | 1 堆里踢掉 bit=0 的点。 | — |
| 53 | `llr(:,:,bit)=max(a,[],3)-max(b,[],3);` | 沿候选维（第 3 维）取最大再相减。 | max-log LLR：\(\max_{s:b=0} z - \max_{s:b=1} z\)。 |
| 54 | `max(-20,min(20,llr))` | 逐元素钳位。先 `min(20,·)` 再 `max(-20,·)`。 | 限幅 ±20。 |
| 54 | `permute(...,[1 3 2])` 再 `reshape(...,B,24)` | 维顺序变成 批 × bit × 符号，再拉成 批 × 24。 | 符号 1 的 6 bit、符号 2 的 6 bit…… |
| 54 | `result.bits=result.llr<0;` | 比较得到逻辑数组。 | LLR 取“0 组最高分减 1 组最高分”；负值判 1，零值判 0。 |

---

## 行 59–73 `pkg_vf_fixed_mvm`

| 行 | 代码 | 语法 | 计算过程 |
|---|---|---|---|
| 62 | `assert(size(x,2)==size(A,1));` | 矩阵乘内维相等。 | `x` 是 1×N 或 B×N，`A` 是 N×M。 |
| 62 | `assert(width.accumulator_bits<=53);` | 双精度整数精确范围大约 53 bit。 | 超出则 MATLAB 整数不可比硬件。 |
| 63–64 | `inputBits=24; if isfield(...), ... end` | 有字段就覆盖默认。输出位宽默认等于输入。 | 缺省 S24；权重下面写死 18。 |
| 65 | `[xi,ins]=pkg_vf_quantize(x,inputBits,12);` | 24 位、12 小数。 | \( x_i = \mathrm{sat}(\mathrm{round}(x\cdot 2^{12})) \)，整数。 |
| 65 | `[wi,ws]=pkg_vf_quantize(A,18,14);` | 18 位、14 小数。 | 权重整数。 |
| 66 | `acc=xi*wi;` | MATLAB `*` 是矩阵乘。两边已是整数，乘积仍双精度里的整数。 | 整数 MAC。 |
| 67 | `assert(all(acc(:)>=-2^(W-1) & acc(:)<2^(W-1)),'...');` | `all` 全部真；`&` 逐元素与（两边都算）。上界是**开区间** `< 2^{W-1}`。 | 检查本次列末结果是否位于所配有符号范围；逐项部分和峰值另由有序 MAC 观察。 |
| 68 | `pkg_vf_quantize(acc/2^26, outputBits, 12)` | `/2^26`：输入 12 小数 + 权重 14 小数 = 26，先对齐成「还没量化的实数」。再按 12 小数收成输出整数。 | 相当于右移对齐后再量化。 |
| 68 | `y=yi/2^12;` | 整数变回实数。 | 输出 S24.12 的实数值。 |
| 69–72 | `audit=struct(...)` | 续行 `...` 表示下一行接着写。 | 记饱和次数、最大输入输出、相对纯浮点 `x*A` 的误差。 |

---

## 行 77–84 `pkg_vf_quantize`

| 行 | 代码 | 语法 | 计算过程 |
|---|---|---|---|
| 79 | `assert(all(isfinite(x(:))),'Vfinal:Nonfinite','...');` | 三参数 `assert`：条件、错误 ID、消息。 | Inf/NaN 直接失败。 |
| 80 | `assert(bits>=2 && bits<=52 && fraction>=0 && fraction<bits);` | 小数位必须少于总位（至少留符号位）。 | 非法字长停。 |
| 81 | `scaled=round(double(x)*2^fraction);` | MATLAB `round`：最近整数，**半数远离 0**（+1.5→2，-1.5→-2）。 | 定点化。 |
| 81 | `lo=-2^(bits-1); hi=2^(bits-1)-1;` | 有符号整数范围。 | 例：24 bit → [-2^23, 2^23-1]。 |
| 82 | `stats.saturations=nnz(scaled<lo\|scaled>hi);` | `\|` 逐元素或；`nnz` 非零个数（逻辑里即「真」的个数）。 | 饱和次数。 |
| 82 | `q=max(lo,min(hi,scaled));` | 钳位。 | 饱和后的整数。 |
| 83 | `stats.maxAbsError=max(abs(q(:)/2^fraction-double(x(:))),[],'omitnan');` | `'omitnan'` 忽略 NaN。 | 量化相对原浮点的最大绝对误差。 |

---

## 行 88–165 `pkg_vf_infer`

### 行 88–111 准备（进 3 轮之前）

| 行 | 代码 | 语法 | 计算过程 |
|---|---|---|---|
| 88 | `function [output,audit]=pkg_vf_infer(task,d,p,steps,mode)` | 五个输入。`p` 这里是 `profile`（入口传入 `p.profile`），不是整个 pack。 | — |
| 91 | `if nargin<5,mode='float';end` | 少传 mode 当浮点。 | — |
| 92 | `A=p.matrix;` | 结构体，字段 `A2,A13,A5` 各一张矩阵。 | 取出三块权重。 |
| 93 | `audit=struct('mvmCalls',0,...);` | 计数器清零。 | 后面嵌套函数会改这些字段。 |
| 94 | `cfg=p.runtime.config; groups=p.runtime.groups;` | 取运行配置。 | 缩放系数、天线分组。 |
| 94 | `if ~iscell(groups), groups=num2cell(groups,2); end` | 不是 cell 就把矩阵**按行**切成 cell。 | 统一成 `{组1, 组2, ...}`。 |
| 95 | `for g=1:numel(groups), groups{g}=double(groups{g}(:).')+1; end` | `{}` 取 cell 内容。`+1`：包里是 0 基下标。 | 变成 MATLAB 的 1…8 天线号，行向量。 |
| 96 | `L=9; if strcmp(task,'channel'), L=21; end` | — | MIMO 每口 9 候选。channel 本包不走。 |
| 97 | `pv=[]; ports=cell(size(groups));` | 空数组；与 groups 同形状的空 cell。 | `pv` 将列出每个口对应哪个发符号（1…4）。`ports{g}` 是该组占用的口下标。 |
| 98–101 | `scope=1:4;` … `ports{g}=numel(pv)+(1:numel(scope)); pv=[pv scope];` | `1:4` 行向量。`[pv scope]` 水平拼接。`%#ok<AGROW>` 告诉编辑器「我知道在变长」。 | **MIMO：每组都带四个发符号。** 5 组 → `pv` 长度 **P=20**，内容为 `[1 2 3 4 1 2 3 4 ...]`。第 g 组的口编号是连续 4 个。channel 时 `scope` 会改，本包不走。 |
| 102 | `B=size(d.local,1); P=numel(pv); S=P*L; output=zeros(B,steps,4,L);` | — | 批、20 口、180 维消息、输出 `B×3×4×9`。 |
| 103 | `pilot=sqrt(8/3)*[...];` | 4×8 复数矩阵字面量，`;` 分行。 | **仅 channel 用。** MIMO 循环里不读它。 |
| 104 | `for b=1:B` | 按批。自测 B=1。 | — |
| 105 | `c=double(squeeze(complex(d.candidateReal(b,:,:),d.candidateImag(b,:,:))).');` | `complex(re,im)` 合成；`squeeze` 去掉长度为 1 的维（批维）；`.'` 变成 4×9（符号 × 候选）。 | 本帧四个符号的 9 个候选复数。 |
| 106 | `y=double(complex(d.yReal(b,:),d.yImag(b,:)));` | 1×8 复数。 | 接收。 |
| 106 | `nv=...; iv=...;` | 本帧方差。若字段是标量，`d.noiseVar(b)` 仍合法。 | — |
| 107 | `local=double(d.local(b,:)); beta=zeros(1,S);` | — | 先验 1×36；消息 β 1×180，**第一轮从全 0 开始**。 |
| 108–110 | `if strcmp(task,'mimo')` | MIMO 才做。 | — |
| 109 | `local=local*cfg.mimoPriorScale;` | 标量乘向量。 | 先验缩放（配置里常为 1）。 |
| 109 | `H=double(squeeze(complex(...)));` | 8×4。 | 信道。 |
| 110 | `order=vf_infer__receiver_order(H,cfg); H=H(order,:); y=y(order);` | `H(order,:)` 按 `order` **重排行**。`y(order)` 同步重排。 | 天线顺序固定后，后面 `rx=1:8` 是重排后的编号。每帧一次。 |

### 行 112–155 一轮 `for t=1:steps`（MIMO 实走）

| 行 | 代码 | 语法 | 计算过程 |
|---|---|---|---|
| 112 | `for t=1:steps` | `steps`＝3。 | 同一套更新做三遍。 |
| 113 | `alpha=reshape(vf_infer__mv('A2',[beta local]),L,P).';` | `[beta local]` 水平拼 180+36=**216**。`mv` 返回 1×180。`reshape(...,9,20)` 按列填成 9×20，再 `.'` 成 **20×9**（口 × 候选）。 | **A2**：邻居消息+先验 → 每口 9 个分数 α。 |
| 113 | `alpha=alpha-max(alpha,[],2);` | `max(...,[],2)` 每行一个最大值，自动扩成 20×1 再减。 | 每个口减自己的峰值。相对分数，防后面 exp 爆。 |
| 114 | `if strcmp(task,'mimo'), alpha=alpha*cfg.mimoAlphaScale; end` | — | 再乘 α 缩放（常为 1）。 |
| 115 | `[a,idx]=sort(alpha,2,'descend');` | 沿第 2 维降序。`a` 排好的值，`idx` 原列号（1…9）。 | 每口候选从高分到低分。 |
| 115 | `cs=zeros(P,L);` | 20×9。 | 将放重排后的星座点。 |
| 116 | `for j=1:P, cs(j,:)=c(pv(j),idx(j,:)); end` | `pv(j)` 是该口对应哪个发符号 1…4；`c(符号, 那 9 个下标)`。 | `cs(j,:)` 与 `a(j,:)` 同一顺序的复数。 |
| 117 | `temp=1; if mimo, temp=cfg.mimoSoftIcTemperature; end` | — | softmax 温度，默认配置里常为 1。 |
| 118 | `prob=exp(a/temp-max(a/temp,[],2)); prob=prob./sum(prob,2);` | `./` 逐元素除；`sum(...,2)` 每行求和。 | softmax：9 个点变成概率，每口和为 1。 |
| 119 | `mu=sum(prob.*cs,2);` | `.*` 逐元素；`sum` 沿候选。 | 软均值 μ，20×1 复数：「这个口现在猜的符号」。 |
| 119 | `varr=sum(prob.*abs(cs-mu).^2,2);` | `mu` 20×1 对 20×9 广播。`abs.^2` 模方。 | 软方差，20×1 实数。 |
| 119 | `lambda=[];` | 空，后面拼接。 | 将收集似然。 |
| 121 | `for rx=1:8` | 重排后的 8 天线。 | — |
| 122 | `g=find(cellfun(@(x)ismember(rx,x),groups));` | `@(x)ismember(rx,x)` 匿名函数；`cellfun` 对每个组问「天线 rx 在不在」；`find` 组号。 | 找到 rx 所属组。`pp=ports{g}` 是该组 4 个口（对应 4 个发符号）。 |
| 123 | `for v=1:4` | 当前组里第 v 个发符号。 | — |
| 124 | `q=pp(v);` | 口下标 1…20。 | 「自己」这个口。 |
| 124 | `residual=y(rx)-H(rx,:)*mu(pp)+H(rx,v)*(mu(q)-cs(q,:));` | `H(rx,:)*mu(pp)` 是 1×4 乘 4×1＝标量（该天线用四个软均值重建）。`cs(q,:)` 是 1×9，于是整式扩成 **1×9**。 | **软干扰抵消：** 先扣掉所有人的均值，再把自己的均值加回去、改成 9 个候选假设。结果：9 种「假如我是这个点」的天线残差。 |
| 125 | `weighted=abs(H(rx,:)).^2.*varr(pp).';` | `varr(pp)` 4×1，`.'` 成 1×4。 | 四个符号在该天线的「不确定度」加权。 |
| 125 | `extra=max(0,sum(weighted)-weighted(v))*cfg.mimoSoftIcVarianceScale;` | 总和减自己那一项＝别人的不确定度。`max(0,·)` 防负。 | 残差方差里加上别人的泄漏。 |
| 126 | `lambda=[lambda vf_infer__mix(residual,nv+extra,iv+extra,ε)];` | mix 对 1×9 逐元素返回 1×9；水平接到 `lambda` 后面。 | 混合高斯对数似然。8×4 次 → `lambda` 最终 **1×288**。 |
| 129 | `lambda=lambda*cfg.mimoLambdaScale;` | — | λ 缩放。 |
| 129 | `ai=a; mx=max(a,[],2); ai(:,1)=mx+log(sum(exp(a-mx),2));` | `ai(:,1)` 改第 1 列。 | 复制排序后的 α；**第一列改成该口 9 个数的 log-sum-exp**（总质量），其余列仍是排序分数。 |
| 130–146 | `else` … `ai=a;` | channel：用 `pilot` 对导频位置做类似抵消。 | **本包不走。** |
| 147 | `score=reshape(vf_infer__mv('A13',[lambda reshape(ai.',1,[])]),L,P).';` | `ai.'` 9×20 → 按列拉成 1×180；与 λ 拼成 **1×468**。出 1×180，再成 20×9。 | **A13**：似然 + 排序域摘要 → 新的每口 9 分数（仍在排序域）。 |
| 147 | `raw=zeros(P,L);` | — | 准备反排。 |
| 148 | `for j=1:P, raw(j,idx(j,:))=score(j,:); end` | 把第 k 名的分数写回原候选下标 `idx(j,k)`。 | 从「第 1 名、第 2 名…」回到「候选 1…9 原来的顺序」。 |
| 149 | `raw=raw-max(raw,[],2); raw=reshape(raw.',1,[]);` | 20×9 → 1×180。 | 再减峰值，平铺成消息向量。 |
| 150 | `raw=raw*cfg.mimoBetaScale;` | MIMO。 | β 缩放。 |
| 151 | `rate=p.runtime.rate; beta=(1-rate)*beta+rate*raw;` | — | **阻尼：** 本包 `rate=0.3`，即 `β ← 0.7 β_old + 0.3 raw`。 |
| 152 | `bi=beta; li=local;` | 拷贝。 | 后验这条支路可以另缩放，不改正在迭代的 β。 |
| 153 | `if mimo, bi=bi*...; li=li*...; end` | — | 进 A5 前的后验缩放。 |
| 154 | `z=reshape(vf_infer__mv('A5',[bi li]),L,4).';` | 180+36=216 入，出 36，reshape 成 9×4 再转置 **4×9**。 | **A5**：四个符号的后验分数。 |
| 154 | `output(b,t,:,:)=reshape(z,1,1,4,L);` | 写成 1×1×4×9 才能塞进 `B×T×4×L` 的切片。 | 记下第 b 帧第 t 轮。 |

### 行 157–164 嵌套函数 `vf_infer__mv`

嵌套在 `pkg_vf_infer` **内部**（注意第 157 行前面有空格）。语法：能读/写外层的 `audit, mode, A, p`，不必当参数传来。外层 `end` 在第 165 行，把嵌套一起结束。

| 行 | 代码 | 语法 | 计算过程 |
|---|---|---|---|
| 157 | `function y=vf_infer__mv(stage,x)` | `stage` 是 `'A2'`/`'A13'`/`'A5'`。 | — |
| 158 | `audit.mvmCalls=audit.mvmCalls+1;` | 改外层结构体。 | 计数。三轮 × 3 次 = 9。 |
| 159 | `if strcmp(mode,'float'), y=x*double(A.(stage)); return; end` | `A.(stage)` **动态字段名**：`A.A2` 等。`return` 离开嵌套函数。 | 稠密矩阵乘（很多零也乘）。 |
| 160 | `[y,s]=pkg_vf_fixed_mvm(x,double(A.(stage)),p.matrices.(stage));` | `p.matrices.A2` 等带字长。 | 定点阵列口。 |
| 161–163 | 累加饱和、最大误差、最大幅值 | `max(旧, 新)` 滚动记录。 | 给入口 `audit`。 |

---

## 行 166–169 `vf_infer__mix`

| 行 | 代码 | 语法 | 计算过程 |
|---|---|---|---|
| 167 | `a=log(1-ep)-log(pi*nv)-abs(r).^2/nv;` | `r` 可为向量；`abs(r).^2` 逐元素模方；`/nv` 标量除。 | 正常噪声分量的对数密度：\(\log\frac{1-\varepsilon}{\pi n_v}-\|r\|^2/n_v\)。复数圆对称，分母是 \(\pi\sigma^2\) 不是 \(2\pi\)。 |
| 167 | `b=log(ep)-log(pi*iv)-abs(r).^2/iv;` | 同样。 | 脉冲分量。 |
| 168 | `m=max(a,b); y=m+log(exp(a-m)+exp(b-m));` | 与 `stable_logadd` 相同。 | \(\log(e^a+e^b)\)，即混合密度的对数。输出与 `r` 同形状（软 IC 时为 1×9）。 |

---

## 行 170–181 `vf_infer__receiver_order`

| 行 | 代码 | 语法 | 计算过程 |
|---|---|---|---|
| 171 | `power=sum(abs(H).^2,2); [~,order]=sort(power); order=order(:).';` | `sort` 默认升序。`~` 丢掉排好的值。`(:).'` 保证 1×8。 | 8 根天线按行能量从弱到强的下标。 |
| 172 | `if ~isfield(...) \|\| strcmp(...,'energy'), return; end` | `\|\|` 短路或。`return` 带着当前 `order` 离开。 | 策略是能量 或 没写字段 → 只用这一排序。 |
| 173 | `assert(strcmp(...,'correlation_groups'));` | 只认这一种第二策略。 | 其它字符串停。 |
| 174 | `h=H(order,:);` | 先按能量排好再算相关。 | — |
| 174 | `rho=abs(h*h').^2./max(power*power',1e-12);` | `h*h'` 是 8×8 Gram。`power*power'` 是外积。`./` 逐元素。`max(...,1e-12)` 防除零。 | 归一化相关（越大越「绑在一起」）。 |
| 174 | `e=power/mean(power);` | 相对能量。 | — |
| 175 | `w=1; if isfield(...), w=...; end` | 默认能量权重 1。 | 代价里相关和能量怎么掺。 |
| 176 | `pairs=nchoosek(2:8,2);` | 从 {2..8} 里取 2 的组合，每行一对。 | 与最弱天线（现编号 1）组成三人组的候选。 |
| 177 | `cost(k)=rho(1,i)+rho(1,j)+rho(i,j)+w*(e(i)+e(j));` | — | 三人组代价：三对相关 + 能量。 |
| 178 | `[~,k]=min(cost); triple=[1 pairs(k,:)]; rest=setdiff(1:8,triple);` | `setdiff` 差集，默认排序。 | 最便宜的三人组；剩下 5 根。 |
| 178–180 | 在 `rest` 里同样 `nchoosek` 挑一对 | 代价只有这一对的相关+能量。 | 二人组。 |
| 180 | `order=order([triple pair setdiff(rest,pair)]);` | 下标拼接：三人、二人、剩下三个。 | 把「新编号」映射回**原始天线行号**，作为最终 `order`。 |

---

## 行 184–227 `pkg_mimo_candidate_frontend`

| 行 | 代码 | 语法 | 计算过程 |
|---|---|---|---|
| 184–185 | 函数签名续行 `...` | 四个输出、七个输入。 | — |
| 191–195 | `Nt=cfg.Nt;` 等 | 从配置取标量。 | 通常 Nt=4，L=9，ε、残差权重 0.25、覆盖间隙 2。 |
| 197 | `A=H'*H+noiseVar*eye(Nt);` | `'` **共轭**转置。`eye(Nt)` 单位阵。 | 4×4：Gram + σ²I。 |
| 198 | `xhat=A\(H'*y);` | `\` 解线性方程（左除），比 `inv(A)*` 稳。 | LMMSE：\(\hat x=(H^H H+\sigma^2 I)^{-1} H^H y\)，4×1。 |
| 199 | `covariance=A\eye(Nt);` | 等于 A 的逆。 | 得到 4×4 的逆矩阵，下一行取其对角作为评分尺度。 |
| 200 | `variance=max(real(diag(covariance)),1e-8);` | `diag` 取对角；`real` 丢掉数值虚部；`max` 与 1e-8。 | 第 v 个对角元素实部取下界 1e−8，作为该流距离评分的尺度。 |
| 201–205 | `zeros(...)` | 预分配。 | 64×4 分数；9×4 输出。 |
| 207 | `for v=1:Nt` | 每个发符号单独挑 9 点。 | — |
| 208 | `scoreLmmse=-abs(constellation-xhat(v)).^2./(2*variance(v));` | `constellation` 64×1 减标量，64 个距离。 | 离粗估计越近分越高（高斯对数似然，差一个常数）。 |
| 209 | `scoreLmmse=scoreLmmse-max(scoreLmmse);` | 无维参数的 `max` 对向量返回一个数。 | 减峰值。 |
| 210 | `residualWithoutTarget=y-H*xhat+H(:,v)*xhat(v);` | 8×1。 | 从重建里拿掉符号 v，天线残差不含 v。 |
| 212–216 | `for k=1:64` … `residual=...-H(:,v)*constellation(k);` | — | 假设 v 发第 k 点，8 根天线残差。 |
| 214–215 | `sum(mixture_log_likelihood_vector(residual,...))` | 对 8 根天线的对数似然**相加**（独立）。 | 该点的残差分数。 |
| 217 | `scoreResidual=scoreResidual-max(...);` | — | 减峰值。 |
| 218 | `score=scoreLmmse+residualWeight*scoreResidual;` | — | 综合分：LMMSE + 0.25×残差。 |
| 219 | `[~,order]=sort(score,'descend');` | `order` 是 64 个下标，最好的在前。 | — |
| 220 | `keep=...bit_coverage(order,score,bitTable,L,coverageGap);` | 见下节。 | 从名单里定下正好 9 个下标，并尽量让 6 bit 都有 0 和 1。 |
| 221–223 | 写入三张表的第 v 列 | — | 保存分数和下标。 |
| 224–225 | `value=score(keep); localScore(:,v)=value-max(value);` | — | 留下的 9 个分数再减最大 → 先验 `local`。 |

---

## 行 229–279 比特覆盖

| 行 | 代码 | 语法 | 计算过程 |
|---|---|---|---|
| 230 | `keep=order(1:L);` | 先取前 9 名。 | 初始名单。 |
| 231 | `nBit=size(bitTable,2);` | 列数＝6。 | — |
| 232 | `for pass=1:nBit` | 最多扫 6 轮。 | 一轮可能改 keep，需要再扫。 |
| 233 | `changed=false;` | 逻辑。 | 本轮有没有换人。 |
| 234 | `for b=1:nBit` | 检查每一个比特。 | — |
| 235 | `present=unique(bitTable(keep,b));` | `unique` 去重。 | 这 9 个点在 bit b 上出现了哪些值。 |
| 236–238 | `if numel(present)~=1, continue; end` | `continue` 跳到下一 `b`。 | 已经同时有 0 和 1 → 这比特不用补。 |
| 239 | `wanted=1-present(1);` | 0↔1。 | 缺的那一面。 |
| 240 | `addPos=find(bitTable(order,b)==wanted & ~ismember(order,keep),1);` | `find(...,1)` 只找**第一个**。`ismember` 是否已在 keep。`&` 逐元素与。 | 在大名单里、尚未入选、该 bit 是反码的、分数尽量靠前的点。 |
| 241–243 | `isempty` 则 `continue` | 找不到反码点。 | — |
| 244 | `addState=order(addPos);` | 真正的星座下标。 | 候选人。 |
| 245–247 | `if score(order(1))-score(addState)>gapLimit, continue; end` | 第一名减候选人。 | 分差大于 2 → 太差，不换，以免把好点换成差很远的点。 |
| 248–252 | `counts(q,1/2)=sum(bitTable(keep,q)==0/1)` | 9 个点里每个 bit 的 0/1 计数。 | 用来判断删谁不会让别的 bit 又变单边。 |
| 253–267 | `for pos=L:-1:1` 从**最差**往前找 | `L:-1:1` 递减。 | 优先换掉名单末尾。 |
| 255–261 | `if counts(q,row(q)+1)<=1` 则不可删 | `row(q)` 是 0 或 1，MATLAB 下标 +1 变成 1 或 2。`<=1` 表示这个点是该 bit 某一面的**最后一人**。 | 删了会让某 bit 又缺一面。 |
| 263–266 | 找到可删位置就 `break` | — | `replacePos`。 |
| 268–271 | `keep(replacePos)=addState; changed=true;` | 替换。 | 9 个长度不变。 |
| 273–275 | `if ~changed, break; end` | 一整轮 6 个 bit 都没换 → 停止外层 pass。 | — |
| 277–278 | `[~,rankOrder]=sort(score(keep),'descend'); keep=keep(rankOrder);` | 按分数重排 keep。 | 输出仍是高分在前的 9 个下标。 |

---

## 行 281–286 前端 mixture（与 `vf_infer__mix` 同公式）

| 行 | 代码 | 语法 | 计算过程 |
|---|---|---|---|
| 282–283 | `a=...; b=...;` | `residual` 为 8×1，输出 8×1。 | 每根天线一个正常/脉冲对数密度。 |
| 284–285 | `peak=max(a,b); value=peak+log(exp(a-peak)+exp(b-peak));` | 向量 `max`。 | 每根天线的混合对数似然。调用方再 `sum` 成一个点的分数。 |

---

## 读代码时的数据尺寸速查（MIMO，B=1）

| 时刻 | 变量 | 形状 | 从哪一行来 |
|---|---|---|---|
| 前端后 | `local` | 1×36 | 33 |
| 前端后 | 候选 | 1×9×4 | 32 |
| 核准备 | `P,S` | 20, 180 | 102 |
| 每轮 A2 入 | `[beta local]` | 1×216 | 113 |
| 每轮 α,a | | 20×9 | 113–115 |
| 每轮 λ | | 1×288 | 121–126 |
| 每轮 A13 入 | `[λ, ai平铺]` | 1×468 | 147 |
| 每轮 A5 入 | `[bi li]` | 1×216 | 154 |
| 每轮后验 | `z` | 4×9 | 154 |
| 读出 | `llr` | 1×24 | 54 |

**两种 idx，两个地址空间。** 第 31–34 行的 idx 是 64 点星座下标（1…64），以零基表示需 6 位。第 115 行 sort 的 idx 是每口的 9 槽排列（1…9），以零基表示需 4 位；第 148 行按后者散回。接口对拍时分别保存候选身份与排序索引。第 54 行输出按流排列，每流依次存 I 轴三位与 Q 轴三位的六个软值，共占 24 个输出地址。
