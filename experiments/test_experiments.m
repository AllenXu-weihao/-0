function test_experiments()
% Run on MATLAB before sweeps. No toolboxes required.
base=fileparts(fileparts(mfilename('fullpath')));addpath(base);s=load(fullfile(base,'deployment.mat'),'pack');p=s.pack;
[r,~]=MIMO(p.example,'float');assert(max(abs(r.trajectory-p.expectedFloat),[],'all')<1e-9);
[q,~]=MIMO(p.example,'fixed_mvm');assert(max(abs(q.trajectory-p.expectedFixed),[],'all')<1e-9);
[z,~]=run_quantized(p.example,struct());assert(max(abs(z.trajectory-r.trajectory),[],'all')<1e-9,'Instrumentation changed prepared reference');
cases=make_cases(1,91);
for k=1:numel(cases)
 a=MIMO(cases(k).input,'float');b=run_quantized(cases(k).input,struct());assert(max(abs(a.llr-b.llr),[],'all')<1e-9,'Raw reference mismatch');
end
global MIMO_EXPERIMENT
old=MIMO_EXPERIMENT;clean=onCleanup(@()restore(old)); %#ok<NASGU>
MIMO_EXPERIMENT=struct('formats',struct('test',struct('W',4,'F',2)),'stats',struct());
y=qedge('test',[-.125 .125 -3 3]);assert(isequal(y,[-.25 .25 -2 1.75]));
assert(MIMO_EXPERIMENT.stats.test.saturations==2);
f=struct('A2_product',struct('W',42,'F',26),'A2_acc',struct('W',45,'F',26));
MIMO_EXPERIMENT=struct('formats',f,'stats',struct());
y=experiment_mvm('A2',[1 -2],[.5 1;2 -.25]);assert(isequal(y,[-3.5 1.5]));
fprintf('Golden, instrumentation, quantizer and small ordered MAC tests passed.\n');
end
function restore(s)
global MIMO_EXPERIMENT
MIMO_EXPERIMENT=s;
end
