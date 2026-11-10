% Derived from MIMO.m. Run test_experiments before any sweep.
function [result,audit]=mimo_instrumented(input,mode)
% MIMO Standalone MATLAB implementation for FPGA translation.
% MIMO() runs included golden example; no common folder/Python required.
% MIMO(input,'float') = reference; 'fixed_mvm' quantizes array interfaces only.
% Nonlinear peripherals are algorithm references, not completed HDL or LUT IP.
if nargin<2,mode='float';end
assert(any(strcmp(mode,{'float','fixed_mvm'})));
p=load_package();demo=nargin==0;if demo,input=p.example;end
task='mimo';
if ~isfield(input,'local'),input=frontend(task,input,p);end
[z,audit]=pkg_vf_infer(task,input,p.profile,p.profile.fixed_passes,mode);result=readout(task,z,input);
if demo,expected=p.expectedFloat;if strcmp(mode,'fixed_mvm'),expected=p.expectedFixed;end;audit.goldenMaxError=max(abs(z-expected),[],'all');assert(audit.goldenMaxError<1e-9);fprintf('%s golden PASS, %d iterations, error %g\n',task,p.profile.fixed_passes,audit.goldenMaxError);end
end

function p=load_package()
persistent cached
if isempty(cached),s=load(fullfile(fileparts(fileparts(mfilename('fullpath'))),'deployment.mat'),'pack');cached=s.pack;end
p=cached;
end
function restore_audit(previous)
global VFINAL_MATRIX_AUDIT
VFINAL_MATRIX_AUDIT=previous;
end

