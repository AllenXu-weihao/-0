function run_share78()
% Joint 8-bit and 7-bit formats on the archived seed-1105 frames.
% Fraction bits are the finest legal values that still hold the E0 peak
% of that same frame set. Wires whose peak does not fit stay double.
% This is a coverage probe, not a frozen FPGA word length.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
addpath(fullfile(root,'实验档案'));
addpath(fileparts(mfilename('fullpath')));
cd(root);
R = new_run('E3','share78',1105,1);
write_protocol(R);
S = load(fullfile(root,'实验档案','01_运行记录', ...
    'E2_alpha_s1105_a01_20261109_151630_tp000a4ea5_7e93_49b9_93c9_dae10b3a38fb', ...
    'raw','20261109_151811_alpha_tpf0c841e9_c436_476f_9e66_299c79cabd66','inputs.mat'));
cases = S.cases;
assert(numel(cases)==80);
ref = cell(numel(cases),1);
for k = 1:numel(cases)
    ref{k} = MIMO(cases(k).input,'float');
end
jobs = {'peak8', formats8(); 'peak7', formats7()};
frameFile = fullfile(R.raw,'per_frame.csv');
sumFile = fullfile(R.raw,'summary.csv');
fid = fopen(frameFile,'w','n','UTF-8');
assert(fid>=0);
fprintf(fid,'name,case_index,backgroundSNR,floatErrors,candidateErrors,disagreements,became_wrong,became_correct,llrMax,saturations\n');
sf = fopen(sumFile,'w','n','UTF-8');
assert(sf>=0);
fprintf(sf,'name,candidateErrors,disagreements,became_wrong,became_correct,llrMax,saturations,e0,e10,e20,e30,d0,d10,d20,d30\n');
for j = 1:size(jobs,1)
    name = jobs{j,1};
    fmt = jobs{j,2};
    rows = zeros(numel(cases),10);
    fprintf('JOB %s\n', name);
    for k = 1:numel(cases)
        [r,st] = run_quantized(cases(k).input,fmt);
        truth = cases(k).truth;
        fb = ref{k}.bits ~= truth;
        cb = r.bits ~= truth;
        dg = r.bits ~= ref{k}.bits;
        wrong = nnz(~fb & cb);
        right = nnz(fb & ~cb);
        llr = max(abs(r.llr-ref{k}.llr),[],'all');
        sat = sat_sum(st);
        rows(k,:) = [k, cases(k).snrDB, nnz(fb), nnz(cb), nnz(dg), wrong, right, llr, sat, 0];
        fprintf(fid,'%s,%d,%.0f,%d,%d,%d,%d,%d,%.8g,%d\n', ...
            name,k,cases(k).snrDB,nnz(fb),nnz(cb),nnz(dg),wrong,right,llr,sat);
        fprintf('  case %d snr %.0f err %d disagree %d llr %.4g sat %d\n', ...
            k, cases(k).snrDB, nnz(cb), nnz(dg), llr, sat);
    end
    snr = rows(:,2);
    bins = [0 10 20 30];
    e = zeros(1,4); d = zeros(1,4);
    for b = 1:4
        m = snr==bins(b);
        e(b) = sum(rows(m,4));
        d(b) = sum(rows(m,5));
    end
    fprintf(sf,'%s,%d,%d,%d,%d,%.8g,%d,%d,%d,%d,%d,%d,%d,%d,%d\n', ...
        name, sum(rows(:,4)), sum(rows(:,5)), sum(rows(:,6)), sum(rows(:,7)), ...
        max(rows(:,8)), sum(rows(:,9)), e(1),e(2),e(3),e(4), d(1),d(2),d(3),d(4));
    fprintf('SUM %s cand %d disagree %d wrong %d right %d llr %.4g sat %d bins %d/%d/%d/%d\n', ...
        name, sum(rows(:,4)), sum(rows(:,5)), sum(rows(:,6)), sum(rows(:,7)), ...
        max(rows(:,8)), sum(rows(:,9)), e(1),e(2),e(3),e(4));
end
fclose(fid);
fclose(sf);
fprintf('SHARE78_DONE %s\n', R.id);
end

function n = sat_sum(st)
n = 0;
names = fieldnames(st);
for i = 1:numel(names)
    a = st.(names{i});
    if isstruct(a) && isfield(a,'saturations')
        n = n + a.saturations;
    end
end
end

