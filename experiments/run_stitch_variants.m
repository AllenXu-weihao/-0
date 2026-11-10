function run_stitch_variants(outputDir)
% Pass a run-specific directory to keep the archived results intact.
% Stitch a few process-width combinations on the same 80 frames.
% The per-process minimum was already measured. These runs ask which
% combination keeps the frame error count down once the processes meet.
base = fileparts(fileparts(mfilename('fullpath')));
addpath(base);
addpath(fileparts(mfilename('fullpath')));
cases = make_cases(20, 1105);
n = numel(cases);
ref = cell(n, 1);
for k = 1:n
    ref{k} = MIMO(cases(k).input, 'float');
end
names = {'I2_S10_6','F_S24_14','I1_S24_14','I2_S24_14','I3_S24_14','R_S16_10','mild'};
widths = {
    [14 10; 10 6; 10 6; 16 10; 16 10; 8 4]
    [24 14; 10 6; 8 4; 16 10; 16 10; 8 4]
    [14 10; 24 14; 8 4; 16 10; 16 10; 8 4]
    [14 10; 10 6; 24 14; 16 10; 16 10; 8 4]
    [14 10; 10 6; 8 4; 24 14; 16 10; 8 4]
    [14 10; 10 6; 8 4; 16 10; 16 10; 16 10]
    [24 14; 20 12; 16 12; 16 10; 16 10; 16 10]
    };
if nargin < 1 || isempty(outputDir)
    root = fullfile(fileparts(mfilename('fullpath')), 'matlab位宽建模实验2_单计算过程协同压窄', 'result', '拼接对照');
else
    root = outputDir;
end
if ~exist(root, 'dir'), mkdir(root); end
fid = fopen(fullfile(root, 'summary.csv'), 'w', 'n', 'UTF-8');
assert(fid >= 0);
closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, 'name,candidateErrors,disagreements,saturations,e0,e10,e20,e30\n');
% With an explicit archive directory, retain the input and matched frame counts.
archiveFrames = nargin >= 1 && ~isempty(outputDir);
if archiveFrames
    save(fullfile(root,'inputs.mat'),'cases');
    fixedErrors = zeros(n,1);
    for k = 1:n
        fixed = MIMO(cases(k).input,'fixed_mvm');
        fixedErrors(k) = nnz(fixed.bits ~= cases(k).truth);
    end
    frameFile = fopen(fullfile(root,'per_frame.csv'),'w','n','UTF-8');
    assert(frameFile >= 0, 'Cannot write the baseline frame table.');
    frameCloser = onCleanup(@() fclose(frameFile)); %#ok<NASGU>
    fprintf(frameFile, 'name,seed,case_index,backgroundSNR,bits,floatErrors,fixedErrors,candidateErrors,disagreements,became_wrong,became_correct\n');
end
for v = 1:numel(names)
    fmt = stitch_format(widths{v});
    errN = 0; dis = 0; sat = 0; e = zeros(1, 4);
    for k = 1:n
        [r, st] = run_quantized(cases(k).input, fmt);
        ce = nnz(r.bits ~= cases(k).truth);
        if archiveFrames
            truth = cases(k).truth;
            refWrong = ref{k}.bits ~= truth;
            candidateWrong = r.bits ~= truth;
            newlyWrong = nnz(~refWrong & candidateWrong);
            newlyCorrect = nnz(refWrong & ~candidateWrong);
            fprintf(frameFile, '%s,%d,%d,%g,%d,%d,%d,%d,%d,%d,%d\n', ...
                names{v},cases(k).seed,k,cases(k).snrDB,numel(truth),nnz(refWrong), ...
                fixedErrors(k),ce,newlyWrong+newlyCorrect,newlyWrong,newlyCorrect);
        end
        errN = errN + ce;
        dis = dis + nnz(r.bits ~= ref{k}.bits);
        sat = sat + sat_requested(st, fieldnames(fmt));
        snr = cases(k).snrDB;
        if snr == 0, e(1) = e(1) + ce; elseif snr == 10, e(2) = e(2) + ce; elseif snr == 20, e(3) = e(3) + ce; else, e(4) = e(4) + ce; end
    end
    fprintf(fid, '%s,%d,%d,%d,%d,%d,%d,%d\n', names{v}, errN, dis, sat, e(1), e(2), e(3), e(4));
    fprintf('VARIANT %s err %d disagree %d snr %d/%d/%d/%d\n', names{v}, errN, dis, e(1), e(2), e(3), e(4));
end
fprintf('STITCH_VARIANTS_DONE\n');
end

function fmt = stitch_format(w)
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
        fmt.(stages{s}{i}) = struct('W', w(s, 1), 'F', w(s, 2));
    end
end
end

function sat = sat_requested(st, names)
sat = 0;
for i = 1:numel(names)
    if isfield(st, names{i})
        sat = sat + st.(names{i}).saturations;
    end
end
end