function d=frontend(task,input,p)
% Observation-only frontend. No transmitted bits/true channel enter inference.
y=double(input.y(:).');assert(numel(y)==8);nv=double(input.noiseVar);iv=double(input.impulseExtraVar);
assert(isscalar(nv)&&isscalar(iv)&&isfinite(nv)&&isfinite(iv)&&nv>0&&iv>0);
y=qedge('input_y',y);nv=qedge('input_nv',nv);iv=qedge('input_iv',iv);assert(nv>0&&iv>0);
d=struct('yReal',real(y),'yImag',imag(y),'noiseVar',nv,'impulseVar',iv);
 H=qedge('input_H',double(input.H));assert(isequal(size(H),[8 4]));[constellation,bitTable]=qam64_table();
 [~,~,local,idx]=pkg_mimo_candidate_frontend(y.',H,nv,iv,constellation,bitTable,p.config);
 c=constellation(idx);d.candidateReal=reshape(real(c),1,9,4);d.candidateImag=reshape(imag(c),1,9,4);
 d.local=qedge('frontend_local',reshape(local,1,[]));d.Hreal=reshape(real(H),1,8,4);d.Himag=reshape(imag(H),1,8,4);
 cb=zeros(1,9,4,6);for v=1:4,cb(1,:,v,:)=reshape(bitTable(idx(:,v),:),1,9,1,6);end;d.candidateBit=cb;
end
function value=stable_logadd(a,b)
m=max(a,b);value=m+log(exp(a-m)+exp(b-m));
end
function [c,b]=qam64_table()
level=-7:2:7;gray=bitxor(0:7,floor((0:7)/2));c=zeros(64,1);b=zeros(64,6);q=0;
for i=1:8,for r=1:8,q=q+1;c(q)=(level(i)+1i*level(r))/sqrt(42);b(q,1:3)=bitget(gray(i),3:-1:1);b(q,4:6)=bitget(gray(r),3:-1:1);end,end
end
function result=readout(task,z,d)
result=struct('trajectory',z,'actualIterations',size(z,2));
if strcmp(task,'ldpc'),result.llr=reshape(z(:,end,:),size(z,1),38);result.bits=result.llr<0;result.informationBits=result.bits(:,1:25);return;end
B=size(z,1);L=size(z,4);last=reshape(z(:,end,:,:),B,4,L);
if strcmp(task,'channel')
 prob=exp(last-max(last,[],3));prob=prob./sum(prob,3);c=permute(complex(d.candidateReal,d.candidateImag),[1 3 2]);
 result.estimate=sum(prob.*c,3);result.probability=prob;
else
 assert(isfield(d,'candidateBit'),'Prepared MIMO input must provide constellation bit labels.');
 cb=permute(d.candidateBit,[1 3 2 4]);llr=zeros(B,4,6);max0=[];max1=[];
 if tracing()
  max0=zeros(B,4,6);max1=zeros(B,4,6);
  for bit=1:6,a=last;b=last;a(cb(:,:,:,bit)~=0)=-1e6;b(cb(:,:,:,bit)==0)=-1e6;max0(:,:,bit)=max(a,[],3);max1(:,:,bit)=max(b,[],3);llr(:,:,bit)=max0(:,:,bit)-max1(:,:,bit);end
 else
  for bit=1:6,a=last;b=last;a(cb(:,:,:,bit)~=0)=-1e6;b(cb(:,:,:,bit)==0)=-1e6;llr(:,:,bit)=max(a,[],3)-max(b,[],3);end
 end
 unclipped=llr;
 result.llr=reshape(permute(max(-20,min(20,llr)),[1 3 2]),B,24);result.llr=qedge('llr',result.llr);result.bits=result.llr<0;
 if tracing(),trace_readout(unclipped,result.llr,result.bits,max0,max1);end
end
end

% ===== vf_fixed_mvm =====
function [y,audit]=pkg_vf_fixed_mvm(x,A,width)
% Bit-accurate integer MAC reference within proven <=53-bit integer range.
% This simulates array interfaces; it is NOT a power estimate or full RTL.
assert(size(x,2)==size(A,1));assert(width.accumulator_bits<=53);
inputBits=24;if isfield(width,'input_bits'),inputBits=width.input_bits;end
outputBits=inputBits;if isfield(width,'output_bits'),outputBits=width.output_bits;end
[xi,ins]=pkg_vf_quantize(x,inputBits,12);[wi,ws]=pkg_vf_quantize(A,18,14);
acc=xi*wi;
assert(all(acc(:)>=-2^(width.accumulator_bits-1) & acc(:)<2^(width.accumulator_bits-1)),'Accumulator overflow');
[yi,outs]=pkg_vf_quantize(acc/2^26,outputBits,12);y=yi/2^12;
audit=struct('inputSaturations',ins.saturations,'weightSaturations',ws.saturations, ...
 'outputSaturations',outs.saturations,'accumulatorBits',width.accumulator_bits, ...
 'maxAbsInput',max(abs(double(x)),[],'all'),'maxAbsOutput',max(abs(y),[],'all'), ...
 'maxAbsErrorVsFloat',max(abs(y-double(x)*double(A)),[],'all'));
end


% ===== vf_quantize =====
function [q,stats]=pkg_vf_quantize(x,bits,fraction)
% Signed fixed point. MATLAB round uses nearest with half ties away from zero.
assert(all(isfinite(x(:))),'Vfinal:Nonfinite','Invalid states require a separate valid flag.');
assert(bits>=2 && bits<=52 && fraction>=0 && fraction<bits);
scaled=round(double(x)*2^fraction);lo=-2^(bits-1);hi=2^(bits-1)-1;
stats.saturations=nnz(scaled<lo|scaled>hi);q=max(lo,min(hi,scaled));
stats.maxAbsError=max(abs(q(:)/2^fraction-double(x(:))),[],'omitnan');
end


% ===== vf_infer =====
function [output,audit]=pkg_vf_infer(task,d,p,steps,mode)
% Native MATLAB reference for FINAL kernels. Fixed mode quantizes MVM only.
% Peripheral math remains floating reference; no claim of full fixed-point RTL.
if nargin<5,mode='float';end
assert(any(strcmp(mode,{'float','fixed_mvm'})));A=p.matrix;
audit=struct('mvmCalls',0,'inputSaturations',0,'outputSaturations',0,'maxMvmError',0,'maxAbsInput',0,'maxAbsOutput',0);
cfg=p.runtime.config;groups=p.runtime.groups;if ~iscell(groups),groups=num2cell(groups,2);end
for g=1:numel(groups),groups{g}=double(groups{g}(:).')+1;end
L=9;if strcmp(task,'channel'),L=21;end
pv=[];ports=cell(size(groups));
for g=1:numel(groups)
 scope=1:4;if strcmp(task,'channel'),scope=unique([groups{g},mod(groups{g},4)+1]);end
 ports{g}=numel(pv)+(1:numel(scope));pv=[pv scope]; %#ok<AGROW>
end
B=size(d.local,1);P=numel(pv);S=P*L;output=zeros(B,steps,4,L);
pilot=sqrt(8/3)*[1 0 0 0 1 0 0 1;0 1 0 0 1 1i 0 0;0 0 1 0 0 1 1i 0;0 0 0 1 0 0 1 -1i];
for b=1:B
 c=double(squeeze(complex(d.candidateReal(b,:,:),d.candidateImag(b,:,:))).');
 y=double(complex(d.yReal(b,:),d.yImag(b,:)));nv=double(d.noiseVar(b));iv=double(d.impulseVar(b));
 local=double(d.local(b,:));beta=zeros(1,S);
 if strcmp(task,'mimo')
  local=local*cfg.mimoPriorScale;H=double(squeeze(complex(d.Hreal(b,:,:),d.Himag(b,:,:))));
  order=vf_infer__receiver_order(H,cfg);H=H(order,:);y=y(order);
 end
 for t=1:steps
  alpha=reshape(vf_infer__mv('A2',[beta local]),L,P).';alpha=alpha-max(alpha,[],2);
  if strcmp(task,'mimo'),alpha=alpha*cfg.mimoAlphaScale;end
  alphaPre=alpha;
  alpha=qedge('alpha',alpha);
  [a,idx]=sort(alpha,2,'descend');cs=zeros(P,L);
  for j=1:P,cs(j,:)=c(pv(j),idx(j,:));end
  temp=1;if strcmp(task,'mimo'),temp=cfg.mimoSoftIcTemperature;end
  prob=qedge('exp',exp(a/temp-max(a/temp,[],2)));den=qedge('sum_exp',sum(prob,2));assert(all(den>0));prob=qedge('prob',prob./den);
  mu=qedge('mu',sum(prob.*cs,2));varr=qedge('var',sum(prob.*abs(cs-mu).^2,2));lambda=[];
  if strcmp(task,'mimo')
   for rx=1:8
    g=find(cellfun(@(x)ismember(rx,x),groups));pp=ports{g};
    for v=1:4
     q=pp(v);residual=y(rx)-H(rx,:)*mu(pp)+H(rx,v)*(mu(q)-cs(q,:));
     residual=qedge('residual',residual);weighted=qedge('weighted',abs(H(rx,:)).^2.*varr(pp).');extra=max(0,sum(weighted)-weighted(v))*cfg.mimoSoftIcVarianceScale;
     lambda=[lambda vf_infer__mix(residual,nv+extra,iv+extra,cfg.channelImpulseEpsilon)]; %#ok<AGROW>
    end
   end
   lambda=qedge('lambda',lambda*cfg.mimoLambdaScale);ai=a;mx=max(a,[],2);ai(:,1)=mx+log(sum(exp(a-mx),2));
  else
   for g=1:numel(groups)
    for q=ports{g}
     target=pv(q);
     for obs=groups{g}
      if pilot(target,obs+4)==0,continue;end
      residual=y(obs+4)-pilot(target,obs+4)*cs(q,:);extra=0;
      for peer=ports{g}
       if peer==q || pilot(pv(peer),obs+4)==0,continue;end
       residual=residual-pilot(pv(peer),obs+4)*mu(peer);extra=extra+abs(pilot(pv(peer),obs+4))^2*varr(peer);
      end
      lambda=[lambda vf_infer__mix(residual,nv+extra,iv+extra,cfg.channelImpulseEpsilon)]; %#ok<AGROW>
     end
    end
   end
   ai=a;
  end
  ai=qedge('ai',ai);score=reshape(vf_infer__mv('A13',[lambda reshape(ai.',1,[])]),L,P).';raw=zeros(P,L);
  for j=1:P,raw(j,idx(j,:))=score(j,:);end
  raw=raw-max(raw,[],2);raw=reshape(raw.',1,[]);
  if strcmp(task,'mimo'),raw=raw*cfg.mimoBetaScale;end
  raw=qedge('raw',raw);rate=qedge('rate',p.runtime.rate);betaBefore=beta;d0=qedge('damp_product_old',(1-rate)*beta);d1=qedge('damp_product_new',rate*raw);beta=qedge('beta',qedge('damp_sum',d0+d1));
  if tracing(),[~,idxPre]=sort(alphaPre,2,'descend');trace_iter(t,alphaPre,alpha,idxPre,idx,raw,betaBefore,beta);end
  bi=beta;li=local;
  if strcmp(task,'mimo'),bi=bi*cfg.mimoPosteriorBetaScale;li=li*cfg.mimoPosteriorPriorScale;end
  z=reshape(vf_infer__mv('A5',[bi li]),L,4).';output(b,t,:,:)=reshape(z,1,1,4,L);
 end
end
 function y=vf_infer__mv(stage,x)
  audit.mvmCalls=audit.mvmCalls+1;
  if strcmp(mode,'float'),y=experiment_mvm(stage,x,double(A.(stage)));return;end
  [y,s]=pkg_vf_fixed_mvm(x,double(A.(stage)),p.matrices.(stage));
  audit.inputSaturations=audit.inputSaturations+s.inputSaturations;audit.outputSaturations=audit.outputSaturations+s.outputSaturations;
  audit.maxMvmError=max(audit.maxMvmError,s.maxAbsErrorVsFloat);
  audit.maxAbsInput=max(audit.maxAbsInput,s.maxAbsInput);audit.maxAbsOutput=max(audit.maxAbsOutput,s.maxAbsOutput);
 end
end
function y=vf_infer__mix(r,nv,iv,ep)
a=log(1-ep)-log(pi*nv)-abs(r).^2/nv;b=log(ep)-log(pi*iv)-abs(r).^2/iv;
a=qedge('mix_a',a);b=qedge('mix_b',b);m=max(a,b);y=qedge('mix_output',m+log(exp(a-m)+exp(b-m)));
end
function order=vf_infer__receiver_order(H,cfg)
power=sum(abs(H).^2,2);[~,order]=sort(power);order=order(:).';
if ~isfield(cfg,'receiver_order_policy') || strcmp(cfg.receiver_order_policy,'energy'),return;end
assert(strcmp(cfg.receiver_order_policy,'correlation_groups'));
h=H(order,:);power=sum(abs(h).^2,2);rho=abs(h*h').^2./max(power*power',1e-12);e=power/mean(power);
w=1;if isfield(cfg,'grouping_energy_weight'),w=cfg.grouping_energy_weight;end
pairs=nchoosek(2:8,2);cost=zeros(size(pairs,1),1);
for k=1:numel(cost),i=pairs(k,1);j=pairs(k,2);cost(k)=rho(1,i)+rho(1,j)+rho(i,j)+w*(e(i)+e(j));end
[~,k]=min(cost);triple=[1 pairs(k,:)];rest=setdiff(1:8,triple);pairs=nchoosek(rest,2);cost=zeros(size(pairs,1),1);
for k=1:numel(cost),i=pairs(k,1);j=pairs(k,2);cost(k)=rho(i,j)+w*(e(i)+e(j));end
[~,k]=min(cost);pair=pairs(k,:);order=order([triple pair setdiff(rest,pair)]);
end

% ===== mimo_candidate_frontend =====
function [candidateScore,lmmseScore,localScore,candidateIndex] = ...
    pkg_mimo_candidate_frontend(y,H,noiseVar,impulseVar,constellation,bitTable,cfg)
%MIMO_CANDIDATE_FRONTEND Fixed-size robust Top-L candidate construction.
%
% The output always contains exactly cfg.mimoStateCount states per transmit
% variable. The same fixed frontend is used by the all-one and learned paths.

Nt = cfg.Nt;
L = cfg.mimoStateCount;
epsilon = cfg.channelImpulseEpsilon;
residualWeight = cfg.mimoCandidateResidualWeight;
coverageGap = cfg.mimoCandidateBitCoverageGap;

A = qedge('frontend_gram',H'*H+noiseVar*eye(Nt));
xhat = qedge('frontend_center',A\qedge('frontend_rhs',H'*y));
covariance = qedge('frontend_cov',A\eye(Nt));
variance=qedge('frontend_variance',max(real(diag(covariance)),1e-8));assert(all(variance>0));
nConstellation = numel(constellation);
lmmseScore = zeros(nConstellation,Nt);
candidateScore = zeros(nConstellation,Nt);
localScore = zeros(L,Nt);
candidateIndex = zeros(L,Nt);

for v = 1:Nt
    scoreLmmse = -abs(constellation-xhat(v)).^2./(2*variance(v));
    scoreLmmse = scoreLmmse-max(scoreLmmse);
    residualWithoutTarget = y-H*xhat+H(:,v)*xhat(v);
    scoreResidual = zeros(nConstellation,1);
    for k = 1:nConstellation
        residual = residualWithoutTarget-H(:,v)*constellation(k);
        scoreResidual(k) = sum(mimo_candidate_frontend__mixture_log_likelihood_vector( ...
            residual,noiseVar,impulseVar,epsilon));
    end
    scoreResidual = scoreResidual-max(scoreResidual);
    score=qedge('frontend_score',scoreLmmse+residualWeight*scoreResidual);
    [~,order] = sort(score,'descend');
    keep = mimo_candidate_frontend__confidence_gated_bit_coverage(order,score,bitTable,L,coverageGap);
    lmmseScore(:,v) = scoreLmmse;
    candidateScore(:,v) = score;
    candidateIndex(:,v) = keep;
    value = score(keep);
    localScore(:,v) = value-max(value);
end
end

function keep = mimo_candidate_frontend__confidence_gated_bit_coverage(order,score,bitTable,L,gapLimit)
keep = order(1:L);
nBit = size(bitTable,2);
for pass = 1:nBit
    changed = false;
    for b = 1:nBit
        present = unique(bitTable(keep,b));
        if numel(present)~=1
            continue;
        end
        wanted = 1-present(1);
        addPos = find(bitTable(order,b)==wanted & ~ismember(order,keep),1);
        if isempty(addPos)
            continue;
        end
        addState = order(addPos);
        if score(order(1))-score(addState)>gapLimit
            continue;
        end
        counts = zeros(nBit,2);
        for q = 1:nBit
            counts(q,1) = sum(bitTable(keep,q)==0);
            counts(q,2) = sum(bitTable(keep,q)==1);
        end
        replacePos = 0;
        for pos = L:-1:1
            row = bitTable(keep(pos),:);
            removable = true;
            for q = 1:nBit
                if counts(q,row(q)+1)<=1
                    removable = false;
                    break;
                end
            end
            if removable
                replacePos = pos;
                break;
            end
        end
        if replacePos>0
            keep(replacePos) = addState;
            changed = true;
        end
    end
    if ~changed
        break;
    end
end
[~,rankOrder] = sort(score(keep),'descend');
keep = keep(rankOrder);
end

function value = mimo_candidate_frontend__mixture_log_likelihood_vector(residual,noiseVar,impulseVar,epsilon)
a = log(1-epsilon)-log(pi*noiseVar)-abs(residual).^2/noiseVar;
b = log(epsilon)-log(pi*impulseVar)-abs(residual).^2/impulseVar;
peak = max(a,b);
value = peak+log(exp(a-peak)+exp(b-peak));
end

function tf=tracing()
global MIMO_EXPERIMENT
tf=isstruct(MIMO_EXPERIMENT) && isfield(MIMO_EXPERIMENT,'trace') && isstruct(MIMO_EXPERIMENT.trace) && MIMO_EXPERIMENT.trace.enabled;
end
function trace_iter(roundIndex,pre,post,idxPre,idx,raw,betaBefore,betaAfter)
global MIMO_EXPERIMENT
rec.alphaPre=pre;rec.alphaPost=post;rec.idxPre=idxPre;rec.idx=idx;rec.raw=raw;
rec.betaBefore=betaBefore;rec.betaAfter=betaAfter;
rec.tiePre=adjacent_ties(pre,idxPre);rec.tiePost=adjacent_ties(post,idx);
rec.newEqualPairs=new_equal_pairs(pre,post);
if ~isfield(MIMO_EXPERIMENT.traceLog,'round') || isempty(MIMO_EXPERIMENT.traceLog.round)
 MIMO_EXPERIMENT.traceLog.round=repmat(rec,1,3);
end
MIMO_EXPERIMENT.traceLog.round(roundIndex)=rec;
end
function trace_readout(unclipped,llr,bits,max0,max1)
global MIMO_EXPERIMENT
MIMO_EXPERIMENT.traceLog.readout=struct('unclipped',unclipped,'llr',llr,'bits',bits,'max0',max0,'max1',max1);
end
function n=adjacent_ties(values,idx)
sorted=zeros(size(values));
for j=1:size(values,1),sorted(j,:)=values(j,idx(j,:));end
n=sum(sorted(:,1:end-1)==sorted(:,2:end),2);
end
function n=new_equal_pairs(pre,post)
n=zeros(size(pre,1),1);
for j=1:size(pre,1)
 count=0;
 for a=1:size(pre,2)-1
  for b=a+1:size(pre,2)
   if pre(j,a)~=pre(j,b) && post(j,a)==post(j,b),count=count+1;end
  end
 end
 n(j)=count;
end
end
