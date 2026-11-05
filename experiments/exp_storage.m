function report=exp_storage()
% Exact payload accounting from deployment; not a synthesis resource report.
b=fileparts(fileparts(mfilename('fullpath')));s=load(fullfile(b,'deployment.mat'),'pack');
names={'A2','A13','A5'};rows=zeros(3,7);
for k=1:3
 A=s.pack.profile.matrix.(names{k});[R,C]=size(A);N=nnz(A);addr=max(1,ceil(log2(R)));ptr=max(1,ceil(log2(N+1)));
 rows(k,:)=[R,C,N,numel(A)*18,N*(18+addr)+(C+1)*ptr,max(sum(A~=0,1)),addr];
end
report=array2table(rows,'VariableNames',{'rows','cols','nnz','denseBits','sparseBits','maxFanin','rowAddressBits'},'RowNames',names);
out=fullfile(fileparts(mfilename('fullpath')),'results',['storage_' datestr(now,'yyyymmdd_HHMMSS')]);if ~exist(out,'dir'),mkdir(out);end
writetable(report,fullfile(out,'storage.csv'),'WriteRowNames',true);save(fullfile(out,'storage.mat'),'report');
f=fopen(fullfile(out,'report.md'),'w','n','UTF-8');assert(f>=0);c=onCleanup(@()fclose(f)); %#ok<NASGU>
fprintf(f,'# 存储实验\n\n## 实验目的\n从部署包比较18位稠密系数与按输出列压缩的有效容量。\n\n## 实验结果\n见storage.csv。稠密合计 %d bit，稀疏合计 %d bit。\n\n## 结论\n仅容量计算完成；未综合，不据此宣布BRAM块数。\n\n## 分析\n稀疏记录包含系数、行地址和列指针；未计对齐、bank、副本、端口约束及控制。实际资源须结合读写调度和器件配置。\n',sum(report.denseBits),sum(report.sparseBits));
end
