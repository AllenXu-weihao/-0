function run_batch6()
% Compare damper rounding A and B. Default A stays the fifth-batch path.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
addpath(fullfile(root,'实验档案'));
addpath(fileparts(mfilename('fullpath')));
cd(root);
prevId = 'E2-M_cross_sample_three_s271111_a01_20261111_012042_tpd5715780_d324_4b16_ba0e_9f21c35438d9';
prev = fullfile(root,'实验档案','01_运行记录',prevId);
R = find_resume(root);
if isempty(R)
    R = new_run('E3','damp_rounding',271111,1);
    write_protocol(R, prevId);
    mark_running(R, prevId);
    append_index(root, R);
end
fprintf('RUN %s\n', R.id);
if exist(fullfile(R.raw,'定向失败.txt'),'file') || exist(fullfile(R.raw,'桥接失败.txt'),'file') || exist(fullfile(R.raw,'算术失败.txt'),'file')
    error('BATCH6_STOPPED %s', R.id);
end
if ~exist(fullfile(R.raw,'定向通过.txt'),'file')
    directed(R);
end
S = load(fullfile(prev,'raw','inputs.mat'),'cases');
cases = S.cases;
assert(numel(cases)==2048 && all([cases.seed]==271111));
F = load(fullfile(prev,'raw','float_dev.mat'),'floatBits','floatLlr');
specs = widths();
for i = 1:numel(specs)
    run_saved(R, prev, cases, F.floatBits, F.floatLlr, specs(i), 'A', true);
end
if ~exist(fullfile(R.raw,'桥接通过.txt'),'file')
    fid = fopen(fullfile(R.raw,'桥接通过.txt'),'w','n','UTF-8');
    fprintf(fid,'两个宽度的算术 A 与第五批 MAT 的硬判和 LLR 全精度一致，rate 整数码为 307。\n');
    fclose(fid);
    fprintf('BRIDGE_PASS\n');
end
for i = 1:numel(specs)
    run_saved(R, prev, cases, F.floatBits, F.floatLlr, specs(i), 'B', false);
end
export_tables(R, cases);
finish(R);
fprintf('BATCH6_DONE %s\n', R.id);
end

function R = find_resume(root)
R = [];
parent = fullfile(root,'实验档案','01_运行记录');
d = dir(fullfile(parent,'E3_damp_rounding_*'));
if isempty(d), return; end
[~,ix] = max([d.datenum]);
folder = fullfile(parent, d(ix).name);
if exist(fullfile(folder,'raw','导出完成.txt'),'file'), return; end
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
fprintf(fid,'# 单次实验协议\n\n冻结于查看本批新结果之前。\n\n');
fprintf(fid,'|项目|本次冻结值|\n|---|---|\n');
fprintf(fid,'|问题|β 阻尼的舍入放在两个乘积之后，还是放在一次对齐和之后|\n');
fprintf(fid,'|代码|开工时 HEAD %s。驱动 experiments/run_batch6.m。前次 %s。不改 MIMO.m，默认仍是 A|\n', strtrim(hash), prevId);
fprintf(fid,'|算术 A|Qβ(Q16.10(Q16.10(717·β旧/1024)+Q16.10(307·raw/1024)))|\n');
fprintf(fid,'|算术 B|Qβ(Q16.10((717·β旧+307·raw)/1024))。乘积与和对齐后保留足够位宽，和之前不夹幅|\n');
fprintf(fid,'|宽度|W15_15_15 与 W21_19_17。整数位 9/8/7。其余边、排序、三轮和 LLR 格式不动|\n');
fprintf(fid,'|样本|先做定向整数对拍，不跑整机。通过后用第五批 inputs.mat 的 2048 帧。不使用 9110527|\n');
fprintf(fid,'|桥接|A 的硬判和 24 个 LLR 必须与第五批 MAT 全精度一致。失败则不做 A/B 性能比较|\n');
fprintf(fid,'|判断|局部差在窄点写回后消失且完整差异很小，就保留 A。B 若造成可定位的翻转，先定算术合同。开发集不能证明全域非劣|\n');
fprintf(fid,'|终止|不重扫 64 点，不开 E4，不综合，不报 pJ/bit|\n');
end

