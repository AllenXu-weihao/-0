function run_batch4()
% 64-point alpha/raw/beta grid. Protocol is written before new results are read.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
addpath(fullfile(root,'实验档案'));
addpath(fileparts(mfilename('fullpath')));
cd(root);
prevId = 'E2-M_joint_start_s1105_a01_20261110_235305_tpdfec58fe_a167_473e_b30a_5a869968eca5';
prev = fullfile(root,'实验档案','01_运行记录',prevId);
prevManifest = jsondecode(fileread(fullfile(prev,'manifest.json')));
source = fullfile(root, prevManifest.cases_path);
S = load(source,'cases');
cases = S.cases;
assert(numel(cases)==80 && all([cases.seed]==1105));
R = find_resume(root);
if isempty(R)
    R = new_run('E2-M','grid64',1105,1);
    write_protocol(R, prevId, source);
    mark_running(R, prevManifest.cases_path);
    append_index(root, R, 'RUNNING', '待定');
end
fprintf('RUN %s\n', R.id);
if ~exist(fullfile(R.raw,'桥接通过.txt'),'file')
    bridge(R, cases, prev);
end
widths = [15 17 19 21];
done = done_names(fullfile(R.raw,'grid_summary.csv'));
[~,hash] = system('git rev-parse --short HEAD');
hash = strtrim(hash);
nDone = numel(done);
for ia = 1:4
    for ir = 1:4
        for ib = 1:4
            Wa = widths(ia); Wr = widths(ir); Wb = widths(ib);
            name = sprintf('W%d_%d_%d', Wa, Wr, Wb);
            if any(strcmp(done, name))
                continue
            end
            if Wa==21 && Wr==21 && Wb==21
                copy_bridge_point(R, 'joint_W21', name, Wa, Wr, Wb);
            else
                fmt = point_format(Wa, Wr, Wb);
                ref = load_ref(fullfile(R.raw,'float_ref.mat'));
                rec = evaluate(cases, ref, fmt);
                write_point(R, name, Wa, Wr, Wb, rec);
            end
            nDone = nDone + 1;
            fprintf('GRID %d/64 %s\n', nDone, name);
        end
    end
end
write_ties(R);
trace_selected(R, cases);
finish(R, hash);
fprintf('BATCH4_DONE %s\n', R.id);
end

function R = find_resume(root)
R = [];
parent = fullfile(root,'实验档案','01_运行记录');
d = dir(fullfile(parent,'E2-M_grid64_*'));
if isempty(d), return; end
[~,ix] = max([d.datenum]);
folder = fullfile(parent, d(ix).name);
sumPath = fullfile(folder,'raw','grid_summary.csv');
if ~exist(sumPath,'file'), return; end
names = done_names(sumPath);
if numel(names) >= 64, return; end
R.id = d(ix).name;
R.dir = folder;
R.raw = fullfile(folder,'raw');
R.manifest = fullfile(folder,'manifest.json');
R.project = root;
fprintf('RESUME %s with %d points\n', R.id, numel(names));
end