function fmt = formats8()
fmt = struct();
fmt.A13_acc = pair(8,1); fmt.A13_out = pair(8,1); fmt.A13_product = pair(8,1);
fmt.A13_w = pair(8,6); fmt.A13_x = pair(8,0);
fmt.A2_acc = pair(8,0); fmt.A2_out = pair(8,0); fmt.A2_product = pair(8,1);
fmt.A2_w = pair(8,6); fmt.A2_x = pair(8,1);
fmt.A5_acc = pair(8,0); fmt.A5_out = pair(8,0); fmt.A5_product = pair(8,1);
fmt.A5_w = pair(8,6); fmt.A5_x = pair(8,1);
fmt.ai = pair(8,0); fmt.alpha = pair(8,0); fmt.beta = pair(8,2);
fmt.damp_product_new = pair(8,3); fmt.damp_product_old = pair(8,3); fmt.damp_sum = pair(8,2);
fmt.exp = pair(8,6);
fmt.frontend_center = pair(8,6); fmt.frontend_cov = pair(8,5); fmt.frontend_gram = pair(8,4);
fmt.frontend_local = pair(8,1); fmt.frontend_rhs = pair(8,4); fmt.frontend_variance = pair(8,5);
fmt.input_H = pair(8,6); fmt.input_y = pair(8,4);
fmt.lambda = pair(8,1); fmt.llr = pair(8,2);
fmt.mix_b = pair(8,1); fmt.mix_output = pair(8,1);
fmt.mu = pair(8,6); fmt.prob = pair(8,6); fmt.rate = pair(8,7);
fmt.raw = pair(8,1); fmt.residual = pair(8,4); fmt.sum_exp = pair(8,3);
fmt.var = pair(8,7); fmt.weighted = pair(8,7);
end

function fmt = formats7()
fmt = struct();
fmt.A13_acc = pair(7,0); fmt.A13_out = pair(7,0); fmt.A13_product = pair(7,0); fmt.A13_w = pair(7,5);
fmt.A2_product = pair(7,0); fmt.A2_w = pair(7,5); fmt.A2_x = pair(7,0);
fmt.A5_product = pair(7,0); fmt.A5_w = pair(7,5); fmt.A5_x = pair(7,0);
fmt.beta = pair(7,1);
fmt.damp_product_new = pair(7,2); fmt.damp_product_old = pair(7,2); fmt.damp_sum = pair(7,1);
fmt.exp = pair(7,5);
fmt.frontend_center = pair(7,5); fmt.frontend_cov = pair(7,4); fmt.frontend_gram = pair(7,3);
fmt.frontend_local = pair(7,0); fmt.frontend_rhs = pair(7,3); fmt.frontend_variance = pair(7,4);
fmt.input_H = pair(7,5); fmt.input_y = pair(7,3);
fmt.lambda = pair(7,0); fmt.llr = pair(7,1);
fmt.mix_b = pair(7,0); fmt.mix_output = pair(7,0);
fmt.mu = pair(7,5); fmt.prob = pair(7,5); fmt.rate = pair(7,6);
fmt.raw = pair(7,0); fmt.residual = pair(7,3); fmt.sum_exp = pair(7,2);
fmt.var = pair(7,6); fmt.weighted = pair(7,6);
end

function f = pair(W,F)
f = struct('W',W,'F',F);
end

function write_protocol(R)
fid = fopen(fullfile(R.dir,'protocol.md'),'w','n','UTF-8');
assert(fid>=0);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'# 单次实验协议\n\n');
fprintf(fid,'冻结时间：运行开始前，时区 UTC+8。run_id 由 new_run 生成，见 manifest。\n\n');
fprintf(fid,'|项目|本次冻结值|\n|---|---|\n');
fprintf(fid,'|阶段|E3 联合覆盖探针，不是 E2-M，也不是 E4|\n');
fprintf(fid,'|问题|把峰值能装进 8 bit 的线同时量化后，这 80 帧的硬判和 LLR 相对双精度变多少；7 bit 只量化峰值装得下的线|\n');
fprintf(fid,'|假设|峰值安全的最细小数位可以让大约 85%% 的非零数据流处在 7–8 bit，同时硬判差保持很小。数据可以否定它|\n');
fprintf(fid,'|占比|非零样本。三张系数矩阵只计非零元 900/828/216，不把结构零算进分母。E0 同一批帧上，8 bit 峰值可覆盖 96.3%%，7 bit 峰值可覆盖 77.7%%|\n');
fprintf(fid,'|参考|归档 inputs.mat 上的 MIMO float。对照是双精度硬判和发送真值|\n');
fprintf(fid,'|自变量|peak8：除 mix_a、frontend_score、input_nv、input_iv 外全部量化到总宽 8，小数位取仍能包住 E0 峰值的最大值。peak7：只量化峰值不超过 63 的线，总宽 7，同样取最细小数位。装不下的线，以及会把正的最小噪声打成 0 的 input_nv 与 input_iv，保持双精度|\n');
fprintf(fid,'|输入|E2 归档的 80 帧，种子 1105，0/10/20/30 dB 各 20 帧，每帧 24 bit|\n');
fprintf(fid,'|算术|系数、乘积或累加器格式一旦存在，矩阵乘走有序乘积后累加再舍入。舍入为 MATLAB round，饱和。mix_a 与 frontend_score 保持双精度。阻尼仍是运行时 0.3，不是 307/717|\n');
fprintf(fid,'|指标|候选误码、相对 float 的硬判差、对变错、错变对、LLR 最大绝对差、饱和次数。分母 1920 bit。不设通过线|\n');
fprintf(fid,'|终止|两档各跑完 80 帧即停。不启动 E4，不综合|\n');
fprintf(fid,'\n前次 E3_share78_s1105_a01_20261110_103741 在 peak8 第 61 帧（30 dB）停止：S8.6 把 input_nv=0.001 舍入成 0，frontend 的正数断言失败。本轮因此把 input_nv 和 input_iv 留在双精度。\n');
end
