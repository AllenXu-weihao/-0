function runs=exp_mvm_A2(edge,formats,cases)
% Controlled experiment: exactly one selected edge, no group-wide quantization.
allowed={'A2_x','A2_w','A2_out','A2_product','A2_acc'};
if nargin<1,edge=allowed{1};end
if nargin<2,formats=[24 12;22 12;20 12;20 10;18 10];end
if nargin<3,cases=make_cases();end
assert(any(strcmp(edge,allowed)),'Unsupported edge for this pathway');
runs=run_edge_experiment(edge,formats,cases);
end
