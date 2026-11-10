function run_batch3()
% Third batch: raw and beta single-edge ladders, then the joint start.
% Protocols are written before any candidate result is read.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
addpath(fullfile(root,'实验档案'));
addpath(fileparts(mfilename('fullpath')));
cd(root);
source = fullfile(root,'实验档案','01_运行记录', ...
    'E0_baseline_s1105_a01_20261109_145449_tpcdb53181_74d4_4723_9e0e_efe47567de32', ...
    'raw','stitch','inputs.mat');
S = load(source,'cases');
cases = S.cases;
assert(numel(cases)==80 && all([cases.seed]==1105));
rawFormats = [21 13; 19 11; 17 9; 15 7];
betaFormats = [21 14; 19 12; 17 10; 15 8];
A = new_run('E2','raw_sweep',1105,1);
B = new_run('E2','beta_sweep',1105,1);
write_edge_protocol(A,'raw',8,rawFormats,source);
write_edge_protocol(B,'beta',7,betaFormats,source);
mark_running(A,'raw',rawFormats,'only raw quantized; ordered MAC off; default floating matrix product');
mark_running(B,'beta',betaFormats,'only beta quantized; ordered MAC off; default floating matrix product');
append_index(root,A,'RUNNING','待定');
append_index(root,B,'RUNNING','待定');
fprintf('TRANSPARENCY raw\n');
check_transparency(fullfile(A.raw,'trace'), cases, 'raw', struct('raw',struct('W',15,'F',7)));
fprintf('TRANSPARENCY beta\n');
check_transparency(fullfile(B.raw,'trace'), cases, 'beta', struct('beta',struct('W',15,'F',8)));
fprintf('SWEEP raw\n');
rawRuns = exp_feedback('raw',rawFormats,cases);
archive_edge_runs(A,rawRuns);
assert_float_bins(rawRuns{1});
write_elements(A,rawRuns,'raw');
fprintf('SWEEP beta\n');
betaRuns = exp_feedback('beta',betaFormats,cases);
archive_edge_runs(B,betaRuns);
assert_float_bins(betaRuns{1});
write_elements(B,betaRuns,'beta');
fprintf('TRACE raw\n');
trace_edge(fullfile(A.raw,'trace'), cases, 'raw', rawFormats);
fprintf('TRACE beta\n');
trace_edge(fullfile(B.raw,'trace'), cases, 'beta', betaFormats);
finish_edge(A);
finish_edge(B);
fprintf('JOINT\n');
run_joint(root, cases, source);
fprintf('BATCH3_DONE %s %s\n', A.id, B.id);
end

