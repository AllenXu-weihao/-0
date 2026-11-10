function run_batch5()
% Three archived widths on a new development sample. Does not call run_batch4.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
addpath(fullfile(root,'实验档案'));
addpath(fileparts(mfilename('fullpath')));
cd(root);
prevId = 'E2-M_grid64_s1105_a01_20261111_002256_tpc21d47e0_0131_4d3e_aae0_ac1aea8e91f1';
prev = fullfile(root,'实验档案','01_运行记录',prevId);
R = find_resume(root);
if isempty(R)
    R = new_run('E2-M','cross_sample_three',271111,1);
    write_protocol(R, prevId);
    mark_running(R, prevId);
    append_index(root, R, 'RUNNING', '待定', '');
end
fprintf('RUN %s\n', R.id);
if exist(fullfile(R.raw,'桥接失败.txt'),'file')
    error('BRIDGE_FAIL already recorded in %s', R.id);
end
if ~exist(fullfile(R.raw,'桥接通过.txt'),'file')
    bridge(R, prev);
end
devPath = fullfile(R.raw,'inputs.mat');
if ~exist(devPath,'file')
    cases = make_cases(512,271111);
    assert_dev(cases);
    save(devPath,'cases','-v7');
    write_input_note(R, devPath, cases);
else
    S = load(devPath,'cases');
    cases = S.cases;
    assert_dev(cases);
end
floatPath = fullfile(R.raw,'float_dev.mat');
if ~exist(floatPath,'file')
    fprintf('FLOAT %d\n', numel(cases));
    [floatBits,floatLlr] = run_float(cases);
    save(floatPath,'floatBits','floatLlr','-v7');
else
    F = load(floatPath,'floatBits','floatLlr');
    floatBits = F.floatBits;
    floatLlr = F.floatLlr;
end
specs = candidates();
for i = 1:numel(specs)
    matPath = fullfile(R.raw, ['cand_' specs(i).name '.mat']);
    if exist(matPath,'file')
        fprintf('SKIP %s\n', specs(i).name);
        continue
    end
    fprintf('CANDIDATE %s\n', specs(i).name);
    fmt = point_format(specs(i).Wa, specs(i).Wr, specs(i).Wb);
    rec = run_candidate(cases, floatBits, floatLlr, fmt, true);
    save(matPath,'rec','-v7');
    fprintf('CANDIDATE_DONE %s errors %d disagreements %d\n', specs(i).name, sum(rec.err), sum(rec.dis));
end
export_tables(R, cases);
write_wide_compare(R, cases);
trace_selected(R, cases, floatBits, floatLlr);
finish(R);
fprintf('BATCH5_DONE %s\n', R.id);
end

function R = find_resume(root)
R = [];
parent = fullfile(root,'实验档案','01_运行记录');
d = dir(fullfile(parent,'E2-M_cross_sample_three_*'));
if isempty(d), return; end
[~,ix] = max([d.datenum]);
folder = fullfile(parent, d(ix).name);
done = exist(fullfile(folder,'raw','trace','选择.txt'),'file') && exist(fullfile(folder,'raw','trace','透明.txt'),'file');
if done, return; end
R.id = d(ix).name;
R.dir = folder;
R.raw = fullfile(folder,'raw');
R.manifest = fullfile(folder,'manifest.json');
R.project = root;
fprintf('RESUME %s\n', R.id);
end

