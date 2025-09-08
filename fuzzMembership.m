function [phi_cost, phi_carbon, phi_flex] = fuzzMembership( ...
                                   C_cost , C_carbon , kPR_d , kGR_d )
%======================================================================
%  fuzzMembership.m
%     将 经济成本 / 综合排放 / 功率调节灵活性 / 网架灵活性
%     映射到 [0,1] 隶属度
%
%   输入:
%     C_cost   —— 日运行经济成本  (万元)
%     C_carbon —— 日综合排放量   (t-CO2-eq)
%     kPR_d    —— 功率调节灵活性 (0–1)
%     kGR_d    —— 网架调节灵活性 (0–1)
%
%   输出:
%     phi_cost   —— 经济满意度   (越低成本越接近 1)
%     phi_carbon —— 排放满意度   (越低排放越接近 1)
%     phi_flex   —— 综合灵活性满意度 = 0.5·φ_PR + 0.5·φ_GR
%======================================================================

%% 阈值（由 parameter.m 统一给出）
global Ce_min Ce_max CF_min CF_max ...
       kPR_min kPR_max kGR_min kGR_max
assert(C_cost  > 0 && C_cost  < 1e4, 'C_cost 单位错误？期望 < 1e4 万元');
assert(C_carbon> 0 && C_carbon< 1e3, 'C_carbon 单位错误？期望 < 1000 t');
%% 1) 经济性隶属度  φ_cost   (线性递减)
phi_cost = max( 0 , min( 1 , (Ce_max - C_cost) / max(eps , Ce_max - Ce_min) ) );

%% 2) 综合排放隶属度  φ_carbon (线性递减)
phi_carbon = max( 0 , min( 1 , (CF_max - C_carbon) / max(eps , CF_max - CF_min) ) );

%% 3-A) 功率灵活性隶属度  φ_PR   (线性递增)
phi_pr = max( 0 , min( 1 , (kPR_d - kPR_min) / max(eps , kPR_max - kPR_min) ) );

%% 3-B) 网架灵活性隶属度  φ_GR   (线性递增)
phi_gr = max( 0 , min( 1 , (kGR_d - kGR_min) / max(eps , kGR_max - kGR_min) ) );

%% 3-C) 综合灵活性满意度
phi_flex = 0.5 * ( phi_pr + phi_gr );   % 0.5 / 0.5 等权平均
% 若需偏重某一侧，可改为  w1*phi_pr + w2*phi_gr ,  且 w1+w2=1

end