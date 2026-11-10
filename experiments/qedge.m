function y=qedge(id,x)
% Quantize only the configured edge. Complex components are independent.
global MIMO_EXPERIMENT
assert(all(isfinite(x(:))),'Nonfinite input at %s',id);
y=x; st=MIMO_EXPERIMENT;
if isempty(st), return; end
sat=0;
if isfield(st.formats,id)
 f=st.formats.(id); assert(f.W>=2&&f.W<=48&&f.F>=0&&f.F<f.W);
 [yr,sr]=one(real(x),f);sat=sr;
 if ~isreal(x),[yi,si]=one(imag(x),f);y=complex(yr,yi);sat=sat+si;else,y=yr;end
end
v=[real(x(:));imag(x(:))]; if isreal(x),v=real(x(:));end
if ~isfield(st.stats,id),st.stats.(id)=struct('calls',0,'elements',0,'minimum',Inf,'maximum',-Inf,'saturations',0,'maxError',0);end
a=st.stats.(id);a.calls=a.calls+1;a.elements=a.elements+numel(v);a.minimum=min(a.minimum,min(v));a.maximum=max(a.maximum,max(v));a.saturations=a.saturations+sat;a.maxError=max(a.maxError,max(abs(y(:)-x(:))));
if isfield(st,'logEdges') && numel(st.logEdges)==2
 loB=st.logEdges(1);hiB=st.logEdges(2);nB=hiB-loB+1;
 if ~isfield(a,'logCount'),a.logCount=zeros(1,nB);a.logUnder=0;a.logOver=0;a.logZero=0;end
 mag=abs(v);a.logZero=a.logZero+nnz(mag==0);nz=mag>0;
 if any(nz)
  b=floor(log2(mag(nz)));a.logUnder=a.logUnder+nnz(b<loB);a.logOver=a.logOver+nnz(b>hiB);
  b=b(b>=loB & b<=hiB);
  if ~isempty(b),a.logCount=a.logCount+accumarray(b(:)-loB+1,1,[nB,1]).';end
 end
end
st.stats.(id)=a;
MIMO_EXPERIMENT=st;
end
function [y,s]=one(x,f)
lo=-2^(f.W-1);hi=2^(f.W-1)-1;
% Clamp before scaling: avoids loss of integer accuracy on extreme outliers.
z=x*2^f.F;assert(all(isfinite(z(:))),'Quantizer scaling overflow');
s=nnz(round(z)<lo|round(z)>hi);q=round(max(lo,min(hi,z)));y=q/2^f.F;
end
