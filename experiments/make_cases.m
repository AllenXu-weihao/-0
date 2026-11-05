function cases=make_cases(nPerSNR,seed)
% Synthetic normalized Rayleigh + mixture noise, not a satellite channel claim.
if nargin<1,nPerSNR=20;end
if nargin<2,seed=1105;end
old=rng;c=onCleanup(@()rng(old));rng(seed,'twister'); %#ok<NASGU>
base=fileparts(fileparts(mfilename('fullpath')));s=load(fullfile(base,'deployment.mat'),'pack');ep=s.pack.config.channelImpulseEpsilon;
level=-7:2:7;gray=bitxor(0:7,floor((0:7)/2));const=zeros(64,1);bits=zeros(64,6);k=0;
for i=1:8,for j=1:8,k=k+1;const(k)=(level(i)+1i*level(j))/sqrt(42);bits(k,:)=[bitget(gray(i),3:-1:1),bitget(gray(j),3:-1:1)];end,end
cases=struct('input',{},'truth',{},'snrDB',{},'seed',{});k=0;
for snr=[0 10 20 30]
 for frame=1:nPerSNR
  H=(randn(8,4)+1i*randn(8,4))/sqrt(8);idx=randi(64,4,1);x=const(idx);
  % Ensemble receive power is 1; nv defines background SNR, not mixture SNR.
  nv=10^(-snr/10);iv=25*nv;v=nv*ones(8,1);v(rand(8,1)<ep)=iv;
  y=H*x+sqrt(v/2).*(randn(8,1)+1i*randn(8,1));k=k+1;
  cases(k)=struct('input',struct('y',y,'H',H,'noiseVar',nv,'impulseExtraVar',iv), ...
   'truth',reshape(bits(idx,:).',1,24),'snrDB',snr,'seed',seed);
 end
end
end