function write_protocol(R, prevId)
[~,hash] = system('git rev-parse --short HEAD');
fid = fopen(fullfile(R.dir,'protocol.md'),'w','n','UTF-8');
assert(fid>=0);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'# 单次实验协议\n\n冻结于查看本批新样本结果之前。\n\n');
fprintf(fid,'|项目|本次冻结值|\n|---|---|\n');
fprintf(fid,'|问题|第四批的最低成本点和两套宽配置，在新的开发样本上硬判和软值是否仍分得开|\n');
fprintf(fid,'|代码|开工时 HEAD %s。驱动 experiments/run_batch5.m。前次 %s。不调用 run_batch4|\n', strtrim(hash), prevId);
fprintf(fid,'|候选|W15_15_15、W21_19_17、W21_21_21。整数位 9/8/7，F=W-I。其余边用 mild。阻尼仍是运行时 0.3|\n');
fprintf(fid,'|桥接|种子 1105 的第四批输入。三候选的分档错数、两向翻转、逐帧最大 LLR 差按 %%.8g 对齐，饱和次数对齐。失败则停止|\n');
fprintf(fid,'|新样本|make_cases(512,271111)。四档各 512 帧、12288 bit，共 2048 帧。开工前 271111 只出现在第五批任务书。不使用 9110527|\n');
fprintf(fid,'|预算|三候选都跑完全部 2048 帧，不按中途结果停止。底表 6144 行|\n');
fprintf(fid,'|对照|同一帧上比较三候选。21/19/17 与 21/21/21 另做逐位硬判和 LLR|\n');
fprintf(fid,'|诊断帧|10 dB 取最小 case_index：任一候选相对 float 有硬判差，或两个宽配置彼此硬判不同。若没有，改取该档三候选相对 float 的最大绝对 LLR 差最大的帧。0 dB 优先取 W15 相对 float 有硬判差而两个宽配置没有的最小 case_index；否则取任一候选有硬判差的最小 case_index|\n');
fprintf(fid,'|门槛|69/480 只用于历史桥接。新样本图上的 8/480 是参考线，不是验收线|\n');
fprintf(fid,'|终止|三配置复测和诊断为止。不综合，不做独立样本正式非劣判定|\n');
end

function mark_running(R, prevId)
m = jsondecode(fileread(R.manifest));
m.status = 'RUNNING';
m.previous_run_id = prevId;
m.driver_revision = 'experiments/run_batch5.m';
m.entry_command = 'run_batch5';
m.dataset_role = '开发复测';
m.cases_path = '实验档案/01_运行记录/E0_baseline_s1105_a01_20261109_145449_tpcdb53181_74d4_4723_9e0e_efe47567de32/raw/stitch/inputs.mat';
m.reference = 'MIMO float; three widths bridged to batch 4 then rerun on make_cases(512,271111)';
m.candidate_ids = {'W15_15_15','W21_19_17','W21_21_21'};
m.matrix_arithmetic = 'mild stitch: ordered product then accumulator; only alpha raw beta overridden';
m.architecture = 'instrumented MATLAB, same quantizer as batch 4';
m.decision_rule = 'bridge must match batch 4 at printed precision; new sample is diagnostic and is not accepted by the 69/480 gate';
write_json(R.manifest, m);
end

function append_index(root, R, status, decision, report)
fid = fopen(fullfile(root,'实验档案','02_汇总','运行索引.csv'),'a','n','UTF-8');
assert(fid>=0);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
rel = ['实验档案/01_运行记录/' R.id];
fprintf(fid,'%s,E2-M,1,E2-M_grid64_s1105_a01_20261111_002256_tpc21d47e0_0131_4d3e_aae0_ac1aea8e91f1,%s,%s,%s,%s/protocol.md,%s/manifest.json,%s\n', ...
    R.id, '开发复测', status, decision, rel, rel, report);
end

function bridge(R, prev)
fprintf('BRIDGE\n');
manifest = jsondecode(fileread(fullfile(prev,'manifest.json')));
source = fullfile(R.project, manifest.cases_path);
S = load(source,'cases');
cases = S.cases;
assert(numel(cases)==80 && all([cases.seed]==1105));
old = readtable(fullfile(prev,'raw','per_frame.csv'),'TextType','string');
[floatBits,floatLlr] = run_float(cases);
for k = 1:numel(cases)
    hit = old(old.name=="W15_15_15" & old.case_index==k,:);
    got = nnz(floatBits(k,:) ~= cases(k).truth);
    if height(hit)~=1 || got~=hit.floatErrors
        fail_bridge(R, sprintf('float case %d', k));
    end
