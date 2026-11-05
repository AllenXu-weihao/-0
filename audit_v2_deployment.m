function report = audit_v2_deployment(outputDir)
% Deployment facts and two existing golden checks; NOT a width sweep.
base = fileparts(mfilename('fullpath'));
if nargin < 1, outputDir = fullfile(base,'audit_results'); end
if ~exist(outputDir,'dir'), mkdir(outputDir); end
s = load(fullfile(base,'deployment.mat'),'pack'); p = s.pack;
report = struct('timestamp',datestr(now,30),'runtime',p.profile.runtime, ...
    'config',p.config,'fixed_passes',p.profile.fixed_passes);
names = {'A2','A13','A5'};
for k = 1:numel(names)
    name = names{k}; A = double(p.profile.matrix.(name));
    fanin = sum(A~=0,1);
    q = max(-2^17,min(2^17-1,round(A*2^14)));
    report.matrix.(name) = struct('size',size(A),'nnz',nnz(A), ...
        'fanin_by_output_column',fanin,'max_fanin',max(fanin), ...
        'min',min(A(:)),'max',max(A(:)), ...
        'weight_saturations',nnz(round(A*2^14)<-2^17 | round(A*2^14)>2^17-1), ...
        'weight_quantization_max_error',max(abs(A(:)-q(:)/2^14)), ...
        'width_spec',p.profile.matrices.(name));
end
oldPath=path; cleanup=onCleanup(@()path(oldPath)); %#ok<NASGU>
addpath(base,'-begin'); clear MIMO;
[rf,af]=MIMO(p.example,'float');
[rq,aq]=MIMO(p.example,'fixed_mvm');
report.floatGoldenError=max(abs(rf.trajectory-p.expectedFloat),[],'all');
report.fixedGoldenError=max(abs(rq.trajectory-p.expectedFixed),[],'all');
report.floatAudit=af; report.fixedAudit=aq;
report.llrMaxDifference=max(abs(rf.llr-rq.llr),[],'all');
report.hardDecisionDisagreements=nnz(rf.bits~=rq.bits);
report.note='Golden only. No BER without transmitted truth; no full peripheral quantization.';
save(fullfile(outputDir,'deployment_audit.mat'),'report');
fid=fopen(fullfile(outputDir,'deployment_audit.json'),'w','n','UTF-8');
assert(fid>=0,'Cannot create report'); closeFile=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',jsonencode(report));
assert(report.floatGoldenError<1e-9,'Float golden mismatch; inspect saved audit');
assert(report.fixedGoldenError<1e-9,'Fixed MVM golden mismatch; inspect saved audit');
fprintf('Both existing golden checks passed. This does not validate compressed widths.\n');
end
