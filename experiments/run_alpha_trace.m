function run_alpha_trace(outputDir, cases)
% Read-only traces for the adjacent alpha formats. Trace on must not change LLR.
if nargin<1 || isempty(outputDir), error('Pass the raw trace directory.'); end
if ~exist(outputDir,'dir'), mkdir(outputDir); end
formats = {struct(), struct('alpha',struct('W',21,'F',12)), struct('alpha',struct('W',20,'F',11)), struct('alpha',struct('W',19,'F',10))};
names = {'float','F12','F11','F10'};
n = numel(cases);
floatLlr = cell(n,1);
for k = 1:n
    floatLlr{k} = MIMO(cases(k).input,'float').llr;
end
off = run_set(cases, formats{1}, false);
onFloat = run_set(cases, formats{1}, true);
gapOff = max_gap(off, floatLlr);
gapOn = max_gap(onFloat, floatLlr);
fid = fopen(fullfile(outputDir,'透明.txt'),'w','n','UTF-8');
assert(fid>=0);
fprintf(fid,'关 trace、不量化，相对 MIMO 浮点的最大 LLR 差 %.8g。\n', gapOff);
fprintf(fid,'开 trace、不量化，相对 MIMO 浮点的最大 LLR 差 %.8g。\n', gapOn);
fprintf(fid,'开 trace 与关 trace 的不量化 LLR 最大差 %.8g。\n', max_gap(onFloat, off));
onF10 = run_set(cases, formats{4}, true);
offF10 = run_set(cases, formats{4}, false);
f10Gap = max_gap(onF10, offF10);
f10Bits = bit_diff_frames(onF10, offF10);
fprintf(fid,'F=10 开 trace 与关 trace 的 LLR 最大差 %.8g，硬判不同帧数 %d。\n', f10Gap, f10Bits);
fclose(fid);
assert(gapOff<1e-9 && gapOn<1e-9 && max_gap(onFloat,off)<1e-9 && f10Gap<1e-9 && f10Bits==0, 'Trace changed the arithmetic.');
packs = {onFloat, [], [], onF10};
packs{2} = run_set(cases, formats{2}, true);
packs{3} = run_set(cases, formats{3}, true);
save(fullfile(outputDir,'traces.mat'),'packs','names','cases','-v7');
write_summary(fullfile(outputDir,'idx摘要.csv'), packs, names);
write_frames(fullfile(outputDir,'代表帧'), packs, names, cases);
fprintf('TRACE_DONE\n');
end

function out = run_set(cases, fmt, traceOn)
n = numel(cases);
out = cell(n,1);
opts = struct('trace',traceOn,'orderedObserve',false);
for k = 1:n
    [r,st] = run_quantized(cases(k).input, fmt, opts);
    out{k} = struct('llr',r.llr,'bits',r.bits,'trace',[]);
    if traceOn, out{k}.trace = st.trace; end
end
end

function gap = max_gap(a, b)
gap = 0;
for k = 1:numel(a)
    got = a{k}.llr;
    if isstruct(b{k}), ref = b{k}.llr; else, ref = b{k}; end
    gap = max(gap, max(abs(got-ref),[],'all'));
end
end

function n = bit_diff_frames(a, b)
n = 0;
for k = 1:numel(a)
    if any(a{k}.bits ~= b{k}.bits), n = n+1; end
end
end

function write_summary(path, packs, names)
fid = fopen(path,'w','n','UTF-8');
assert(fid>=0);
fprintf(fid,'format,round,portRounds,idxDiffPorts,newEqualPairs,maxAbsBetaDiff,firstCase,firstRound,firstPort,firstSlot\n');
floatPack = packs{1};
for f = 2:numel(packs)
    first = [0 0 0 0];
    for roundIndex = 1:3
        diffPorts = 0; pairs = 0; beta = 0; ports = 0;
        for k = 1:numel(packs{f})
            got = packs{f}{k}.trace.round(roundIndex);
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
            beta = max(beta, max(abs(got.betaAfter-ref.betaAfter)));
        end
        fprintf(fid,'%s,%d,%d,%d,%d,%.8g,%d,%d,%d,%d\n', names{f}, roundIndex, ports, diffPorts, pairs, beta, first(1), first(2), first(3), first(4));
    end
end
fclose(fid);
end

function write_frames(folder, packs, names, cases)
if ~exist(folder,'dir'), mkdir(folder); end
keep = unique([14 16 20 hard_cases(packs) first_idx_case(packs)]);
keep = keep(keep>0);
for k = keep
    for f = 1:numel(packs)
        dump_frame(fullfile(folder, sprintf('case_%02d_%s.csv', k, names{f})), packs{f}{k}, cases(k), k);
    end
end
fid = fopen(fullfile(folder,'帧清单.txt'),'w','n','UTF-8');
fprintf(fid,'保留帧号：%s\n', sprintf('%d ', keep));
fclose(fid);
end

function k = first_idx_case(packs)
k = 0;
for frame = 1:numel(packs{1})
    for f = 2:numel(packs)
        for roundIndex = 1:3
            if any(packs{f}{frame}.trace.round(roundIndex).idx ~= packs{1}{frame}.trace.round(roundIndex).idx,'all')
                k = frame; return;
            end
        end
    end
end
end

function keep = hard_cases(packs)
keep = [];
for frame = 1:numel(packs{1})
    for f = 2:numel(packs)
        if any(packs{f}{frame}.bits ~= packs{1}{frame}.bits)
            keep(end+1) = frame; %#ok<AGROW>
        end
    end
end
end

function dump_frame(path, pack, oneCase, frame)
fid = fopen(path,'w','n','UTF-8');
assert(fid>=0);
fprintf(fid,'case_index,%d,snr,%g\n', frame, oneCase.snrDB);
fprintf(fid,'truth'); fprintf(fid,',%d', oneCase.truth); fprintf(fid,'\n');
fprintf(fid,'bits'); fprintf(fid,',%d', pack.bits); fprintf(fid,'\n');
fprintf(fid,'llr'); fprintf(fid,',%.8g', pack.llr); fprintf(fid,'\n');
for roundIndex = 1:numel(pack.trace.round)
    rec = pack.trace.round(roundIndex);
    fprintf(fid,'round,%d\n', roundIndex);
    write_matrix(fid,'idx', rec.idx);
    write_matrix(fid,'idxPre', rec.idxPre);
    write_matrix(fid,'alphaPre', rec.alphaPre);
    write_matrix(fid,'alphaPost', rec.alphaPost);
    fprintf(fid,'newEqualPairs'); fprintf(fid,',%d', rec.newEqualPairs); fprintf(fid,'\n');
    fprintf(fid,'betaBefore'); fprintf(fid,',%.8g', rec.betaBefore); fprintf(fid,'\n');
    fprintf(fid,'betaAfter'); fprintf(fid,',%.8g', rec.betaAfter); fprintf(fid,'\n');
    fprintf(fid,'raw'); fprintf(fid,',%.8g', rec.raw); fprintf(fid,'\n');
end
if isfield(pack.trace,'readout') && isfield(pack.trace.readout,'max0')
    write_matrix(fid,'max0', squeeze(pack.trace.readout.max0));
    write_matrix(fid,'max1', squeeze(pack.trace.readout.max1));
end
fclose(fid);
end

function write_matrix(fid, label, value)
fprintf(fid,'%s', label);
for r = 1:size(value,1)
    fprintf(fid,'\nrow,%d', r);
    fprintf(fid,',%.8g', value(r,:));
end
fprintf(fid,'\n');
end
