function run_width_push()
% Single-edge width ladders on the same 80 raw frames as the A2_out smoke.
% Double remains the reference. A zero-disagreement row is an observation
% on this set, not a frozen FPGA/IC format and not a 5 pJ/bit measurement.
base = fileparts(fileparts(mfilename('fullpath')));
addpath(base);
addpath(fileparts(mfilename('fullpath')));
cases = make_cases(20,1105);
msg = [24 12; 16 10; 12 8; 10 6; 8 4; 6 3; 4 2];
wts = [18 14; 14 12; 12 10; 10 8; 8 6; 6 4; 4 2];
prod = [42 26; 32 20; 24 14; 20 12; 16 10; 12 8; 8 4];
acc = [45 26; 32 18; 24 14; 20 12; 16 10; 12 8; 8 4];
rate = [18 16; 12 10; 8 6; 6 4; 4 2];
unit = [16 14; 10 8; 8 6; 6 4; 4 2];
sumexp = [16 11; 12 7; 10 5; 8 4; 6 2];
mix = [32 8; 24 8; 16 6; 12 4; 8 2];
varf = [16 12; 12 10; 10 8; 8 6; 6 4; 4 2];
front = [24 12; 16 8; 12 6; 10 4; 8 2];
nvar = [24 16; 16 12; 12 10; 10 8; 8 6];
nv = [16 14; 12 10; 10 8; 8 6; 6 4];
iv = [16 8; 12 6; 10 4; 8 2; 6 2];
jobs = {
    'A2_x',msg; 'A2_w',wts; 'A2_out',msg; 'A2_product',prod; 'A2_acc',acc;
    'A13_x',msg; 'A13_w',wts; 'A13_out',msg; 'A13_product',prod; 'A13_acc',acc;
    'A5_x',msg; 'A5_w',wts; 'A5_out',msg; 'A5_product',prod; 'A5_acc',acc;
    'alpha',msg; 'raw',msg; 'beta',msg; 'lambda',msg; 'ai',msg; 'llr',msg;
    'residual',msg; 'mu',msg; 'var',varf; 'weighted',varf;
    'exp',unit; 'prob',unit; 'sum_exp',sumexp;
    'mix_a',mix; 'mix_b',mix; 'mix_output',mix;
    'rate',rate; 'damp_product_old',msg; 'damp_product_new',msg; 'damp_sum',msg;
    'input_y',msg; 'input_H',msg; 'input_nv',nv; 'input_iv',iv;
    'frontend_gram',front; 'frontend_rhs',front; 'frontend_center',msg;
    'frontend_cov',front; 'frontend_variance',nvar;
    'frontend_score',msg; 'frontend_local',msg};
out = fullfile(fileparts(mfilename('fullpath')),'results','width_push_20261105');
if ~exist(out,'dir'), mkdir(out); end
fid = fopen(fullfile(out,'summary.csv'),'w','n','UTF-8');
assert(fid>=0);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'edge,W,F,status,floatErrors,fixedErrors,candidateErrors,disagreements,llrMax,saturations\n');
obs = cell(size(jobs,1),1);
for j = 1:size(jobs,1)
    edge = jobs{j,1};
    formats = jobs{j,2};
    fprintf('EDGE %d/%d %s\n', j, size(jobs,1), edge);
    runs = run_edge_experiment(edge, formats, cases);
    hold = [];
    for f = 1:numel(runs)
        r = runs{f};
        W = formats(f,1); F = formats(f,2);
        if isempty(r.metrics)
            fprintf(fid,'%s,%d,%d,ERROR,nan,nan,nan,nan,nan,nan\n', edge, W, F);
            fprintf('  %s S%d.%d ERROR\n', edge, W, F);
            continue;
        end
        fe = sum(r.metrics.floatErrors);
        xe = sum(r.metrics.fixedErrors);
        ce = sum(r.metrics.candidateErrors);
        dg = sum(r.metrics.disagreements);
        ll = max(r.metrics.llrMaxVsFloat);
        st = sum(r.metrics.edgeSaturations);
        fprintf(fid,'%s,%d,%d,%s,%d,%d,%d,%d,%.8g,%d\n', edge, W, F, r.status, fe, xe, ce, dg, ll, st);
        fprintf('  %s S%d.%d bitsErr %d/%d/%d disagree %d llr %.4g sat %d\n', edge, W, F, fe, xe, ce, dg, ll, st);
        hold(end+1,:) = [W, F, dg, st, ll, ce]; %#ok<AGROW>
    end
    obs{j} = describe_cliff(edge, hold);
    fprintf('OBS %s\n', obs{j});
end
of = fopen(fullfile(out,'observation.md'),'w','n','UTF-8');
assert(of>=0);
c2 = onCleanup(@() fclose(of)); %#ok<NASGU>
fprintf(of,'# 单边压位宽观察（80 帧，seed 1105）\n\n');
fprintf(of,'双精度是参考。下面每一行只量化一个边界。和 float 硬判一致只说明这 1920 bit 上没翻比特，不是位宽冻结，也不是 5 pJ/bit。\n\n');
for j = 1:numel(obs)
    fprintf(of,'- %s\n', obs{j});
end
fprintf('WIDTH_PUSH_DONE\n');
end

function s = describe_cliff(edge, hold)
if isempty(hold)
    s = sprintf('%s：本梯子全部执行失败', edge);
    return;
end
ok = hold(:,3)==0 & hold(:,4)==0;
if any(ok)
    k = find(ok, 1, 'last');
    s = sprintf('%s：这组帧上硬判仍与 float 相同、且该边无饱和的最窄一档是 S%d.%d', edge, hold(k,1), hold(k,2));
    if k < size(hold,1)
        s = sprintf('%s；再窄的 S%d.%d 硬判差 %d bit，饱和 %d，最大 LLR 差 %.4g', ...
            s, hold(k+1,1), hold(k+1,2), hold(k+1,3), hold(k+1,4), hold(k+1,5));
    else
        s = sprintf('%s；梯子最窄档仍未翻硬判', s);
    end
else
    s = sprintf('%s：最宽的 S%d.%d 已经和 float 差 %d bit，饱和 %d，最大 LLR 差 %.4g', ...
        edge, hold(1,1), hold(1,2), hold(1,3), hold(1,4), hold(1,5));
end
end
