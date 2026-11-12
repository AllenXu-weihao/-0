function [result,stats]=run_quantized(input,formats,opts)
% Restores global state even after a failed candidate.
% opts.orderedObserve walks each nonzero and records the double product
% and running sum. opts.logEdges is [lo hi] for a log2 magnitude histogram.
global MIMO_EXPERIMENT
if nargin<3,opts=struct();end
previous=MIMO_EXPERIMENT;c=onCleanup(@()restore(previous)); %#ok<NASGU>
ex=struct('formats',formats,'stats',struct());
if isfield(opts,'orderedObserve'),ex.orderedObserve=logical(opts.orderedObserve);end
if isfield(opts,'logEdges'),ex.logEdges=opts.logEdges;end
if isfield(opts,'recordSaturation'),ex.recordSaturation=logical(opts.recordSaturation);end
if isfield(opts,'dampMode'),ex.dampMode=opts.dampMode;end
if isfield(opts,'dampAudit'),ex.dampAudit=logical(opts.dampAudit);end
if isfield(opts,'trace') && logical(opts.trace)
 ex.trace=struct('enabled',true);
 ex.traceLog=struct();
end
MIMO_EXPERIMENT=ex;
[result,~]=mimo_instrumented(input,'float');stats=MIMO_EXPERIMENT.stats;
if isfield(MIMO_EXPERIMENT,'traceLog'),stats.trace=MIMO_EXPERIMENT.traceLog;end
if isfield(MIMO_EXPERIMENT,'dampAuditLog'),stats.dampAudit=MIMO_EXPERIMENT.dampAuditLog;end
requested=fieldnames(formats);
for k=1:numel(requested),assert(isfield(stats,requested{k}),'Requested edge was not exercised: %s',requested{k});end
end
function restore(s)
global MIMO_EXPERIMENT
MIMO_EXPERIMENT=s;
end
