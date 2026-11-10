function R = new_run(experiment, label, seed, attempt)
% Create one archive for a planned run. Run from the MIMO_v2_matlab project.
experiment = validatestring(experiment, {'E0','E1','E2','E2-M','E3','E3-H','E4','E5'});
label = char(label);
assert(~isempty(regexp(label, '^[A-Za-z0-9][A-Za-z0-9_-]{0,47}$', 'once')), ...
    'Use a short ASCII run label, e.g. baseline or alpha.');
validateattributes(seed, {'numeric'}, {'scalar','integer','>=',0,'<=',2^32-1});
validateattributes(attempt, {'numeric'}, {'scalar','integer','positive'});
archive = fileparts(mfilename('fullpath'));
R.project = fileparts(archive);
parent = fullfile(archive,'01_运行记录');
[~, token] = fileparts(tempname(parent));
R.id = sprintf('%s_%s_s%.0f_a%02d_%s_%s',experiment,label,seed,attempt, ...
    datestr(now,'yyyymmdd_HHMMSS'),token);
R.dir = fullfile(parent,R.id);
R.raw = fullfile(R.dir,'raw');
R.manifest = fullfile(R.dir,'manifest.json');
m = struct('schema_version',1,'run_id',R.id,'experiment',experiment,'label',label, ...
    'attempt',attempt,'previous_run_id','','seed',seed,'status','PLANNED', ...
    'matlab_version',version,'machine',computer,'created_utc', ...
    char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd HH:mm:ss')), ...
    'deployment_sha256','','mimo_sha256','','driver_revision','','entry_command','', ...
    'dataset_role','','cases_path','','reference','','candidate_ids',{{}}, ...
    'matrix_arithmetic','','architecture','','decision_rule','','raw_sources',{{}}, ...
    'figures',{{}},'report','','error','');
if usejava('jvm')
    m.deployment_sha256 = file_sha256(fullfile(R.project,'deployment.mat'));
    m.mimo_sha256 = file_sha256(fullfile(R.project,'MIMO.m'));
end
assert(~exist(R.dir,'file'), 'Run ID already exists; call new_run again.');
[ok,message,id] = mkdir(R.dir);
assert(ok && isempty(id), 'Could not reserve a new run folder: %s',message);
mkdir(R.raw);
copyfile(fullfile(archive,'00_实验设计','单次实验协议.md'),fullfile(R.dir,'protocol.md'));
[fid,message] = fopen(R.manifest,'w','n','UTF-8');
assert(fid >= 0,'Cannot write manifest: %s',message);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(m));
fprintf('Run %s\n%s\n',R.id,R.dir);
end

function value = file_sha256(path)
[fid,message] = fopen(path,'rb');
assert(fid >= 0,'Cannot hash %s: %s',path,message);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
md = java.security.MessageDigest.getInstance('SHA-256');
while ~feof(fid)
    chunk = fread(fid,65536,'*uint8');
    if ~isempty(chunk), md.update(typecast(chunk,'int8')); end
end
bytes = typecast(md.digest(),'uint8');
value = lower(reshape(dec2hex(bytes,2).',1,[]));
end