end
specs = candidates();
bf = fopen(fullfile(R.raw,'bridge_per_frame.csv'),'w','n','UTF-8');
assert(bf>=0);
fprintf(bf,'name,case_index,backgroundSNR,floatErrors,candidateErrors,disagreements,became_wrong,became_correct,llrMax,saturations\n');
for i = 1:numel(specs)
    fmt = point_format(specs(i).Wa, specs(i).Wr, specs(i).Wb);
    rec = run_candidate(cases, floatBits, floatLlr, fmt, false);
    for k = 1:numel(cases)
        hit = old(old.name==string(specs(i).name) & old.case_index==k,:);
        if height(hit)~=1 || rec.err(k)~=hit.candidateErrors || rec.dis(k)~=hit.disagreements || ...
                rec.wrong(k)~=hit.became_wrong || rec.right(k)~=hit.became_correct || ...
                rec.satFrame(k)~=hit.saturations || ~printed_same(rec.llrMax(k), hit.llrMax)
            fail_bridge(R, sprintf('%s case %d fresh err %d dis %d wrong %d right %d sat %d llr %.8g; archived err %d dis %d llr %.8g', ...
                specs(i).name, k, rec.err(k), rec.dis(k), rec.wrong(k), rec.right(k), rec.satFrame(k), rec.llrMax(k), ...
                hit.candidateErrors, hit.disagreements, hit.llrMax));
        end
        fprintf(bf,'%s,%d,%.0f,%d,%d,%d,%d,%d,%.8g,%d\n', specs(i).name, k, cases(k).snrDB, ...
            rec.floatErr(k), rec.err(k), rec.dis(k), rec.wrong(k), rec.right(k), rec.llrMax(k), rec.satFrame(k));
    end
    check_sat(R, rec, fullfile(prev,'raw','grid_sat.csv'), specs(i).name);
end
fclose(bf);
fid = fopen(fullfile(R.raw,'桥接通过.txt'),'w','n','UTF-8');
fprintf(fid,'三候选与第四批逐帧错数、两向翻转、打印精度内的最大 LLR 差和饱和次数一致。\n');
fclose(fid);
fprintf('BRIDGE_PASS\n');
end

function check_sat(R, rec, path, name)
old = readtable(path,'TextType','string');
old = old(old.name==string(name),:);
seen = struct();
for i = 1:height(old)
    edge = char(old.edge(i));
    seen.(edge) = true;
    got = 0;
    if isfield(rec.sat, edge), got = rec.sat.(edge); end
    if got ~= old.saturations(i)
        fail_bridge(R, sprintf('%s saturation %s fresh %d archived %d', name, edge, got, old.saturations(i)));
    end
end
names = fieldnames(rec.sat);
for i = 1:numel(names)
    if rec.sat.(names{i})>0 && ~isfield(seen, names{i})
        fail_bridge(R, sprintf('%s new saturation edge %s = %d', name, names{i}, rec.sat.(names{i})));
    end
end
end

function fail_bridge(R, message)
fid = fopen(fullfile(R.raw,'桥接失败.txt'),'w','n','UTF-8');
fprintf(fid,'%s\n', message);
fclose(fid);
m = jsondecode(fileread(R.manifest));
m.status = 'ERROR';
m.error = message;
write_json(R.manifest, m);
error('BRIDGE_FAIL %s', message);
end

function ok = printed_same(fresh, archived)
ok = strcmp(sprintf('%.8g', fresh), sprintf('%.8g', double(archived)));
end

function assert_dev(cases)
assert(numel(cases)==2048);
assert(all([cases.seed]==271111));
snr = [cases.snrDB];
for level = [0 10 20 30]
    assert(nnz(snr==level)==512, 'SNR %g count is %d', level, nnz(snr==level));
end
end

function write_input_note(R, path, cases)
fid = fopen(fullfile(R.raw,'输入摘要.txt'),'w','n','UTF-8');
assert(fid>=0);
fprintf(fid,'make_cases(512,271111)\n');
fprintf(fid,'frames 2048\n');
fprintf(fid,'per SNR 512\n');
fprintf(fid,'bits per SNR 12288\n');
fprintf(fid,'sha256 %s\n', sha256_file(path));
fprintf(fid,'seed 271111 was not a historical result seed at protocol time.\n');
fclose(fid);
assert_dev(cases);
end

function [bits,llr] = run_float(cases)
n = numel(cases);
bits = false(n,24);
llr = zeros(n,24);
for k = 1:n
    ref = MIMO(cases(k).input,'float');
    bits(k,:) = ref.bits(:).';
    llr(k,:) = ref.llr(:).';
    if mod(k,256)==0, fprintf('  float %d/%d\n', k, n); end
