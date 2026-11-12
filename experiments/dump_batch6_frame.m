function dump_batch6_frame()
% Dump item codes for the earliest damper disagreement. One frame, both widths.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
addpath(fullfile(root,'实验档案'));
addpath(fileparts(mfilename('fullpath')));
cd(root);
runId = 'E3_damp_rounding_s271111_a01_20261112_095229_tp28f349d0_9c3e_44e1_997c_fca86163588b';
prevId = 'E2-M_cross_sample_three_s271111_a01_20261111_012042_tpd5715780_d324_4b16_ba0e_9f21c35438d9';
raw = fullfile(root,'实验档案','01_运行记录',runId,'raw');
S = load(fullfile(root,'实验档案','01_运行记录',prevId,'raw','inputs.mat'),'cases');
note = fopen(fullfile(raw,'代表帧.txt'),'w','n','UTF-8');
assert(note>=0);
cleaner = onCleanup(@() fclose(note)); %#ok<NASGU>
specs = struct('name',{'W15_15_15','W21_19_17'},'Wa',{15,21},'Wr',{15,19},'Wb',{15,17});
for i = 1:numel(specs)
    fmt = point_format(specs(i).Wa, specs(i).Wr, specs(i).Wb);
    [~,st] = run_quantized(S.cases(1).input, fmt, struct('dampMode','A','dampAudit',true,'trace',true));
    roundIndex = 2;
    rawRow = st.trace.round(roundIndex).raw;
    betaRow = st.trace.round(roundIndex).betaBefore;
    Fr = fmt.raw.F; Fb = fmt.beta.F; Wb = fmt.beta.W;
    rawCode = round(rawRow*2^Fr);
    betaCode = round(betaRow*2^Fb);
    assert(all(imag(rawCode)==0) && all(imag(betaCode)==0));
    rawCode = real(rawCode);
    betaCode = real(betaCode);
    rec = damp_codes(rawCode, betaCode, Fr, Fb, Wb);
    fid = fopen(fullfile(raw, ['代表帧_' specs(i).name '.csv']),'w','n','UTF-8');
    fprintf(fid,'frame,round,item,port,slot,rawCode,betaCode,sumA,sumB,betaA,betaB,sumDiff,betaDiff\n');
    for at = 1:numel(rec.sumA)
        port = floor((at-1)/9)+1;
        slot = mod(at-1,9)+1;
        fprintf(fid,'1,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n', roundIndex, at, port, slot, ...
            rawCode(at), betaCode(at), rec.sumA(at), rec.sumB(at), rec.betaA(at), rec.betaB(at), ...
            rec.sumA(at)~=rec.sumB(at), rec.betaA(at)~=rec.betaB(at));
    end
    fclose(fid);
    A = load(fullfile(raw, ['cand_' specs(i).name '_A.mat']),'pack');
    B = load(fullfile(raw, ['cand_' specs(i).name '_B.mat']),'pack');
    hard = A.pack.bits ~= B.pack.bits;
    frame = find(any(hard,2), 1);
    bit = [];
    if ~isempty(frame), bit = find(hard(frame,:), 1); end
    fprintf(note,'%s 第 1 帧第 2 轮逐项码已写出。和差 %d/180，写回差 %d/180。\n', ...
        specs(i).name, nnz(rec.sumA~=rec.sumB), nnz(rec.betaA~=rec.betaB));
    if isempty(frame)
        fprintf(note,'%s 2048 帧没有硬判差。\n', specs(i).name);
    else
        fprintf(note,'%s 硬判首差 帧 %d 位 %d。A 错 %d，B 错 %d，|LLR| 最大 %.8g。\n', ...
            specs(i).name, frame, bit, A.pack.err(frame), B.pack.err(frame), max(abs(B.pack.llr(frame,:)-A.pack.llr(frame,:))));
    end
end
fprintf('FRAME_DUMP_DONE\n');
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
