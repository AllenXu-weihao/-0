function run_process_joint()
% One computation process at a time, starting from double.
% Every instrumented number in that process shares one signed format.
% Other processes stay double. Acceptance is bit errors versus the
% transmitted bits: fewest errors, then the narrowest total width.
% A second run stitches the six chosen formats and resimulates the frame.
test_experiments();
base = fileparts(fileparts(mfilename('fullpath')));
addpath(base);
addpath(fileparts(mfilename('fullpath')));
cases = make_cases(20, 1105);
n = numel(cases);
ref = cell(n, 1);
fixed = cell(n, 1);
for k = 1:n
    ref{k} = MIMO(cases(k).input, 'float');
    fixed{k} = MIMO(cases(k).input, 'fixed_mvm');
end
floatErr = zeros(n, 1);
fixedErr = zeros(n, 1);
for k = 1:n
    floatErr(k) = nnz(ref{k}.bits ~= cases(k).truth);
    fixedErr(k) = nnz(fixed{k}.bits ~= cases(k).truth);
end
stages = process_table();
ladder = [24 14; 20 12; 18 12; 16 12; 16 10; 14 10; 12 8; 12 6; 10 6; 8 4];
root = fullfile(fileparts(mfilename('fullpath')), 'matlab位宽建模实验2_单计算过程协同压窄', 'result');
if ~exist(root, 'dir'), mkdir(root); end
save(fullfile(root, 'inputs.mat'), 'cases');
fid = fopen(fullfile(root, 'summary.csv'), 'w', 'n', 'UTF-8');
assert(fid >= 0);
cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, ['stage,W,F,status,floatErrors,fixedErrors,candidateErrors,' ...
    'disagreements,llrMax,saturations,e0,e10,e20,e30\n']);
picks = struct('stage', {}, 'W', {}, 'F', {}, 'candidateErrors', {}, 'note', {});
for s = 1:numel(stages)
    fprintf('PROCESS %s\n', stages(s).name);
    held = [];
    for f = 1:size(ladder, 1)
        W = ladder(f, 1);
        Fr = ladder(f, 2);
        fmt = pack_format(stages(s).edges, W, Fr);
        [rows, status, message] = eval_formats(cases, ref, fixed, floatErr, fixedErr, fmt);
        if strcmp(status, 'ERROR')
            fprintf(fid, '%s,%d,%d,ERROR,nan,nan,nan,nan,nan,nan,nan,nan,nan,nan\n', stages(s).name, W, Fr);
            fprintf('  %s S%d.%d ERROR %s\n', stages(s).name, W, Fr, first_line(message));
            write_error(fullfile(root, stages(s).name, sprintf('S%d_%d_ERROR', W, Fr)), message);
        else
            sat = rows.saturations;
            fprintf(fid, '%s,%d,%d,OK,%d,%d,%d,%d,%.8g,%d,%d,%d,%d,%d\n', ...
                stages(s).name, W, Fr, sum(floatErr), sum(fixedErr), sum(rows.candidateErrors), ...
                sum(rows.disagreements), max(rows.llrMax), sat, ...
                snr_sum(rows, 0), snr_sum(rows, 10), snr_sum(rows, 20), snr_sum(rows, 30));
            fprintf('  %s S%d.%d err %d disagree %d sat %d\n', stages(s).name, W, Fr, ...
                sum(rows.candidateErrors), sum(rows.disagreements), sat);
            write_frame(fullfile(root, stages(s).name, sprintf('S%d_%d', W, Fr)), rows);
            held(end + 1, :) = [W, Fr, sum(rows.candidateErrors), snr_sum(rows, 30)]; %#ok<AGROW>
        end
    end
    picks(s) = choose_process(stages(s).name, held); %#ok<AGROW>
    fprintf('PICK %s S%d.%d err %d (%s)\n', picks(s).stage, picks(s).W, picks(s).F, picks(s).candidateErrors, picks(s).note);
end
fmt = struct();
for s = 1:numel(stages)
    fmt = merge_format(fmt, pack_format(stages(s).edges, picks(s).W, picks(s).F));
end
[rows, status, message] = eval_formats(cases, ref, fixed, floatErr, fixedErr, fmt);
stitchDir = fullfile(root, '拼接');
if strcmp(status, 'ERROR')
    fprintf('STITCH ERROR %s\n', first_line(message));
    write_error(stitchDir, message);
else
    fprintf('STITCH err %d disagree %d sat %d snr %d/%d/%d/%d\n', ...
        sum(rows.candidateErrors), sum(rows.disagreements), rows.saturations, ...
        snr_sum(rows, 0), snr_sum(rows, 10), snr_sum(rows, 20), snr_sum(rows, 30));
    write_frame(stitchDir, rows);
end
write_picks(fullfile(root, '选择.csv'), picks);
fprintf('PROCESS_JOINT_DONE\n');
end

function stages = process_table()
stages = struct('name', {}, 'edges', {});
stages(1).name = 'F';
stages(1).edges = {'input_y','input_H','input_nv','input_iv','frontend_gram','frontend_rhs', ...
    'frontend_center','frontend_cov','frontend_variance','frontend_score','frontend_local'};
