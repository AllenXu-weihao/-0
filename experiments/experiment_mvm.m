function y=experiment_mvm(stage,x,A)
% Float matrix boundary experiments; product/acc tests use ordered MAC.
global MIMO_EXPERIMENT
x=qedge([stage '_x'],x);A=qedge([stage '_w'],A);
f=MIMO_EXPERIMENT.formats;
ordered=isfield(f,[stage '_product'])||isfield(f,[stage '_acc']);
if ~ordered,y=x*A;else
 y=zeros(size(x,1),size(A,2));
 for j=1:size(A,2)
  ids=find(A(:,j)~=0);a=zeros(size(x,1),1);
  for k=1:numel(ids)
   i=ids(k);v=qedge([stage '_product'],x(:,i)*A(i,j));a=qedge([stage '_acc'],a+v);
  end
  y(:,j)=a;
 end
end
y=qedge([stage '_out'],y);
end