function mark_running(R, prevId)
m = jsondecode(fileread(R.manifest));
m.status = 'RUNNING';
m.previous_run_id = prevId;
m.driver_revision = 'experiments/run_batch6.m';
m.entry_command = 'run_batch6';
m.dataset_role = '开发诊断';
m.cases_path = ['实验档案/01_运行记录/' prevId '/raw/inputs.mat'];
m.reference = 'fifth-batch MAT for arithmetic A; integer damper for A and B';
m.candidate_ids = {'W15_15_15_A','W15_15_15_B','W21_19_17_A','W21_19_17_B'};
m.matrix_arithmetic = 'same mild ordered product; only the damper rounding site changes';
m.architecture = 'instrumented MATLAB, dampMode defaults to A';
m.decision_rule = 'A must match batch 5 exactly; B is compared on the same 2048 frames and is not a global acceptance';
write_json(R.manifest, m);
end

function append_index(root, R)
fid = fopen(fullfile(root,'实验档案','02_汇总','运行索引.csv'),'a','n','UTF-8');
assert(fid>=0);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
rel = ['实验档案/01_运行记录/' R.id];
fprintf(fid,'%s,E3,1,E2-M_cross_sample_three_s271111_a01_20261111_012042_tpd5715780_d324_4b16_ba0e_9f21c35438d9,开发诊断,RUNNING,待定,%s/protocol.md,%s/manifest.json,\n', ...
    R.id, rel, rel);
end

function directed(R)
fprintf('DIRECTED\n');
fid = fopen(fullfile(R.raw,'定向对拍.csv'),'w','n','UTF-8');
assert(fid>=0);
fprintf(fid,'name,Fr,Fb,Wb,rawCode,betaCode,sumA,sumB,betaA,betaB,midSat,qedgeMatch\n');
rows = { ...
    'zero_narrow',7,8,15,0,0,-0,-0,-0,-0,false; ...
    'equal_pos',7,8,15,5,5,26,26,7,7,false; ...
    'equal_neg',7,8,15,-5,-5,-26,-26,-7,-7,false; ...
    'half_beta',7,8,15,0,-3968,-11114,-11114,-2779,-2779,false; ...
    'half_raw',7,8,15,-3904,0,-9364,-9364,-2341,-2341,false; ...
    'half_beta_pos',7,8,15,0,3968,11114,11114,2779,2779,false; ...
    'wide_lesson',11,10,17,-2,-2,-1,-2,-1,-2,false; ...
    'wide_lesson_pos',11,10,17,2,2,1,2,1,2,false; ...
    'narrow_kept',7,8,15,-8,-8,-41,-42,-10,-11,false; ...
    'narrow_erased',7,8,15,32,-64,-102,-103,-26,-26,false; ...
    'narrow_full_raw',7,8,15,16383,0,32767,32767,8192,8192,true};
for i = 1:size(rows,1)
    item = rows(i,:);
    rec = damp_codes(item{5}, item{6}, item{2}, item{3}, item{4});
    qmatch = qedge_matches(item{5}, item{6}, item{2}, item{3}, item{4}, rec);
    fprintf(fid,'%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n', item{1}, item{2}, item{3}, item{4}, item{5}, item{6}, ...
        rec.sumA, rec.sumB, rec.betaA, rec.betaB, any(rec.midSat), qmatch);
    expect = [item{7} item{8} item{9} item{10}];
    got = [rec.sumA rec.sumB rec.betaA rec.betaB];
    if any(got ~= expect) || ~qmatch || any(rec.midSat) ~= item{11}
        fclose(fid);
        fail_file(R, '定向失败.txt', sprintf('%s expected %s got %s qedge %d', item{1}, mat2str(expect), mat2str(got), qmatch));
    end
end
fclose(fid);
fid = fopen(fullfile(R.raw,'定向通过.txt'),'w','n','UTF-8');
fprintf(fid,'rate 码 307，互补 717。宽锚点例 A 的和为 -1、B 为 -2，Qβ 保留这一级。窄点 raw=-8、β=-8 时 A/B 为 -41/-42，Qβ 后为 -10/-11，差异还在。raw=32、β=-64 时和差一级，Qβ 后都是 -26，写回消除了这一级。满量程 raw=16383 有中间饱和，只作算术例，不拿来解释误码。\n');
fclose(fid);
fprintf('DIRECTED_PASS\n');
end

