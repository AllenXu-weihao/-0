function [result,stats]=run_quantized(input,formats)
% Restores global state even after a failed candidate.
global MIMO_EXPERIMENT
previous=MIMO_EXPERIMENT;c=onCleanup(@()restore(previous)); %#ok<NASGU>
MIMO_EXPERIMENT=struct('formats',formats,'stats',struct());
[result,~]=mimo_instrumented(input,'float');stats=MIMO_EXPERIMENT.stats;
requested=fieldnames(formats);
for k=1:numel(requested),assert(isfield(stats,requested{k}),'Requested edge was not exercised: %s',requested{k});end
end
function restore(s)
global MIMO_EXPERIMENT
MIMO_EXPERIMENT=s;
end
