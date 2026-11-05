function runs=run_edge_experiment(edge,formats,cases)
% One edge per run. All downstream computations and iterations are rerun.
% formats: N-by-2 [total width, fraction]. No automatic BER acceptance.
if nargin<3,cases=make_cases();end
assert(size(formats,2)==2);test_experiments();
base=fileparts(fileparts(mfilename('fullpath')));addpath(base);
assert(all(arrayfun(@(x)numel(x.truth)==24,cases)),'Each raw frame needs 24 transmitted bits');
ref=cell(size(cases));fixed=cell(size(cases));
for k=1:numel(cases),ref{k}=MIMO(cases(k).input,'float');fixed{k}=MIMO(cases(k).input,'fixed_mvm');end
runs=cell(size(formats,1),1);
for f=1:size(formats,1)
 fmt=struct();fmt.(edge)=struct('W',formats(f,1),'F',formats(f,2));
 [~,token]=fileparts(tempname);runID=[datestr(now,'yyyymmdd_HHMMSS') '_' edge '_' token];
 folder=fullfile(fileparts(mfilename('fullpath')),'results',runID);mkdir(folder);
 result=struct('runID',runID,'edge',edge,'formats',fmt,'status','UNVERIFIED', ...
 'note','No numeric acceptance threshold. BLER not evaluated. Background SNR.', ...
 'matlabVersion',version,'metrics',[],'stats',{{}},'error','');
 save(fullfile(folder,'inputs.mat'),'cases');
 try
  rows=zeros(numel(cases),9);
  for k=1:numel(cases)
   [r,st]=run_quantized(cases(k).input,fmt);result.stats{k}=st;
   rows(k,:)=[cases(k).snrDB,24,nnz(ref{k}.bits~=cases(k).truth),nnz(fixed{k}.bits~=cases(k).truth),nnz(r.bits~=cases(k).truth),nnz(r.bits~=ref{k}.bits),max(abs(r.llr-ref{k}.llr),[],'all'),max(abs(r.llr-fixed{k}.llr),[],'all'),st.(edge).saturations];
  end
  result.metrics=array2table(rows,'VariableNames',{'backgroundSNR','bits','floatErrors','fixedErrors','candidateErrors','disagreements','llrMaxVsFloat','llrMaxVsFixed','edgeSaturations'});
  writetable(result.metrics,fullfile(folder,'per_frame.csv'));
  snrs=unique(rows(:,1));summary=zeros(numel(snrs),6);
  for j=1:numel(snrs)
   m=rows(:,1)==snrs(j);N=sum(rows(m,2));summary(j,:)=[snrs(j),N,sum(rows(m,3:5),1)/N,max(rows(m,7))];
  end
  result.summary=array2table(summary,'VariableNames',{'backgroundSNR','bits','floatBER','fixedBER','candidateBER','llrMaxVsFloat'});writetable(result.summary,fullfile(folder,'summary.csv'));
 catch err
  result.status='ERROR';result.error=getReport(err,'extended','hyperlinks','off');
 end
 save(fullfile(folder,'result.mat'),'result');write_report(folder,result);runs{f}=result;
end
end
function write_report(folder,r)
fid=fopen(fullfile(folder,'report.md'),'w','n','UTF-8');assert(fid>=0);c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'# %s\n\n## 实验目的\n仅量化 `%s`，其余边界保持浮点，完整重算前端、下游和反馈轮次。与原始float及fixed_mvm成对比较。\n\n配置：%s\n\n',r.runID,r.edge,jsonencode(r.formats));
fprintf(fid,'## 实验结果\n状态：%s。MATLAB：%s。\n\n',r.status,r.matlabVersion);
if ~isempty(r.metrics)
 fprintf(fid,'见 per_frame.csv 与 summary.csv；原始输入见 inputs.mat，逐边统计见 result.mat。\n\n');
 fprintf(fid,'总比特 %d；参考/现有定点/候选误码 %d / %d / %d；最大LLR误差 %.8g。\n',sum(r.metrics.bits),sum(r.metrics.floatErrors),sum(r.metrics.fixedErrors),sum(r.metrics.candidateErrors),max(r.metrics.llrMaxVsFloat));
end
fprintf(fid,'\n## 结论\n未设正式BER/BLER劣化阈值，不能宣布通过或冻结位宽。BLER未评估。默认小样本仅作冒烟测试，无置信区间，不支持性能结论。\n\n## 分析\n结合逐SNR误码、饱和与逐边误差定位传播；单边结果不能代替联合量化验证。内部求解/log/exp仍为double；本实验为指定边界量化。\n');
if ~isempty(r.error),fprintf(fid,'\n执行失败记录：\n```\n%s\n```\n',r.error);end
end