function ok = qedge_matches(rawCode, betaCode, Fr, Fb, Wb, rec)
global MIMO_EXPERIMENT
previous = MIMO_EXPERIMENT;
cleaner = onCleanup(@() restore_experiment(previous)); %#ok<NASGU>
formats = struct('rate',pair(16,10),'damp_product_old',pair(16,10),'damp_product_new',pair(16,10), ...
    'damp_sum',pair(16,10),'beta',pair(Wb,Fb));
MIMO_EXPERIMENT = struct('formats',formats,'stats',struct());
rate = qedge('rate', 0.3);
d0 = qedge('damp_product_old', (1-rate)*betaCode/2^Fb);
d1 = qedge('damp_product_new', rate*rawCode/2^Fr);
sm = qedge('damp_sum', d0+d1);
beta = qedge('beta', sm);
ok = round(rate*1024)==307 && round((1-rate)*1024)==717 && round(d0*1024)==rec.prodOld && ...
    round(d1*1024)==rec.prodNew && round(sm*1024)==rec.sumA && round(beta*2^Fb)==rec.betaA;
end

function restore_experiment(previous)
global MIMO_EXPERIMENT
MIMO_EXPERIMENT = previous;
end

function run_saved(R, prev, cases, floatBits, floatLlr, spec, mode, bridge)
name = [spec.name '_' mode];
path = fullfile(R.raw, ['cand_' name '.mat']);
if exist(path,'file')
    fprintf('SKIP %s\n', name);
    if bridge
        S = load(path,'pack');
        check_bridge(R, prev, spec.name, S.pack);
    end
    return
end
fprintf('RUN %s\n', name);
fmt = point_format(spec.Wa, spec.Wr, spec.Wb);
if strcmp(mode,'B')
    fmt = rmfield(fmt, {'damp_product_old','damp_product_new','damp_sum'});
end
n = numel(cases);
pack.llr = zeros(n,24);
pack.bits = false(n,24);
pack.err = zeros(n,1);
pack.floatErr = zeros(n,1);
pack.wrong = zeros(n,1);
pack.right = zeros(n,1);
pack.dis = zeros(n,1);
pack.llrMax = zeros(n,1);
pack.satFrame = zeros(n,1);
pack.snr = zeros(n,1);
pack.idx = zeros(n,20,9,3,'uint8');
pack.localSum = zeros(n,3);
pack.localBeta = zeros(n,3);
pack.midSat = zeros(n,3);
pack.sumSatA = zeros(n,3);
pack.sumSatB = zeros(n,3);
pack.writeSat = zeros(n,3);
pack.first = empty_first();
opts = struct('dampMode',mode,'dampAudit',true);
for k = 1:n
    try
        [r,st] = run_quantized(cases(k).input, fmt, opts);
    catch err
        fail_file(R, '算术失败.txt', sprintf('%s case %d %s', name, k, err.message));
    end
    if k==1
        [r2,~] = run_quantized(cases(k).input, fmt, struct('dampMode',mode,'dampAudit',false,'trace',true));
        if max(abs(r2.llr(:)-r.llr(:)))~=0 || any(r2.bits(:)~=r.bits(:))
            fail_file(R, '算术失败.txt', sprintf('%s trace changed case 1', name));
        end
        if ~isfield(st,'dampAudit') || st.dampAudit.rateCode~=307
            fail_file(R, '算术失败.txt', sprintf('%s rate code is not 307', name));
        end
    end
    truth = cases(k).truth(:).';
    cb = r.bits(:).';
    fb = floatBits(k,:);
    floatWrong = fb ~= truth;
    candWrong = cb ~= truth;
    pack.llr(k,:) = r.llr(:).';
    pack.bits(k,:) = cb;
    pack.floatErr(k) = nnz(floatWrong);
    pack.err(k) = nnz(candWrong);
    pack.wrong(k) = nnz(~floatWrong & candWrong);
    pack.right(k) = nnz(floatWrong & ~candWrong);
    pack.dis(k) = nnz(cb ~= fb);
    pack.llrMax(k) = max(abs(pack.llr(k,:) - floatLlr(k,:)));
    pack.satFrame(k) = sat_total(edge_sat(st));
    pack.snr(k) = cases(k).snrDB;
    for t = 1:3
        slot = st.dampAudit.round(t);
        pack.idx(k,:,:,t) = reshape(uint8(slot.idx),1,20,9);
        pack.localSum(k,t) = slot.localSumDiff;
        pack.localBeta(k,t) = slot.localBetaDiff;
        pack.midSat(k,t) = slot.midSat;
        pack.sumSatA(k,t) = slot.sumSatA;
        pack.sumSatB(k,t) = slot.sumSatB;
        pack.writeSat(k,t) = slot.writeSat;
        if strcmp(mode,'A')
            pack.first = take_first(pack.first, k, t, slot);
        end
    end
    if mod(k,256)==0, fprintf('  %s %d/%d\n', name, k, n); end