function write_edge_protocol(R, edge, intBits, formats, source)
fid = fopen(fullfile(R.dir,'protocol.md'),'w','n','UTF-8');
assert(fid>=0);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'# 单次实验协议\n\n冻结于采集之前。run_id 见 manifest。\n\n');
fprintf(fid,'|项目|本次冻结值|\n|---|---|\n');
fprintf(fid,'|问题|只量化 %s 时，总宽 21/19/17/15 哪一档开始离开双精度硬判|\n', edge);
fprintf(fid,'|整数位|含符号 %d 位，小数位等于总宽减整数位|\n', intBits);
fprintf(fid,'|对照|同一归档输入上的 MIMO float。固定项是其余边双精度、默认浮点矩阵乘、阻尼 0.3|\n');
fprintf(fid,'|输入|%s|\n', strrep(source,'\','/'));
fprintf(fid,'|格式|');
for k = 1:size(formats,1)
    fprintf(fid,' S(%d,%d)', formats(k,1), formats(k,2));
end
fprintf(fid,' |\n|指标|候选误码、两向翻转、分档、最大绝对 LLR 差、该边饱和、元素数。分母每档 1920 bit。不设通过线|\n');
fprintf(fid,'|终止|四档跑完即停。不由此拼成联合结果，不打开 E4|\n');
end

function mark_running(R, edge, formats, arithmetic)
m = jsondecode(fileread(R.manifest));
m.status = 'RUNNING';
m.driver_revision = 'experiments/run_batch3.m';
m.entry_command = 'run_batch3';
m.dataset_role = '回归';
m.cases_path = '实验档案/01_运行记录/E0_baseline_s1105_a01_20261109_145449_tpcdb53181_74d4_4723_9e0e_efe47567de32/raw/stitch/inputs.mat';
m.reference = 'MIMO float';
m.matrix_arithmetic = arithmetic;
m.architecture = 'instrumented MATLAB, single edge, official table with trace off';
m.decision_rule = 'no pass line and no frozen width';
ids = cell(1,size(formats,1));
for k = 1:size(formats,1)
    ids{k} = sprintf('%s_W%d_F%d', edge, formats(k,1), formats(k,2));
end
m.candidate_ids = ids;
write_manifest(R.manifest, m);
end

function write_manifest(path, m)
fid = fopen(path,'w','n','UTF-8');
assert(fid>=0);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n', jsonencode(m));
end

function append_index(root, R, status, decision)
fid = fopen(fullfile(root,'实验档案','02_汇总','运行索引.csv'),'a','n','UTF-8');
assert(fid>=0);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
rel = ['实验档案/01_运行记录/' R.id];
fprintf(fid,'%s,%s,1,,回归,%s,%s,%s/protocol.md,%s/manifest.json,\n', ...
    R.id, R.id(1:2), status, decision, rel, rel);
end

function check_transparency(folder, cases, edge, fmt)
if ~exist(folder,'dir'), mkdir(folder); end
empty = struct();
off = run_pack(cases, empty, false);
on = run_pack(cases, empty, true);
qOff = run_pack(cases, fmt, false);
qOn = run_pack(cases, fmt, true);
fid = fopen(fullfile(folder,'透明.txt'),'w','n','UTF-8');
assert(fid>=0);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
g1 = pack_gap(off,on);
g2 = pack_gap(qOff,qOn);
b2 = pack_bit_frames(qOff,qOn);
fprintf(fid,'边 %s。不量化时开 trace 与关 trace 的最大 LLR 差 %.8g。\n', edge, g1);
fprintf(fid,'最窄档开 trace 与关 trace 的最大 LLR 差 %.8g，硬判不同帧数 %d。\n', g2, b2);
assert(g1<1e-9 && g2<1e-9 && b2==0, 'Trace changed %s.', edge);
end

function trace_edge(folder, cases, edge, formats)
if ~exist(folder,'dir'), mkdir(folder); end
floatPack = run_pack(cases, struct(), true);
fid = fopen(fullfile(folder,'idx摘要.csv'),'w','n','UTF-8');
assert(fid>=0);
fprintf(fid,'format,round,portRounds,idxDiffPorts,newEqualPairs,maxAbsBetaDiff,firstCase,firstRound,firstPort,firstSlot\n');
repDir = fullfile(folder,'代表帧');
if ~exist(repDir,'dir'), mkdir(repDir); end
kept = zeros(1,0);
for f = 1:size(formats,1)
    spec = struct();
    spec.(edge) = struct('W',formats(f,1),'F',formats(f,2));
    name = sprintf('W%d_F%d', formats(f,1), formats(f,2));
    pack = run_pack(cases, spec, true);
    first = [0 0 0 0];
    hardCase = 0; softCase = 0;
    for roundIndex = 1:3
        diffPorts = 0; pairs = 0; beta = 0; ports = 0;
        for k = 1:numel(cases)
            got = pack{k}.trace.round(roundIndex);
            ref = floatPack{k}.trace.round(roundIndex);
            for p = 1:size(got.idx,1)
                ports = ports+1;
                if any(got.idx(p,:) ~= ref.idx(p,:))
                    diffPorts = diffPorts+1;
                    if first(1)==0
                        slot = find(got.idx(p,:) ~= ref.idx(p,:),1);
                        first = [k roundIndex p slot];
                    end
                end
                pairs = pairs + got.newEqualPairs(p);
            end
            beta = max(beta, max(abs(got.betaAfter(:)-ref.betaAfter(:))));
        end
        fprintf(fid,'%s,%d,%d,%d,%d,%.8g,%d,%d,%d,%d\n', name, roundIndex, ports, diffPorts, pairs, beta, first(1), first(2), first(3), first(4));
    end
    for k = 1:numel(cases)
        if hardCase==0 && any(pack{k}.bits ~= floatPack{k}.bits)
            hardCase = k;
        end
        if softCase==0 && all(pack{k}.bits==floatPack{k}.bits) && max(abs(pack{k}.llr(:)-floatPack{k}.llr(:)))>1e-8
            softCase = k;
        end
    end
    dump_pair(repDir, name, floatPack, pack, cases, hardCase);
    dump_pair(repDir, name, floatPack, pack, cases, softCase);
    kept = [kept hardCase softCase]; %#ok<AGROW>
    fprintf('  %s hard %d soft %d first %d/%d/%d/%d\n', name, hardCase, softCase, first(1), first(2), first(3), first(4));
end
fclose(fid);
list = fopen(fullfile(repDir,'帧清单.txt'),'w','n','UTF-8');
fprintf(list,'保留帧号：%s\n分母每档 80 帧、1920 bit。0 表示该档没有这种帧。\n', sprintf('%d ', unique(kept(kept>0))));
fclose(list);
end

function dump_pair(folder, name, floatPack, pack, cases, frame)
if frame<=0, return; end
dump_one(fullfile(folder, sprintf('case_%02d_%s_float.csv', frame, name)), floatPack{frame}, cases(frame), frame);
dump_one(fullfile(folder, sprintf('case_%02d_%s.csv', frame, name)), pack{frame}, cases(frame), frame);
end

function dump_one(path, pack, oneCase, frame)
fid = fopen(path,'w','n','UTF-8');
assert(fid>=0);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'case_index,%d,snr,%g\n', frame, oneCase.snrDB);
fprintf(fid,'truth'); fprintf(fid,',%d', oneCase.truth); fprintf(fid,'\n');
fprintf(fid,'bits'); fprintf(fid,',%d', pack.bits); fprintf(fid,'\n');
fprintf(fid,'llr'); fprintf(fid,',%.8g', pack.llr); fprintf(fid,'\n');
for roundIndex = 1:3
    rec = pack.trace.round(roundIndex);
    fprintf(fid,'round,%d\n', roundIndex);
    fprintf(fid,'idx'); fprintf(fid,',%d', rec.idx); fprintf(fid,'\n');
    fprintf(fid,'betaAfter'); fprintf(fid,',%.8g', rec.betaAfter); fprintf(fid,'\n');
    fprintf(fid,'raw'); fprintf(fid,',%.8g', rec.raw); fprintf(fid,'\n');
end
end

function out = run_pack(cases, fmt, traceOn)
n = numel(cases);
out = cell(n,1);
opts = struct('trace',traceOn,'orderedObserve',false);
for k = 1:n
    [r,st] = run_quantized(cases(k).input, fmt, opts);
    out{k} = struct('llr',r.llr,'bits',r.bits,'trace',[]);
    if traceOn, out{k}.trace = st.trace; end
    if mod(k,20)==0, fprintf('  pack %d/%d\n', k, n); end
end
end

function gap = pack_gap(a,b)
gap = 0;
for k = 1:numel(a)
    gap = max(gap, max(abs(a{k}.llr(:)-b{k}.llr(:))));
end
end

function n = pack_bit_frames(a,b)
n = 0;
for k = 1:numel(a)
    if any(a{k}.bits ~= b{k}.bits), n = n+1; end
end
end

function assert_float_bins(result)
a = result.metrics;
bins = zeros(1,4);
snrs = [0 10 20 30];
for b = 1:4
    bins(b) = sum(a.floatErrors(a.backgroundSNR==snrs(b)));
end
fprintf('FLOAT_BINS %d/%d/%d/%d\n', bins(1), bins(2), bins(3), bins(4));
assert(isequal(bins, [190 61 5 0]), 'Float baseline bins changed.');
end

function write_elements(R, runs, edge)
fid = fopen(fullfile(R.raw,'元素数.csv'),'w','n','UTF-8');
assert(fid>=0);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'candidate,elements,saturations\n');
for f = 1:numel(runs)
    fmt = runs{f}.formats.(edge);
    elements = 0; sat = 0;
    for k = 1:numel(runs{f}.stats)
        st = runs{f}.stats{k};
        elements = elements + st.(edge).elements;
        sat = sat + st.(edge).saturations;
    end
    fprintf(fid,'%s_W%d_F%d,%d,%d\n', edge, fmt.W, fmt.F, elements, sat);