end
end

function rec = run_candidate(cases, floatBits, floatLlr, fmt, recordSat)
n = numel(cases);
rec.snr = zeros(n,1);
rec.llr = zeros(n,24);
rec.bits = false(n,24);
rec.err = zeros(n,1);
rec.floatErr = zeros(n,1);
rec.wrong = zeros(n,1);
rec.right = zeros(n,1);
rec.dis = zeros(n,1);
rec.llrMax = zeros(n,1);
rec.satFrame = zeros(n,1);
rec.sat = struct();
rec.elements = struct();
rec.firstCase = struct();
rec.firstIndex = struct();
rec.hitFrames = struct();
opts = struct('recordSaturation',recordSat);
for k = 1:n
    [r,st] = run_quantized(cases(k).input, fmt, opts);
    truth = cases(k).truth(:).';
    cb = r.bits(:).';
    fb = floatBits(k,:);
    if ~all(isfinite(r.llr(:)))
        error('Nonfinite LLR at case %d', k);
    end
    rec.snr(k) = cases(k).snrDB;
    rec.llr(k,:) = r.llr(:).';
    rec.bits(k,:) = cb;
    floatWrong = fb ~= truth;
    candWrong = cb ~= truth;
    rec.floatErr(k) = nnz(floatWrong);
    rec.err(k) = nnz(candWrong);
    rec.wrong(k) = nnz(~floatWrong & candWrong);
    rec.right(k) = nnz(floatWrong & ~candWrong);
    rec.dis(k) = nnz(cb ~= fb);
    rec.llrMax(k) = max(abs(rec.llr(k,:) - floatLlr(k,:)));
    if rec.dis(k) ~= rec.wrong(k)+rec.right(k)
        error('Flip partition failed at case %d', k);
    end
    satFrame = edge_sat(st);
    rec.satFrame(k) = sat_total(satFrame);
    rec.sat = add_counts(rec.sat, satFrame);
    rec.elements = add_counts(rec.elements, edge_elements(st));
    if recordSat
        rec = note_position(rec, st, k);
    end
    if mod(k,256)==0, fprintf('  frame %d/%d\n', k, n); end
end
end

function rec = note_position(rec, st, k)
names = fieldnames(st);
for i = 1:numel(names)
    a = st.(names{i});
    if ~isstruct(a) || ~isfield(a,'saturations') || a.saturations==0
        continue
    end
    edge = names{i};
    if ~isfield(rec.hitFrames, edge), rec.hitFrames.(edge) = 0; end
    rec.hitFrames.(edge) = rec.hitFrames.(edge) + 1;
    if ~isfield(rec.firstCase, edge)
        rec.firstCase.(edge) = k;
        rec.firstIndex.(edge) = 0;
        if isfield(a,'firstIndex'), rec.firstIndex.(edge) = a.firstIndex; end
    end
end
end