end
save(path,'pack','-v7');
fprintf('SAVED %s\n', name);
if bridge
    check_bridge(R, prev, spec.name, pack);
end
end

function check_bridge(R, prev, name, pack)
old = load(fullfile(prev,'raw', ['cand_' name '.mat']),'rec');
llrGap = max(abs(pack.llr - old.rec.llr), [], 'all');
bitDiff = nnz(pack.bits ~= old.rec.bits);
satDiff = nnz(pack.satFrame ~= old.rec.satFrame);
if llrGap~=0 || bitDiff~=0 || satDiff~=0
    fail_file(R, '桥接失败.txt', sprintf('%s llr %.8g bits %d satFrames %d', name, llrGap, bitDiff, satDiff));
end
fprintf('BRIDGE_OK %s\n', name);
end

function first = empty_first()
first = struct('sumFrame',0,'sumRound',0,'sumAt',0,'sumA',0,'sumB',0,'rawCode',0,'betaCode',0, ...
    'betaFrame',0,'betaRound',0,'betaAt',0,'betaA',0,'betaB',0);
end

function first = take_first(first, frame, roundIndex, slot)
if first.sumFrame==0 && slot.firstSum>0
    first.sumFrame = frame;
    first.sumRound = roundIndex;
    first.sumAt = slot.firstSum;
    first.sumA = slot.sumA;
    first.sumB = slot.sumB;
    first.rawCode = slot.rawCode;
    first.betaCode = slot.betaCode;
end
if first.betaFrame==0 && slot.firstBeta>0
    first.betaFrame = frame;
    first.betaRound = roundIndex;
    first.betaAt = slot.firstBeta;
    first.betaA = slot.betaA;
    first.betaB = slot.betaB;
end
end

function export_tables(R, cases)
specs = widths();
ff = fopen(fullfile(R.raw,'per_frame.csv'),'w','n','UTF-8');
pf = fopen(fullfile(R.raw,'配对.csv'),'w','n','UTF-8');
rf = fopen(fullfile(R.raw,'轮差.csv'),'w','n','UTF-8');
assert(ff>=0 && pf>=0 && rf>=0);
fprintf(ff,'name,arith,case_index,backgroundSNR,floatErrors,candidateErrors,disagreements,became_wrong,became_correct,llrMax,saturations\n');
fprintf(pf,'name,snr,frames,bits,errA,errB,wrongAtoB,rightAtoB,disBits,framesDis,maxAbsLlr,p95AbsLlr\n');
fprintf(rf,'name,snr,round,items,localSumDiff,localBetaDiff,ports,idxDiffPorts,midSat,sumSatA,sumSatB,writeSatA,writeSatB\n');
note = fopen(fullfile(R.raw,'首差.txt'),'w','n','UTF-8');
for i = 1:numel(specs)
    A = load(fullfile(R.raw, ['cand_' specs(i).name '_A.mat']),'pack');
    B = load(fullfile(R.raw, ['cand_' specs(i).name '_B.mat']),'pack');
    A = A.pack; B = B.pack;
    for k = 1:numel(cases)
        fprintf(ff,'%s,A,%d,%.0f,%d,%d,%d,%d,%d,%.8g,%d\n', specs(i).name, k, A.snr(k), A.floatErr(k), A.err(k), A.dis(k), A.wrong(k), A.right(k), A.llrMax(k), A.satFrame(k));
        fprintf(ff,'%s,B,%d,%.0f,%d,%d,%d,%d,%d,%.8g,%d\n', specs(i).name, k, B.snr(k), B.floatErr(k), B.err(k), B.dis(k), B.wrong(k), B.right(k), B.llrMax(k), B.satFrame(k));
    end
    for level = [0 10 20 30]
        mask = A.snr==level;
        hard = A.bits(mask,:) ~= B.bits(mask,:);
        truth = vertcat_truth(cases(mask));
        wrong = nnz(A.bits(mask,:)==truth & B.bits(mask,:)~=truth);
        right = nnz(A.bits(mask,:)~=truth & B.bits(mask,:)==truth);
        delta = abs(B.llr(mask,:) - A.llr(mask,:));
        fprintf(pf,'%s,%.0f,%d,%d,%d,%d,%d,%d,%d,%d,%.8g,%.8g\n', specs(i).name, level, nnz(mask), nnz(mask)*24, ...
            sum(A.err(mask)), sum(B.err(mask)), wrong, right, nnz(hard), nnz(any(hard,2)), max(delta,[],'all'), percentile95(delta));
        for t = 1:3
            ports = squeeze(any(A.idx(mask,:,:,t) ~= B.idx(mask,:,:,t), 3));
            fprintf(rf,'%s,%.0f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n', specs(i).name, level, t, nnz(mask)*180, ...
                sum(A.localSum(mask,t)), sum(A.localBeta(mask,t)), nnz(mask)*20, nnz(ports), ...
                sum(A.midSat(mask,t)), sum(A.sumSatA(mask,t)), sum(A.sumSatB(mask,t)), sum(A.writeSat(mask,t)), sum(B.writeSat(mask,t)));
        end
    end
    write_first(note, specs(i).name, A, B);