function write_protocol(R, prevId, source)
[~,hash] = system('git rev-parse --short HEAD');
fid = fopen(fullfile(R.dir,'protocol.md'),'w','n','UTF-8');
assert(fid>=0);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'# 单次实验协议\n\n冻结于查看本网格新结果之前。\n\n');
fprintf(fid,'|项目|本次冻结值|\n|---|---|\n');
fprintf(fid,'|问题|允许 alpha、raw、beta 各选总宽，比三条边共用一个总宽，能少多少逻辑搬运|\n');
fprintf(fid,'|代码|开工时 HEAD %s。驱动 experiments/run_batch4.m。前次 %s|\n', strtrim(hash), prevId);
fprintf(fid,'|输入|%s 。80 帧，种子 1105，每帧 24 bit|\n', strrep(source,'\','/'));
fprintf(fid,'|算术|从 mild 全套格式出发，只覆盖三条边。有序乘积后累加。阻尼 0.3。三轮|\n');
fprintf(fid,'|网格|(Wα,Wraw,Wβ) 取 {15,17,19,21} 的立方。整数位含符号固定 (9,8,7)，F 分别为 W-9、W-8、W-7|\n');
fprintf(fid,'|可行|80 帧齐全、输出有限，且 10 dB 候选错 ≤69/480。标固定回归可行。硬判差另行记录，饱和不单独淘汰|\n');
fprintf(fid,'|成本|C=1080*Wα+1080*Wraw+1800*Wβ，单位 bit/向量。U 是四条对角线，M 是全部 64 点|\n');
fprintf(fid,'|终止|64 点核验完。不跑 E3-H，不开 E4，不测 pJ/bit|\n');
end

function mark_running(R, casesPath)
m = jsondecode(fileread(R.manifest));
m.status = 'RUNNING';
m.previous_run_id = 'E2-M_joint_start_s1105_a01_20261110_235305_tpdfec58fe_a167_473e_b30a_5a869968eca5';
m.driver_revision = 'experiments/run_batch4.m';
m.entry_command = 'run_batch4';
m.dataset_role = '回归';
m.cases_path = strrep(casesPath,'\','/');
m.reference = 'MIMO float; bridge against third-batch mild and joint_W21';
m.candidate_ids = {'grid64'};
m.matrix_arithmetic = 'mild stitch: ordered product then accumulator when those formats exist';
m.architecture = 'instrumented MATLAB, one mild dictionary, three edges overridden';
m.decision_rule = 'feasible if 80 frames finite and 10 dB candidate errors <= 69/480; cost C=1080*Wa+1080*Wr+1800*Wb';
write_json(R.manifest, m);
end

function append_index(root, R, status, decision)
fid = fopen(fullfile(root,'实验档案','02_汇总','运行索引.csv'),'a','n','UTF-8');
assert(fid>=0);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
rel = ['实验档案/01_运行记录/' R.id];
fprintf(fid,'%s,E2-M,1,E2-M_joint_start_s1105_a01_20261110_235305_tpdfec58fe_a167_473e_b30a_5a869968eca5,回归,%s,%s,%s/protocol.md,%s/manifest.json,\n', ...
    R.id, status, decision, rel, rel);
end

function bridge(R, cases, prev)
fprintf('BRIDGE\n');
ref = cell(numel(cases),1);
for k = 1:numel(cases)
    ref{k} = MIMO(cases(k).input,'float');
end
save(fullfile(R.raw,'float_ref.mat'),'ref');
old = readtable(fullfile(prev,'raw','per_frame.csv'),'TextType','string');
for k = 1:numel(cases)
    hit = old(old.name=="mild" & old.case_index==k,:);
    assert(height(hit)==1);
    got = nnz(ref{k}.bits ~= cases(k).truth);
    if got ~= hit.floatErrors
        fail_bridge(R, sprintf('float case %d errors %d, archived %d', k, got, hit.floatErrors));
    end
end
mildRec = evaluate(cases, ref, mild_format());
jointFmt = mild_format();
jointFmt.alpha = pair(21,12);
jointFmt.raw = pair(21,13);
jointFmt.beta = pair(21,14);
jointRec = evaluate(cases, ref, jointFmt);
compare_named(R, old, mildRec, 'mild', fullfile(prev,'raw','mild_饱和.csv'));
compare_named(R, old, jointRec, 'joint_W21', fullfile(prev,'raw','joint_W21_饱和.csv'));
save(fullfile(R.raw,'bridge_joint.mat'),'jointRec');
fid = fopen(fullfile(R.raw,'桥接通过.txt'),'w','n','UTF-8');
fprintf(fid,'float、mild、joint_W21 的逐帧错数、两向翻转、最大 LLR 差和饱和与第三批一致。\n');
fclose(fid);
fprintf('BRIDGE_PASS\n');
end

function compare_named(R, old, rec, name, satPath)
if ~isempty(rec.err)
    fail_bridge(R, sprintf('%s replay failed: %s', name, rec.err));
end
for k = 1:numel(rec.snr)
    hit = old(old.name==string(name) & old.case_index==k,:);
    assert(height(hit)==1);
    llrGap = abs(rec.llr(k) - double(hit.llrMax));
    if rec.candErr(k)~=hit.candidateErrors || rec.disagree(k)~=hit.disagreements || ...
            rec.wrong(k)~=hit.became_wrong || rec.right(k)~=hit.became_correct || ...
            rec.satFrame(k)~=hit.saturations || llrGap>1e-6
        fail_bridge(R, sprintf('%s case %d cand %d/%d dis %d/%d wrong %d/%d right %d/%d sat %d/%d llr %.8g/%.8g', ...
            name, k, rec.candErr(k), hit.candidateErrors, rec.disagree(k), hit.disagreements, ...
            rec.wrong(k), hit.became_wrong, rec.right(k), hit.became_correct, ...
            rec.satFrame(k), hit.saturations, rec.llr(k), hit.llrMax));
    end
end
check_sat(R, rec.sat, satPath, name);
end

function check_sat(R, sat, path, name)
old = readtable(path,'TextType','string');
seen = struct();
for i = 1:height(old)
    edge = char(old.edge(i));
    seen.(edge) = true;
    got = 0;
    if isfield(sat, edge), got = sat.(edge); end
    if got ~= old.saturations(i)
        fail_bridge(R, sprintf('%s saturation %s fresh %d archived %d', name, edge, got, old.saturations(i)));
    end
end
names = fieldnames(sat);
for i = 1:numel(names)
    if sat.(names{i})>0 && ~isfield(seen, names{i})
        fail_bridge(R, sprintf('%s new saturation edge %s = %d', name, names{i}, sat.(names{i})));
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

function copy_bridge_point(R, sourceName, name, Wa, Wr, Wb)
bridge = load(fullfile(R.raw,'bridge_joint.mat'),'jointRec');
rec = bridge.jointRec;
if ~strcmp(sourceName,'joint_W21')
    error('Only joint_W21 is the reused (21,21,21) cell.');
end
write_point(R, name, Wa, Wr, Wb, rec);
end

function write_point(R, name, Wa, Wr, Wb, rec)
Fa = Wa-9; Fr = Wr-8; Fb = Wb-7;
C = 1080*Wa + 1080*Wr + 1800*Wb;
sumPath = fullfile(R.raw,'grid_summary.csv');
framePath = fullfile(R.raw,'per_frame.csv');
satPath = fullfile(R.raw,'grid_sat.csv');
newSum = ~exist(sumPath,'file');
sf = fopen(sumPath,'a','n','UTF-8');
ff = fopen(framePath,'a','n','UTF-8');
af = fopen(satPath,'a','n','UTF-8');
assert(sf>=0 && ff>=0 && af>=0);
if newSum
    fprintf(sf,'name,Wa,Fa,Wr,Fr,Wb,Fb,frames,e0,e10,e20,e30,float0,float10,float20,float30,became_wrong,became_correct,disagreements,llrMax,sat_total,C,status\n');
    fprintf(ff,'name,case_index,backgroundSNR,floatErrors,candidateErrors,disagreements,became_wrong,became_correct,llrMax,saturations\n');
    fprintf(af,'name,edge,saturations,elements\n');
end
if ~isempty(rec.err) || numel(rec.snr)~=80 || any(~isfinite(rec.llr))
    fprintf(sf,'%s,%d,%d,%d,%d,%d,%d,0,nan,nan,nan,nan,nan,nan,nan,nan,nan,nan,nan,nan,nan,%d,ERROR\n', ...
        name, Wa, Fa, Wr, Fr, Wb, Fb, C);
    fprintf('POINT_ERROR %s %s\n', name, rec.err);
else
    e = bin_sum(rec.snr, rec.candErr);
    f = bin_sum(rec.snr, rec.floatErr);
    status = '未通过10dB回归';
    if e(2) <= 69, status = '固定回归可行'; end
    fprintf(sf,'%s,%d,%d,%d,%d,%d,%d,80,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%.8g,%d,%d,%s\n', ...
        name, Wa, Fa, Wr, Fr, Wb, Fb, e(1), e(2), e(3), e(4), f(1), f(2), f(3), f(4), ...
        sum(rec.wrong), sum(rec.right), sum(rec.disagree), max(rec.llr), sat_total(rec.sat), C, status);
    for k = 1:80
        fprintf(ff,'%s,%d,%.0f,%d,%d,%d,%d,%d,%.8g,%d\n', name, k, rec.snr(k), rec.floatErr(k), ...
            rec.candErr(k), rec.disagree(k), rec.wrong(k), rec.right(k), rec.llr(k), rec.satFrame(k));
    end
    names = fieldnames(rec.sat);
    for i = 1:numel(names)
        if rec.sat.(names{i})>0
            el = 0;
            if isfield(rec.elements, names{i}), el = rec.elements.(names{i}); end
            fprintf(af,'%s,%s,%d,%d\n', name, names{i}, rec.sat.(names{i}), el);
        end
    end
end
fclose(sf); fclose(ff); fclose(af);
end

function e = bin_sum(snr, values)
e = zeros(1,4);
levels = [0 10 20 30];
for b = 1:4
    e(b) = sum(values(snr==levels(b)));
end
end

function names = done_names(path)
names = {};
if ~exist(path,'file'), return; end
t = readtable(path,'TextType','string');
if isempty(t), return; end
names = cellstr(t.name);
end

function ref = load_ref(path)
S = load(path,'ref');
ref = S.ref;
end

function rec = evaluate(cases, ref, fmt)
n = numel(cases);
rec.snr = zeros(n,1);
rec.floatErr = zeros(n,1);
rec.candErr = zeros(n,1);
rec.disagree = zeros(n,1);
rec.wrong = zeros(n,1);
rec.right = zeros(n,1);
rec.llr = zeros(n,1);
rec.satFrame = zeros(n,1);
rec.sat = struct();
rec.elements = struct();
rec.err = '';
try
    for k = 1:n
        [r,st] = run_quantized(cases(k).input, fmt);
        truth = cases(k).truth;
        fb = ref{k}.bits ~= truth;
        cb = r.bits ~= truth;
        rec.snr(k) = cases(k).snrDB;
        rec.floatErr(k) = nnz(fb);
        rec.candErr(k) = nnz(cb);
        rec.wrong(k) = nnz(~fb & cb);
        rec.right(k) = nnz(fb & ~cb);
        rec.disagree(k) = rec.wrong(k) + rec.right(k);
        rec.llr(k) = max(abs(r.llr(:)-ref{k}.llr(:)));
        rec.satFrame(k) = sat_total(edge_sat(st));
        rec.sat = add_counts(rec.sat, edge_sat(st));
        rec.elements = add_counts(rec.elements, edge_elements(st));
    end
catch err
    rec.err = err.message;
end
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

function write_ties(R)
t = readtable(fullfile(R.raw,'grid_summary.csv'),'TextType','string');
ok = t.status=="固定回归可行";
fid = fopen(fullfile(R.raw,'并列.csv'),'w','n','UTF-8');
assert(fid>=0);
fprintf(fid,'group,name,C,e10,disagreements,llrMax\n');
write_group(fid, t(ok & t.Wa==t.Wr & t.Wr==t.Wb,:), 'U');
write_group(fid, t(ok,:), 'M');
fclose(fid);
end

function write_group(fid, rows, group)
if isempty(rows)
    fprintf(fid,'%s,NONE,nan,nan,nan,nan\n', group);
    return
end
best = min(rows.C);
hit = rows(rows.C==best,:);
for i = 1:height(hit)
    fprintf(fid,'%s,%s,%d,%d,%d,%.8g\n', group, hit.name(i), hit.C(i), hit.e10(i), hit.disagreements(i), hit.llrMax(i));
end
end

function trace_selected(R, cases)
t = readtable(fullfile(R.raw,'grid_summary.csv'),'TextType','string');
ok = t.status=="固定回归可行";
uRows = t(ok & t.Wa==t.Wr & t.Wr==t.Wb,:);
mRows = t(ok,:);
targets = unique([pick_rep(uRows); pick_rep(mRows)]);
targets = targets(strlength(targets)>0);
failNear = neighbor_fail(t, pick_rep(mRows));
if strlength(failNear)>0
    targets = unique([targets; failNear]);
end
folder = fullfile(R.raw,'trace');
if ~exist(folder,'dir'), mkdir(folder); end
fid = fopen(fullfile(folder,'选择.txt'),'w','n','UTF-8');
fprintf(fid,'代表与相邻越界：%s\n', strjoin(cellstr(targets), ' '));
if strlength(failNear)==0
    fprintf(fid,'最佳逐边配置在本网格的相邻格里没有未通过 10 dB 的点。覆盖范围是总宽 15、17、19、21。\n');
end
fclose(fid);
if isempty(targets), return; end
ref = load_ref(fullfile(R.raw,'float_ref.mat'));
floatPack = run_pack(cases, struct(), true);
off = run_pack(cases, struct(), false);
gap = pack_gap(floatPack, off);
note = fopen(fullfile(folder,'透明.txt'),'w','n','UTF-8');
fprintf(note,'不量化时开 trace 与关 trace 的最大 LLR 差 %.8g。\n', gap);
sumFid = fopen(fullfile(folder,'idx摘要.csv'),'w','n','UTF-8');
fprintf(sumFid,'format,round,portRounds,idxDiffPorts,maxAbsBetaDiff,firstCase,firstRound,firstPort,firstSlot,hardCase\n');
for i = 1:numel(targets)
    name = char(targets(i));
    parts = sscanf(name, 'W%d_%d_%d');
    fmt = point_format(parts(1), parts(2), parts(3));
    qOff = run_pack(cases, fmt, false);
    qOn = run_pack(cases, fmt, true);
    fprintf(note,'%s 开 trace 与关 trace 的最大 LLR 差 %.8g，硬判不同帧数 %d。\n', ...
        name, pack_gap(qOn,qOff), pack_bit_frames(qOn,qOff));
    write_trace_row(sumFid, name, floatPack, qOn);
end
fclose(note);
fclose(sumFid);
end

function name = pick_rep(rows)
name = "";
if isempty(rows), return; end
best = min(rows.C);
hit = rows(rows.C==best,:);
hit = sortrows(hit, {'e10','disagreements','llrMax'});
name = hit.name(1);
end

function name = neighbor_fail(t, origin)
name = "";
if strlength(origin)==0, return; end
parts = sscanf(char(origin), 'W%d_%d_%d');
widths = [15 17 19 21];
bestErr = inf;
for d = 1:3
    for step = [-2 2]
        trial = parts;
        trial(d) = trial(d) + step;
        if ~any(trial(d)==widths), continue; end
        id = sprintf('W%d_%d_%d', trial(1), trial(2), trial(3));
        hit = t(t.name==string(id),:);
        if isempty(hit) || hit.status=="固定回归可行", continue; end
        if hit.e10 < bestErr
            bestErr = hit.e10;
            name = hit.name;
        end
    end
end
end

function write_trace_row(fid, name, floatPack, pack)
first = [0 0 0 0];
hardCase = 0;
for roundIndex = 1:3
    diffPorts = 0; beta = 0; ports = 0;
    for k = 1:numel(pack)
        got = pack{k}.trace.round(roundIndex);
        ref = floatPack{k}.trace.round(roundIndex);
        for p = 1:size(got.idx,1)
            ports = ports + 1;
            if any(got.idx(p,:) ~= ref.idx(p,:))
                diffPorts = diffPorts + 1;
                if first(1)==0
                    slot = find(got.idx(p,:) ~= ref.idx(p,:), 1);
                    first = [k roundIndex p slot];
                end
            end
        end
        beta = max(beta, max(abs(got.betaAfter(:)-ref.betaAfter(:))));
        if hardCase==0 && any(pack{k}.bits ~= floatPack{k}.bits)
            hardCase = k;
        end
    end
    fprintf(fid,'%s,%d,%d,%d,%.8g,%d,%d,%d,%d,%d\n', name, roundIndex, ports, diffPorts, beta, first(1), first(2), first(3), first(4), hardCase);
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

function finish(R, hash)
t = readtable(fullfile(R.raw,'grid_summary.csv'),'TextType','string');
m = jsondecode(fileread(R.manifest));
m.driver_revision = ['experiments/run_batch4.m @ ' hash];
m.raw_sources = {'raw/grid_summary.csv','raw/per_frame.csv','raw/grid_sat.csv','raw/并列.csv'};
if height(t)==64 && all(t.status~="ERROR")
    m.status = 'COMPLETE';
    m.error = '';
else
    m.status = 'PARTIAL';
    m.error = sprintf('grid rows %d', height(t));
end
write_json(R.manifest, m);
end

function write_json(path, m)
fid = fopen(path,'w','n','UTF-8');
assert(fid>=0);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n', jsonencode(m));
end