function export_tables(R, cases)
specs = candidates();
ff = fopen(fullfile(R.raw,'per_frame.csv'),'w','n','UTF-8');
lf = fopen(fullfile(R.raw,'llr_bits.csv'),'w','n','UTF-8');
sf = fopen(fullfile(R.raw,'饱和.csv'),'w','n','UTF-8');
bf = fopen(fullfile(R.raw,'分档.csv'),'w','n','UTF-8');
assert(ff>=0 && lf>=0 && sf>=0 && bf>=0);
fprintf(ff,'name,case_index,backgroundSNR,floatErrors,candidateErrors,disagreements,became_wrong,became_correct,llrMax,saturations\n');
fprintf(lf,'name,case_index,bit,llr,hard,truth,float_llr,float_hard\n');
fprintf(sf,'name,edge,saturations,elements,frames,first_case,first_component\n');
fprintf(bf,'name,snr,frames,bits,candidateErrors,floatErrors,became_wrong,became_correct,disagreements,frames_with_disagreement,llrMax,saturations\n');
F = load(fullfile(R.raw,'float_dev.mat'),'floatBits','floatLlr');
for i = 1:numel(specs)
    S = load(fullfile(R.raw, ['cand_' specs(i).name '.mat']),'rec');
    rec = S.rec;
    assert(numel(rec.err)==numel(cases));
    for k = 1:numel(cases)
        fprintf(ff,'%s,%d,%.0f,%d,%d,%d,%d,%d,%.8g,%d\n', specs(i).name, k, rec.snr(k), ...
            rec.floatErr(k), rec.err(k), rec.dis(k), rec.wrong(k), rec.right(k), rec.llrMax(k), rec.satFrame(k));
        truth = cases(k).truth(:).';
        for b = 1:24
            fprintf(lf,'%s,%d,%d,%.8g,%d,%d,%.8g,%d\n', specs(i).name, k, b, rec.llr(k,b), rec.bits(k,b), ...
                truth(b), F.floatLlr(k,b), F.floatBits(k,b));
        end
    end
    names = fieldnames(rec.sat);
    for t = 1:numel(names)
        if rec.sat.(names{t})<=0, continue; end
        frames = 0; firstCase = 0; firstIndex = 0;
        if isfield(rec.hitFrames, names{t}), frames = rec.hitFrames.(names{t}); end
        if isfield(rec.firstCase, names{t}), firstCase = rec.firstCase.(names{t}); end
        if isfield(rec.firstIndex, names{t}), firstIndex = rec.firstIndex.(names{t}); end
        el = 0;
        if isfield(rec.elements, names{t}), el = rec.elements.(names{t}); end
        fprintf(sf,'%s,%s,%d,%d,%d,%d,%d\n', specs(i).name, names{t}, rec.sat.(names{t}), el, frames, firstCase, firstIndex);
    end
    for level = [0 10 20 30]
        mask = rec.snr==level;
        fprintf(bf,'%s,%.0f,%d,%d,%d,%d,%d,%d,%d,%d,%.8g,%d\n', specs(i).name, level, nnz(mask), nnz(mask)*24, ...
            sum(rec.err(mask)), sum(rec.floatErr(mask)), sum(rec.wrong(mask)), sum(rec.right(mask)), ...
            sum(rec.dis(mask)), nnz(rec.dis(mask)>0), max(rec.llrMax(mask)), sum(rec.satFrame(mask)));
    end
end
fclose(ff); fclose(lf); fclose(sf); fclose(bf);
end

function write_wide_compare(R, cases)
A = load(fullfile(R.raw,'cand_W21_19_17.mat'),'rec');
B = load(fullfile(R.raw,'cand_W21_21_21.mat'),'rec');
fid = fopen(fullfile(R.raw,'宽点对照.csv'),'w','n','UTF-8');
assert(fid>=0);
fprintf(fid,'snr,frames,bits,hard_differences,frames_with_hard_difference,max_abs_llr\n');
snr = [cases.snrDB].';
for level = [0 10 20 30 -1]
    if level<0
        mask = true(numel(cases),1);
        label = -1;
    else
        mask = snr==level;
        label = level;
    end
    hard = A.rec.bits(mask,:) ~= B.rec.bits(mask,:);
    gap = max(abs(A.rec.llr(mask,:) - B.rec.llr(mask,:)), [], 'all');
    frameHard = any(hard,2);
    fprintf(fid,'%.0f,%d,%d,%d,%d,%.8g\n', label, nnz(mask), nnz(mask)*24, nnz(hard), nnz(frameHard), gap);
end
fclose(fid);
end

function trace_selected(R, cases, floatBits, floatLlr)
specs = candidates();
pack = struct();
for i = 1:numel(specs)
    S = load(fullfile(R.raw, ['cand_' specs(i).name '.mat']),'rec');
    pack.(specs(i).name) = S.rec;
end
snr = [cases.snrDB].';
ten = find(snr==10);
zero = find(snr==0);
tenFlip = [];
for k = ten(:).'
    if frame_flips(pack, k)
        tenFlip = k;
        break
    end
end
tenRule = '最小 case_index 的 10 dB 翻转帧：任一候选相对 float 硬判不同，或 W21_19_17 与 W21_21_21 硬判不同。';
if isempty(tenFlip)
    score = max([pack.W15_15_15.llrMax(ten), pack.W21_19_17.llrMax(ten), pack.W21_21_21.llrMax(ten)], [], 2);
    [~,ix] = max(score);
    tenFlip = ten(ix);
    tenRule = '10 dB 没有硬判翻转。改为该档三候选相对 float 的最大 |ΔLLR| 最大的帧。';