stages(2).name = 'I1';
stages(2).edges = {'A2_x','A2_w','A2_product','A2_acc','A2_out','alpha'};
stages(3).name = 'I2';
stages(3).edges = {'exp','sum_exp','prob','mu','var','residual','weighted','mix_a','mix_b','mix_output','lambda','ai'};
stages(4).name = 'I3';
stages(4).edges = {'A13_x','A13_w','A13_product','A13_acc','A13_out','raw','rate', ...
    'damp_product_old','damp_product_new','damp_sum','beta'};
stages(5).name = 'I4';
stages(5).edges = {'A5_x','A5_w','A5_product','A5_acc','A5_out'};
stages(6).name = 'R';
stages(6).edges = {'llr'};
end

function fmt = pack_format(names, W, Fr)
fmt = struct();
for i = 1:numel(names)
    fmt.(names{i}) = struct('W', W, 'F', Fr);
end
end

function fmt = merge_format(a, b)
fmt = a;
names = fieldnames(b);
for i = 1:numel(names)
    fmt.(names{i}) = b.(names{i});
end
end

function [rows, status, message] = eval_formats(cases, ref, fixed, floatErr, fixedErr, fmt)
status = 'OK';
message = '';
n = numel(cases);
rows = struct('snr', zeros(n,1), 'floatErrors', floatErr, 'fixedErrors', fixedErr, ...
    'candidateErrors', zeros(n,1), 'disagreements', zeros(n,1), 'llrMax', zeros(n,1), 'saturations', 0);
try
    for k = 1:n
        [r, st] = run_quantized(cases(k).input, fmt);
        rows.snr(k) = cases(k).snrDB;
        rows.candidateErrors(k) = nnz(r.bits ~= cases(k).truth);
        rows.disagreements(k) = nnz(r.bits ~= ref{k}.bits);
        rows.llrMax(k) = max(abs(r.llr - ref{k}.llr), [], 'all');
        rows.saturations = rows.saturations + saturation_of(st, fieldnames(fmt));
    end
catch err
    status = 'ERROR';
    message = getReport(err, 'extended', 'hyperlinks', 'off');
    rows = [];
end
end

function sat = saturation_of(st, names)
sat = 0;
for i = 1:numel(names)
    if isfield(st, names{i})
        sat = sat + st.(names{i}).saturations;
    end
end
end

function n = snr_sum(rows, snr)
n = sum(rows.candidateErrors(rows.snr == snr));
end

function pick = choose_process(name, held)
% held columns: W, F, candidateErrors, errorsAt30dB
pick = struct('stage', name, 'W', 0, 'F', 0, 'candidateErrors', inf, 'note', 'no successful format');
if isempty(held)
    return;
end
best = min(held(:, 3));
pool = held(held(:, 3) == best, :);
% Narrowest total width, then fewer fraction bits if the totals match.
[~, order] = sortrows(pool, [1 2]);
chosen = pool(order(1), :);
note = 'fewest bit errors then narrowest width';
wide = held(held(:, 4) == 0, :);
if chosen(4) > 0 && ~isempty(wide)
    % 30 dB float error count is 0. Keep a wider format when the narrow
    % minimum spends those error-free bits and a no-30dB format exists.
    bestWide = min(wide(:, 3));
    poolW = wide(wide(:, 3) == bestWide, :);
    [~, orderW] = sortrows(poolW, [1 2]);
    alt = poolW(orderW(1), :);
    if alt(3) <= chosen(3) + 0
        chosen = alt;
        note = 'same minimum among formats that keep 30 dB at 0 errors';
    else
        note = sprintf('minimum errors is %d but 30 dB is no longer 0; kept the zero-30dB format with %d errors', chosen(3), alt(3));
        chosen = alt;
    end
end
pick.W = chosen(1);
pick.F = chosen(2);
pick.candidateErrors = chosen(3);
pick.note = note;
end

function write_frame(folder, rows)
if ~exist(folder, 'dir'), mkdir(folder); end
t = table(rows.snr, rows.floatErrors, rows.fixedErrors, rows.candidateErrors, rows.disagreements, rows.llrMax, ...
    'VariableNames', {'backgroundSNR','floatErrors','fixedErrors','candidateErrors','disagreements','llrMaxVsFloat'});
writetable(t, fullfile(folder, 'per_frame.csv'));
end

function write_error(folder, message)
if ~exist(folder, 'dir'), mkdir(folder); end
fid = fopen(fullfile(folder, 'error.txt'), 'w', 'n', 'UTF-8');
if fid < 0, return; end
fprintf(fid, '%s\n', message);
fclose(fid);
end

function write_picks(path, picks)
fid = fopen(path, 'w', 'n', 'UTF-8');
assert(fid >= 0);
fprintf(fid, 'stage,W,F,candidateErrors,note\n');
for i = 1:numel(picks)
    fprintf(fid, '%s,%d,%d,%d,%s\n', picks(i).stage, picks(i).W, picks(i).F, picks(i).candidateErrors, picks(i).note);
end
fclose(fid);
end

function s = first_line(message)
s = strtrim(message);
nl = find(s == newline, 1);
if ~isempty(nl), s = strtrim(s(1:nl-1)); end
end
