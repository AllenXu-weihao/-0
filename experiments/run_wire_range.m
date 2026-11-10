function run_wire_range(outputDir)
% Pass a run-specific directory to keep the archived results intact.
% Step 3 of the redo: per-wire range on the double-precision model.
% Same 80 frames and seed 1105 as experiment 2. No format is applied.
% Ordered MAC is walked so product and accumulator ranges exist.
test_experiments();
base = fileparts(fileparts(mfilename('fullpath')));
addpath(base);
addpath(fileparts(mfilename('fullpath')));
cases = make_cases(20, 1105);
n = numel(cases);
opts = struct('orderedObserve', true, 'logEdges', [-40 16]);
if nargin < 1 || isempty(outputDir)
    root = fullfile(fileparts(mfilename('fullpath')), 'matlab位宽建模实验3_线级范围', 'result');
else
    root = outputDir;
end
if ~exist(root, 'dir'), mkdir(root); end
acc = struct();
snrPeak = struct();
llrGap = 0;
floatErr = 0;
for k = 1:n
    ref = MIMO(cases(k).input, 'float');
    [r, st] = run_quantized(cases(k).input, struct(), opts);
    llrGap = max(llrGap, max(abs(r.llr - ref.llr), [], 'all'));
    floatErr = floatErr + nnz(ref.bits ~= cases(k).truth);
    acc = absorb(acc, st);
    snrPeak = absorb_peak(snrPeak, st, cases(k).snrDB);
    fprintf('FRAME %d/%d snr %g\n', k, n, cases(k).snrDB);
end
write_range(fullfile(root, 'range.csv'), acc, opts.logEdges);
write_hist(fullfile(root, 'hist.csv'), acc, opts.logEdges);
write_snr(fullfile(root, 'snr_peak.csv'), snrPeak);
fid = fopen(fullfile(root, '观察.txt'), 'w', 'n', 'UTF-8');
assert(fid >= 0);
fprintf(fid, '帧数 %d，种子 1105。双精度误码 %d。有序观察相对 MIMO 浮点的最大 LLR 差 %.8g。未量化。\n', n, floatErr, llrGap);
fclose(fid);
fprintf('WIRE_RANGE_DONE frames %d floatErr %d llrGap %.8g\n', n, floatErr, llrGap);
end

function acc = absorb(acc, st)
names = fieldnames(st);
for i = 1:numel(names)
    id = names{i};
    a = st.(id);
    if ~isfield(acc, id)
        acc.(id) = a;
        continue;
    end
    b = acc.(id);
    b.calls = b.calls + a.calls;
    b.elements = b.elements + a.elements;
    b.minimum = min(b.minimum, a.minimum);
    b.maximum = max(b.maximum, a.maximum);
    b.saturations = b.saturations + a.saturations;
    b.maxError = max(b.maxError, a.maxError);
    if isfield(a, 'logCount')
        b.logCount = b.logCount + a.logCount;
        b.logUnder = b.logUnder + a.logUnder;
        b.logOver = b.logOver + a.logOver;
        b.logZero = b.logZero + a.logZero;
    end
    acc.(id) = b;
end
end

function snrPeak = absorb_peak(snrPeak, st, snr)
tag = sprintf('s%d', snr);
names = fieldnames(st);
for i = 1:numel(names)
    id = names{i};
    peak = max(abs([st.(id).minimum, st.(id).maximum]));
    if ~isfield(snrPeak, id), snrPeak.(id) = struct(); end
    if ~isfield(snrPeak.(id), tag)
        snrPeak.(id).(tag) = peak;
    else
        snrPeak.(id).(tag) = max(snrPeak.(id).(tag), peak);
    end
end
end

function write_range(path, acc, edges)
fid = fopen(path, 'w', 'n', 'UTF-8');
assert(fid >= 0);
fprintf(fid, 'wire,role,calls,elements,minimum,maximum,peak,signIntBits,signIntBitsPlusGuard,modeLog2,modeCount\n');
names = sort(fieldnames(acc));
for i = 1:numel(names)
    id = names{i};
    a = acc.(id);
    peak = max(abs([a.minimum, a.maximum]));
    bits = sign_int_bits(peak);
    [modeBin, modeCount] = mode_bin(a, edges);
    fprintf(fid, '%s,%s,%d,%d,%.8g,%.8g,%.8g,%d,%d,%d,%d\n', ...
        id, wire_role(id), a.calls, a.elements, a.minimum, a.maximum, peak, bits, bits + 1, modeBin, modeCount);
end
fclose(fid);
end

function write_hist(path, acc, edges)
fid = fopen(path, 'w', 'n', 'UTF-8');
assert(fid >= 0);
fprintf(fid, 'wire,log2Floor,count\n');
names = sort(fieldnames(acc));
loB = edges(1);
for i = 1:numel(names)
    id = names{i};
    a = acc.(id);
    if ~isfield(a, 'logCount'), continue; end
    fprintf(fid, '%s,under,%d\n', id, a.logUnder);
    for b = 1:numel(a.logCount)
        if a.logCount(b) == 0, continue; end
        fprintf(fid, '%s,%d,%d\n', id, loB + b - 1, a.logCount(b));
    end
    fprintf(fid, '%s,over,%d\n', id, a.logOver);
    fprintf(fid, '%s,zero,%d\n', id, a.logZero);
end
fclose(fid);
end

function write_snr(path, snrPeak)
fid = fopen(path, 'w', 'n', 'UTF-8');
assert(fid >= 0);
fprintf(fid, 'wire,role,snrDB,peak,signIntBits\n');
names = sort(fieldnames(snrPeak));
for i = 1:numel(names)
    id = names{i};
    tags = fieldnames(snrPeak.(id));
    for j = 1:numel(tags)
        snr = sscanf(tags{j}, 's%d');
        peak = snrPeak.(id).(tags{j});
        fprintf(fid, '%s,%s,%d,%.8g,%d\n', id, wire_role(id), snr, peak, sign_int_bits(peak));
    end
end
fclose(fid);
end

function [modeBin, modeCount] = mode_bin(a, edges)
modeBin = 0;
modeCount = 0;
if ~isfield(a, 'logCount'), return; end
[modeCount, idx] = max(a.logCount);
if modeCount == 0, return; end
modeBin = edges(1) + idx - 1;
end

function n = sign_int_bits(peak)
% Signed integer bits, including the sign, such that peak < 2^(n-1).
% Sub-unity peaks still need the sign bit. This is not a frozen format.
if ~(peak > 0)
    n = 1;
    return;
end
n = max(1, floor(log2(peak)) + 2);
end

function role = wire_role(name)
onchip = {'alpha','raw','damp_product_old','damp_product_new','damp_sum','beta','llr'};
ports = {'A2_x','A2_out','A13_x','A13_out','A5_x','A5_out'};
if any(strcmp(name, onchip))
    role = '片上';
elseif any(strcmp(name, ports))
    role = '端口';
else
    role = '片外';
end
end