end
zeroPrefer = [];
for k = zero(:).'
    if pack.W15_15_15.dis(k)>0 && pack.W21_19_17.dis(k)==0 && pack.W21_21_21.dis(k)==0
        zeroPrefer = k;
        break
    end
end
zeroRule = '0 dB 上 W15_15_15 相对 float 有硬判差、两个宽配置没有的最小 case_index。';
if isempty(zeroPrefer)
    for k = zero(:).'
        if pack.W15_15_15.dis(k)>0 || pack.W21_19_17.dis(k)>0 || pack.W21_21_21.dis(k)>0
            zeroPrefer = k;
            zeroRule = '0 dB 没有“只窄点翻转”的帧。改为任一候选相对 float 有硬判差的最小 case_index。';
            break
        end
    end
end
if isempty(zeroPrefer)
    score = max([pack.W15_15_15.llrMax(zero), pack.W21_19_17.llrMax(zero), pack.W21_21_21.llrMax(zero)], [], 2);
    [~,ix] = max(score);
    zeroPrefer = zero(ix);
    zeroRule = '0 dB 没有硬判翻转。改为该档三候选相对 float 的最大 |ΔLLR| 最大的帧。';
end
folder = fullfile(R.raw,'trace');
if ~exist(folder,'dir'), mkdir(folder); end
note = fopen(fullfile(folder,'透明.txt'),'w','n','UTF-8');
sumFid = fopen(fullfile(folder,'idx摘要.csv'),'w','n','UTF-8');
fprintf(sumFid,'case,format,round,portRounds,idxDiffPorts,maxAbsRawDiff,maxAbsBetaBefore,maxAbsBetaAfter\n');
for k = [tenFlip zeroPrefer]
    [floatResult,floatStats] = run_quantized(cases(k).input, struct(), struct('trace',true));
    floatGap = max(abs(floatResult.llr(:).' - floatLlr(k,:)));
    floatBitDiff = nnz(floatResult.bits(:).' ~= floatBits(k,:));
    fprintf(note,'case %d float trace LLR gap %.8g hard diffs %d\n', k, floatGap, floatBitDiff);
    dump = fopen(fullfile(folder, sprintf('帧_%gdB_case%d.csv', cases(k).snrDB, k)),'w','n','UTF-8');
    fprintf(dump,'name,item,round,values\n');
    write_vector(dump, 'float', 'llr', 0, floatResult.llr);
    write_vector(dump, 'float', 'bits', 0, floatResult.bits);
    write_round(dump, sumFid, k, 'float', floatStats.trace, floatStats.trace);
    for i = 1:numel(specs)
        fmt = point_format(specs(i).Wa, specs(i).Wr, specs(i).Wb);
        [r,st] = run_quantized(cases(k).input, fmt, struct('trace',true,'recordSaturation',false));
        stored = pack.(specs(i).name);
        gap = max(abs(r.llr(:).' - stored.llr(k,:)));
        bitDiff = nnz(r.bits(:).' ~= stored.bits(k,:));
        fprintf(note,'case %d %s trace versus stored LLR gap %.8g hard diffs %d\n', k, specs(i).name, gap, bitDiff);
        write_vector(dump, specs(i).name, 'llr', 0, r.llr);
        write_vector(dump, specs(i).name, 'bits', 0, r.bits);
        write_round(dump, sumFid, k, specs(i).name, floatStats.trace, st.trace);
    end
    fclose(dump);
end
fclose(note);
fclose(sumFid);
fid = fopen(fullfile(folder,'选择.txt'),'w','n','UTF-8');
fprintf(fid,'10 dB case %d。%s\n', tenFlip, tenRule);
fprintf(fid,'0 dB case %d。%s\n', zeroPrefer, zeroRule);
fclose(fid);
end

function tf = frame_flips(pack, k)
tf = pack.W15_15_15.dis(k)>0 || pack.W21_19_17.dis(k)>0 || pack.W21_21_21.dis(k)>0 || ...
    any(pack.W21_19_17.bits(k,:) ~= pack.W21_21_21.bits(k,:));
end

function write_round(dump, sumFid, caseIndex, name, ref, traced)
if ~isstruct(traced) || ~isfield(traced,'round'), return; end
for roundIndex = 1:3
    got = traced.round(roundIndex);
    base = ref.round(roundIndex);
    ports = size(got.idx,1);
    diffPorts = 0;
    for p = 1:ports
        if any(got.idx(p,:) ~= base.idx(p,:)), diffPorts = diffPorts+1; end
    end
    rawGap = max(abs(got.raw(:)-base.raw(:)));
    beforeGap = max(abs(got.betaBefore(:)-base.betaBefore(:)));
    afterGap = max(abs(got.betaAfter(:)-base.betaAfter(:)));
    fprintf(sumFid,'%d,%s,%d,%d,%d,%.8g,%.8g,%.8g\n', caseIndex, name, roundIndex, ports, diffPorts, rawGap, beforeGap, afterGap);
    write_vector(dump, name, 'idx', roundIndex, got.idx);
    write_vector(dump, name, 'raw', roundIndex, got.raw);
    write_vector(dump, name, 'betaBefore', roundIndex, got.betaBefore);
    write_vector(dump, name, 'betaAfter', roundIndex, got.betaAfter);
end
if isfield(traced,'readout')
    write_vector(dump, name, 'max0', 0, traced.readout.max0);
    write_vector(dump, name, 'max1', 0, traced.readout.max1);
    write_vector(dump, name, 'readout_llr', 0, traced.readout.llr);
end
end

function write_vector(fid, name, item, roundIndex, value)
fprintf(fid,'%s,%s,%d', name, item, roundIndex);
fprintf(fid,',%.8g', double(value(:)));
fprintf(fid,'\n');
end

function finish(R)
m = jsondecode(fileread(R.manifest));
m.status = 'COMPLETE';
m.error = '';
m.cases_path = 'raw/inputs.mat';
m.raw_sources = {'raw/per_frame.csv','raw/llr_bits.csv','raw/分档.csv','raw/饱和.csv','raw/宽点对照.csv','raw/bridge_per_frame.csv','raw/输入摘要.txt'};
m.driver_revision = 'experiments/run_batch5.m';
write_json(R.manifest, m);
end

function specs = candidates()
specs = struct('name',{'W15_15_15','W21_19_17','W21_21_21'},'Wa',{15,21,21},'Wr',{15,19,21},'Wb',{15,17,21});
end

function fmt = point_format(Wa, Wr, Wb)
fmt = mild_format();
fmt.alpha = pair(Wa, Wa-9);
fmt.raw = pair(Wr, Wr-8);
fmt.beta = pair(Wb, Wb-7);
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

function sat = edge_sat(st)
sat = struct();
names = fieldnames(st);
for i = 1:numel(names)
    a = st.(names{i});
    if isstruct(a) && isfield(a,'saturations')
        sat.(names{i}) = a.saturations;
    end
end
end

function el = edge_elements(st)
el = struct();
names = fieldnames(st);
for i = 1:numel(names)
    a = st.(names{i});
    if isstruct(a) && isfield(a,'elements')
        el.(names{i}) = a.elements;
    end
end
end

function acc = add_counts(acc, extra)
names = fieldnames(extra);
for i = 1:numel(names)
    if ~isfield(acc, names{i}), acc.(names{i}) = 0; end
    acc.(names{i}) = acc.(names{i}) + extra.(names{i});
end
end

function n = sat_total(acc)
n = 0;
names = fieldnames(acc);
for i = 1:numel(names), n = n + acc.(names{i}); end
end

function write_json(path, m)
fid = fopen(path,'w','n','UTF-8');
assert(fid>=0);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n', jsonencode(m));
end

function value = sha256_file(path)
fid = fopen(path,'rb');
assert(fid>=0);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
md = java.security.MessageDigest.getInstance('SHA-256');
while ~feof(fid)
    chunk = fread(fid,65536,'*uint8');
    if ~isempty(chunk), md.update(typecast(chunk,'int8')); end
end
bytes = typecast(md.digest(),'uint8');
value = lower(reshape(dec2hex(bytes,2).',1,[]));
end