end
end

function finish_edge(R)
m = jsondecode(fileread(R.manifest));
m.status = 'COMPLETE';
m.raw_sources = {'raw/trace/透明.txt','raw/trace/idx摘要.csv','raw/元素数.csv'};
write_manifest(R.manifest, m);
end

function run_joint(root, cases, source)
R = new_run('E2-M','joint_start',1105,1);
fid = fopen(fullfile(R.dir,'protocol.md'),'w','n','UTF-8');
assert(fid>=0);
fprintf(fid,'# 单次实验协议\n\n冻结于联合采集之前。\n\n');
fprintf(fid,'先在同一 inputs.mat 上复现 mild。复现之后只把 alpha 改为 S(21,12)、raw 改为 S(21,13)、beta 改为 S(21,14)。其余边保持 mild。\n\n');
fprintf(fid,'进入网格的条件：mild 为 181/61/5/0 且硬判差 13；联合配置 10 dB 候选错不超过 69/480。未通过则从联合起点每次只把一条边恢复成 mild。\n');
fprintf(fid,'输入：%s\n', strrep(source,'\','/'));
fclose(fid);
m = jsondecode(fileread(R.manifest));
m.status = 'RUNNING';
m.driver_revision = 'experiments/run_batch3.m';
m.entry_command = 'run_batch3 joint section';
m.dataset_role = '回归';
m.cases_path = '实验档案/01_运行记录/E0_baseline_s1105_a01_20261109_145449_tpcdb53181_74d4_4723_9e0e_efe47567de32/raw/stitch/inputs.mat';
m.reference = 'MIMO float and mild stitch';
m.candidate_ids = {'mild','joint_W21'};
m.matrix_arithmetic = 'mild stitch arithmetic: ordered product then acc when those formats exist';
m.architecture = 'instrumented MATLAB, full format dict, not a stitch of three single-edge runs';
m.decision_rule = '10 dB candidate errors <= 69 of 480 after mild is reproduced';
write_manifest(R.manifest, m);
append_joint_index(root, R, 'RUNNING', '待定');
mild = mild_format();
joint = mild;
joint.alpha = pair(21,12);
joint.raw = pair(21,13);
joint.beta = pair(21,14);
ref = cell(numel(cases),1);
for k = 1:numel(cases)
    ref{k} = MIMO(cases(k).input,'float');
end
eval_named(R, cases, ref, 'mild', mild);
got = read_summary_row(fullfile(R.raw,'summary.csv'), 'mild');
assert(got.e0==181 && got.e10==61 && got.e20==5 && got.e30==0 && got.disagreements==13, ...
    'Mild replay disagreed with the archived 181/61/5/0 and 13 disagreements.');
eval_named(R, cases, ref, 'joint_W21', joint);
row = read_summary_row(fullfile(R.raw,'summary.csv'), 'joint_W21');
fprintf('JOINT_GATE 10dB %d disagreements %d\n', row.e10, row.disagreements);
if row.e10 > 69
    back = joint;
    back.alpha = mild.alpha;
    eval_named(R, cases, ref, 'restore_alpha', back);
    back = joint; back.raw = mild.raw;
    eval_named(R, cases, ref, 'restore_raw', back);
    back = joint; back.beta = mild.beta;
    eval_named(R, cases, ref, 'restore_beta', back);
end
m = jsondecode(fileread(R.manifest));
m.status = 'COMPLETE';
m.raw_sources = {'raw/summary.csv','raw/per_frame.csv'};
write_manifest(R.manifest, m);
fprintf('JOINT_DONE %s\n', R.id);
end

function append_joint_index(root, R, status, decision)
fid = fopen(fullfile(root,'实验档案','02_汇总','运行索引.csv'),'a','n','UTF-8');
assert(fid>=0);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
rel = ['实验档案/01_运行记录/' R.id];
fprintf(fid,'%s,E2-M,1,,回归,%s,%s,%s/protocol.md,%s/manifest.json,\n', ...
    R.id, status, decision, rel, rel);
end

function fmt = mild_format()
widths = [24 14; 20 12; 16 12; 16 10; 16 10; 16 10];
stages = { ...
    {'input_y','input_H','input_nv','input_iv','frontend_gram','frontend_rhs','frontend_center','frontend_cov','frontend_variance','frontend_score','frontend_local'}
    {'A2_x','A2_w','A2_product','A2_acc','A2_out','alpha'}
    {'exp','sum_exp','prob','mu','var','residual','weighted','mix_a','mix_b','mix_output','lambda','ai'}
    {'A13_x','A13_w','A13_product','A13_acc','A13_out','raw','rate','damp_product_old','damp_product_new','damp_sum','beta'}
    {'A5_x','A5_w','A5_product','A5_acc','A5_out'}
    {'llr'}};
fmt = struct();
for s = 1:6
    for i = 1:numel(stages{s})
        fmt.(stages{s}{i}) = pair(widths(s,1), widths(s,2));
    end
end
end

function f = pair(W,F)
f = struct('W',W,'F',F);
end

function eval_named(R, cases, ref, name, fmt)
framePath = fullfile(R.raw,'per_frame.csv');
sumPath = fullfile(R.raw,'summary.csv');
newFile = ~exist(framePath,'file');
ff = fopen(framePath,'a','n','UTF-8');
sf = fopen(sumPath,'a','n','UTF-8');
assert(ff>=0 && sf>=0);
if newFile
    fprintf(ff,'name,case_index,backgroundSNR,floatErrors,candidateErrors,disagreements,became_wrong,became_correct,llrMax,saturations\n');
    fprintf(sf,'name,candidateErrors,disagreements,became_wrong,became_correct,llrMax,saturations,e0,e10,e20,e30,worstCase,worstLlr\n');
end
rows = zeros(numel(cases),6);
satWhere = struct();
for k = 1:numel(cases)
    [r,st] = run_quantized(cases(k).input, fmt);
    truth = cases(k).truth;
    fb = ref{k}.bits ~= truth;
    cb = r.bits ~= truth;
    wrong = nnz(~fb & cb);
    right = nnz(fb & ~cb);
    llr = max(abs(r.llr(:)-ref{k}.llr(:)));
    sat = sat_sum(st);
    satWhere = add_sat(satWhere, st);
    rows(k,:) = [cases(k).snrDB, nnz(cb), wrong+right, wrong, right, llr];
    fprintf(ff,'%s,%d,%.0f,%d,%d,%d,%d,%d,%.8g,%d\n', name, k, cases(k).snrDB, nnz(fb), nnz(cb), wrong+right, wrong, right, llr, sat);
end
fclose(ff);
snrs = rows(:,1);
e = zeros(1,4);
levels = [0 10 20 30];
for b = 1:4
    e(b) = sum(rows(snrs==levels(b),2));
end
[worstLlr, worstCase] = max(rows(:,6));
fprintf(sf,'%s,%d,%d,%d,%d,%.8g,%d,%d,%d,%d,%d,%d,%.8g\n', name, sum(rows(:,2)), sum(rows(:,3)), ...
    sum(rows(:,4)), sum(rows(:,5)), max(rows(:,6)), sat_total(satWhere), e(1), e(2), e(3), e(4), worstCase, worstLlr);
fclose(sf);
fid = fopen(fullfile(R.raw, [name '_饱和.csv']),'w','n','UTF-8');
assert(fid>=0);
fprintf(fid,'edge,saturations\n');
names = fieldnames(satWhere);
for i = 1:numel(names)
    if satWhere.(names{i})>0
        fprintf(fid,'%s,%d\n', names{i}, satWhere.(names{i}));
    end
end
fclose(fid);
fprintf('NAMED %s cand %d disagree %d bins %d/%d/%d/%d worst %d\n', name, sum(rows(:,2)), sum(rows(:,3)), e(1), e(2), e(3), e(4), worstCase);
end

function row = read_summary_row(path, name)
t = readtable(path,'TextType','string');
hit = t(t.name==name,:);
assert(height(hit)==1);
row.e0 = hit.e0(1); row.e10 = hit.e10(1); row.e20 = hit.e20(1); row.e30 = hit.e30(1);
row.disagreements = hit.disagreements(1);
end

function n = sat_sum(st)
n = 0;
names = fieldnames(st);
for i = 1:numel(names)
    a = st.(names{i});
    if isstruct(a) && isfield(a,'saturations'), n = n + a.saturations; end
end
end

function acc = add_sat(acc, st)
names = fieldnames(st);
for i = 1:numel(names)
    a = st.(names{i});
    if isstruct(a) && isfield(a,'saturations')
        if ~isfield(acc, names{i}), acc.(names{i}) = 0; end
        acc.(names{i}) = acc.(names{i}) + a.saturations;
    end
end
end

function n = sat_total(acc)
n = 0;
names = fieldnames(acc);
for i = 1:numel(names), n = n + acc.(names{i}); end
end