end
fclose(ff); fclose(pf); fclose(rf); fclose(note);
fid = fopen(fullfile(R.raw,'导出完成.txt'),'w','n','UTF-8');
fprintf(fid,'底表、配对和轮差已从两侧 MAT 导出。\n');
fclose(fid);
end

function truth = vertcat_truth(subset)
n = numel(subset);
truth = false(n,24);
for k = 1:n
    truth(k,:) = subset(k).truth(:).';
end
end

function value = percentile95(delta)
flat = delta(:);
if isempty(flat)
    value = 0;
    return
end
flat = sort(flat);
value = flat(max(1, ceil(0.95*numel(flat))));
end

function write_first(fid, name, A, B)
fprintf(fid,'%s 局部和首差 帧 %d 轮 %d 项 %d 码 %d/%d raw %d beta %d。写回首差 帧 %d 轮 %d 项 %d 码 %d/%d。\n', ...
    name, A.first.sumFrame, A.first.sumRound, A.first.sumAt, A.first.sumA, A.first.sumB, A.first.rawCode, A.first.betaCode, ...
    A.first.betaFrame, A.first.betaRound, A.first.betaAt, A.first.betaA, A.first.betaB);
found = false;
for k = 1:size(A.idx,1)
    for t = 1:3
        row = squeeze(A.idx(k,:,:,t)) ~= squeeze(B.idx(k,:,:,t));
        port = find(any(row,2), 1);
        if ~isempty(port)
            slot = find(row(port,:), 1);
            fprintf(fid,'%s 口序首差 帧 %d 轮 %d 口 %d 候选 %d。\n', name, k, t, port, slot);
            found = true;
            break
        end
    end
    if found, break; end
end
if ~found
    fprintf(fid,'%s 在 2048 帧、3 轮、每轮 20 口里没有口序差。\n', name);
end
end

function finish(R)
m = jsondecode(fileread(R.manifest));
m.status = 'COMPLETE';
m.error = '';
m.raw_sources = {'raw/定向对拍.csv','raw/per_frame.csv','raw/配对.csv','raw/轮差.csv','raw/首差.txt'};
write_json(R.manifest, m);
end

function fail_file(R, name, message)
fid = fopen(fullfile(R.raw, name),'w','n','UTF-8');
fprintf(fid,'%s\n', message);
fclose(fid);
m = jsondecode(fileread(R.manifest));
m.status = 'ERROR';
m.error = message;
write_json(R.manifest, m);
error('BATCH6_FAIL %s', message);
end

function specs = widths()
specs = struct('name',{'W15_15_15','W21_19_17'},'Wa',{15,21},'Wr',{15,19},'Wb',{15,17});
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

function n = sat_total(acc)
n = 0;
names = fieldnames(acc);
for i = 1:numel(names), n = n + acc.(names{i}); end
end

function write_json(path, value)
fid = fopen(path,'w','n','UTF-8');
assert(fid>=0);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n', jsonencode(value));
end
