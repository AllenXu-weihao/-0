function archive_edge_runs(R, runs)
% Normalize existing run_edge_experiment output; leave the source intact.
% Each candidate has one float-paired frame table and one SNR table.
m = jsondecode(fileread(R.manifest));
assert(strcmp(m.run_id,R.id),'Run ID and manifest disagree.');
assert(iscell(runs) && ~isempty(runs),'Expected one or more run_edge_experiment results.');
candidateRoot = fullfile(R.dir,'candidates');
if ~isfolder(candidateRoot), mkdir(candidateRoot); end
for k = 1:numel(runs)
    child = runs{k};
    edge = child.edge;
    assert(isvarname(edge) && ~isempty(regexp(child.runID,'^[A-Za-z0-9_-]+$','once')), ...
        'Unexpected edge or source ID.');
    format = child.formats.(edge);
    candidate = sprintf('%s_W%d_F%d',edge,format.W,format.F);
    dest = fullfile(candidateRoot,candidate);
    if isfolder(dest)
        prior = jsondecode(fileread(fullfile(dest,'source.json')));
        assert(strcmp(prior.original_run_id,child.runID),'This candidate points to a different source.');
        continue
    end
    % Snapshot once. Keep the original inputs, metrics, errors and native report.
    sourceDir = fullfile(R.project,'experiments','results',child.runID);
    raw = fullfile(R.raw,child.runID);
    if ~isfolder(raw)
        staging = tempname(R.raw);
        [ok,msg] = copyfile(sourceDir,staging);
        assert(ok,'Could not archive %s: %s',sourceDir,msg);
        [ok,msg] = movefile(staging,raw);
        assert(ok,'Could not publish raw copy: %s',msg);
    end
    saved = load(fullfile(raw,'result.mat'),'result');
    result = saved.result;
    assert(strcmp(result.runID,child.runID) && strcmp(result.edge,edge) && ...
        isequal(result.formats,child.formats),'Archived result and requested candidate disagree.');
    source = struct('run_id',m.run_id,'original_run_id',result.runID,'status',result.status, ...
        'candidate_id',candidate,'reference','MIMO(float)','formats',result.formats, ...
        'original_path',['experiments/results/' child.runID], ...
        'raw_path',['raw/' child.runID],'error',result.error);
    work = tempname(candidateRoot);
    mkdir(work);
    if ~strcmp(result.status,'ERROR')
        input = load(fullfile(raw,'inputs.mat'),'cases');
        frames = frame_table(result,input.cases,m,candidate);
        writetable(frames,fullfile(work,'per_frame.csv'));
        writetable(snr_table(frames),fullfile(work,'per_snr.csv'));
    end
    fid = fopen(fullfile(work,'source.json'),'w','n','UTF-8');
    assert(fid >= 0,'Cannot create candidate metadata.');
    closeFile = onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(source));
    clear closeFile
    [ok,msg] = movefile(work,dest);
    assert(ok,'Could not publish candidate: %s',msg);
end
end

function t = frame_table(result,cases,m,candidate)
a = result.metrics;
n = numel(cases);
assert(n>0 && height(a)==n,'Frame count mismatch.');
snr = reshape([cases.snrDB],[],1);
assert(all(snr==a.backgroundSNR) && all([cases.seed]==m.seed),'SNR/seed mismatch.');
sizes = reshape(arrayfun(@(x) numel(x.truth),cases),[],1);
assert(all(sizes==24) && all(a.bits==sizes),'Expected one 24-bit truth per case.');
counts = [a.floatErrors a.candidateErrors a.disagreements];
assert(all(isfinite(counts(:))) && all(counts(:)==floor(counts(:))) && ...
    all(counts(:)>=0 & counts(:)<=24),'Invalid frame counts.');
net = a.candidateErrors-a.floatErrors;
bad = (a.disagreements+net)/2;
good = (a.disagreements-net)/2;
assert(all(bad>=0 & bad==floor(bad) & good>=0 & good==floor(good) & ...
    good<=a.floatErrors & bad<=sizes-a.floatErrors),'Invalid paired counts.');
t = table(repmat(string(m.run_id),n,1),repmat(string(candidate),n,1), ...
    repmat(m.seed,n,1),(1:n)',snr,sizes,a.floatErrors,a.candidateErrors,bad,good, ...
    a.disagreements,a.llrMaxVsFloat,a.edgeSaturations,'VariableNames', ...
    {'run_id','candidate_id','seed','case_index','snr_db','n_bits','reference_errors', ...
    'candidate_errors','became_wrong','became_correct','disagreements','llr_max_abs','saturations'});
end

function t = snr_table(f)
snr = unique(f.snr_db);
n = numel(snr);
counts = zeros(n,8);
for j=1:n
    sub = f(f.snr_db==snr(j),:);
    counts(j,:) = [height(sub),sum(sub.n_bits),sum(sub.reference_errors), ...
        sum(sub.candidate_errors),sum(sub.became_wrong),sum(sub.became_correct), ...
        sum(sub.disagreements),sum(sub.saturations)];
end
t = table(repmat(f.run_id(1),n,1),repmat(f.candidate_id(1),n,1), ...
    repmat(f.seed(1),n,1),snr,'VariableNames',{'run_id','candidate_id','seed','snr_db'});
t = [t,array2table(counts,'VariableNames',{'n_frames','n_bits','reference_errors', ...
    'candidate_errors','became_wrong','became_correct','disagreements','saturations'})];
t.reference_ber = t.reference_errors./t.n_bits;
t.candidate_ber = t.candidate_errors./t.n_bits;
t.delta_ber = (t.became_wrong-t.became_correct)./t.n_bits;
end
