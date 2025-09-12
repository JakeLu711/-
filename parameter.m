function parameter()
% 清理之前的全局变量，但保留算法参数
    clearvars -global -except HS_MAXITERS HS_HMS HS_HMCR HS_PAR_MIN HS_PAR_MAX GA_MAXGEN GA_POPSIZE VERBOSE_SEASON PARAMS_INITIALIZED

    % 参数验证标志␊
    global PARAMS_INITIALIZED
    if ~isempty(PARAMS_INITIALIZED) && PARAMS_INITIALIZED
        warning('参数已初始化，跳过重复初始化');
        return;
    end
% parameter  初始化全局参数（2025‑06 修正版）␊
% ␊
% 关键数据新增/调整：␊
%   • 固定分时电价：cbuy=0.60 ¥/kWh，csell=0.50 ¥/kWh␊
%   • 年负荷增长率 growth_load = 3 %␊
%   • 设备寿命统一 20 年：life_PV/WT/ESS/SOP␊
%   • DR 调节系数 ε_CL=1, ε_SL=0.25␊
%   • 单环网 N‑1 理论负载率 alpha_loadrate = 0.5␊
%   • 潮流备用倍率参数化：FEX_factor_up=1.1, FEX_factor_down=0.9␊
%%====================  全局声明  ====================␊
% --- 资源候选集 & 数量␊
global st_pvc st_windc st_essc st_CLc st_SLc 
global sz_pv sz_wind sz_ess sz_CL sz_SL 
% --- 安装台数上下限% --- 决策变量边界（添加这行）␊
global VarMin VarMax
global max_pv min_pv max_wind min_wind max_ess min_ess
global max_CL min_CL max_SL min_SL
% --- 单台容量 / SOP 模块␊
global s_pv s_wind s_cn  S_SOP_max S_SOP_ub baseLoad s_sop_min
% --- 功率因数 & DR 调节比例␊
global pf_pv pf_wind pf_ess ratio_CL ratio_SL epsilon_CL epsilon_SL
% --- 成本参数（CAPEX & OPEX + 交易/惩罚）␊
global cpv cwind cE_ess cP_ess csop  sc            % CAPEX␊
global cpvy cwindy cE_essy cP_essy csopy         % OPEX 比率␊
global cbuy csell  cdre  cqpv cqw                           % 电价与罚款␊
% --- 碳排放参数与目标权重␊
global xi_co2 xi_nox xi_so2 CF_base alpha_CF_min alpha_CF_max
global w_cost_base w_flex_base w_carbon_base kGR_min kGR_max
global Ce_min Ce_max CF_min CF_max kPR_min kPR_max xi_sum
% --- 财务 & 技术␊
global r year2 eta socmin socmax pl growth_load
% --- 设备寿命␊
global life_PV life_WT life_ESS life_SOPt

% --- 场景 / 聚类␊
global K T seasonCenters seasonProb center_wind 
global seasonWindProb loadCent

% --- 潮流 & 灵活性␊
global branch2nodes PNP PNP_FEX PNV PNP_FEX
global FEX_factor_up FEX_factor_down alpha_loadrate
global min_flow tieBranches numBr
global P_ESS_max max_sw_act deltaP_DR_max
global P_CL_max P_SL_max S_SOP_max

%%==================== 1. 网络拓扑 ====================␊
mpc         = case33bw();
n_total_branches = size(mpc.branch, 1);  % 应该是37␊
% 初始化时使用正确的维度␊
P_ESS_max = zeros(n_total_branches, 1);   % 37×1␊
P_CL_max = zeros(n_total_branches, 1);    % 37×1␊
P_SL_max = zeros(n_total_branches, 1);    % 37×1␊
S_SOP_max = zeros(n_total_branches, 1);   % 37×1␊
s_sop_min = 100;  % SOP模块容量 kVA␊
tieBranches = [33 34 35 36 37];   % 仅这 5 条␊
numBr       = numel(tieBranches); % = 5␊
%%==================== 2. 候选节点 ====================␊
tie_endpoints = mpc.branch(tieBranches, 1:2);  % 5×2矩阵␊
% tie_endpoints = [21 8; 9 15; 12 22; 18 33; 25 29]␊

%% SOP相关参数␊
S_SOP_ub = 3000;      % 单个SOP最大容量 kVA␊
s_sop_min = 100;      % SOP模块容量 kVA␊
S_SOP_max = zeros(length(tieBranches), 1);  % 改为使用tieBranches长度␊
st_pvc   = [6 21 31];   % PV (3)␊
st_windc = [15 23 29];  % WT (3)␊
st_essc  = [6 15 23];   % ESS (3)␊

st_CLc  = [18 30];      % CL (2)␊
st_SLc  = [18 30];      % SL (2)␊
sz_CL  = numel(st_CLc);
sz_SL  = numel(st_SLc);

% 数量␊
sz_pv  = numel(st_pvc);
sz_wind= numel(st_windc);
sz_ess = numel(st_essc);
sz_CL  = numel(st_CLc);
sz_SL  = numel(st_SLc);

%%==================== 3. 安装台数上下限 ====================␊
min_pv   = 1;  max_pv   = 3;
min_wind = 1;  max_wind = 3;
min_ess  = 1;  max_ess  = 3;
min_CL = sz_CL;              % = 2␊
max_CL = sz_CL;              % = 2␊
min_SL = sz_SL;              % = 2␊
max_SL = sz_SL;              % = 2␊
%%==================== 4. 单台容量 & SOP 模块 ====================␊
s_pv   = 140;   % kW / 台␊
s_wind = 180;   % kW / 台␊
s_cn   = 100;   % kW / 台 (ESS 功率)␊
%%==================== 5. 功率因数 & DR 比例 ====================␊
pf_pv   = 0.98;
pf_wind = 0.95;
pf_ess  = 1.00;
ratio_CL = 0.15;           % 可削减比例␊
ratio_SL = 0.15;            % 可平移比例␊
epsilon_CL = 1;             % 论文 ε_CL␊
epsilon_SL = 1/4;           % ε_SL␊

%%==================== 6. 成本参数 ====================␊
% ---- CAPEX (¥/容量)␊
cpv    = 7140;   cwind  = 3500;
cE_ess = 1500;   cP_ess = 400;
cqpv = 0.5;   % 弃光惩罚成本 (元/kWh)␊
cqw = 0.5;    % 弃风惩罚成本 (元/kWh)␊
csop   = 2000;   sc     = 60000;
% ---- OPEX 比率 γ␊
cpvy=0.01; cwindy=0.01; cE_essy=0.04; cP_essy=0.04; csopy=0.01; 

% ---- 电价 / 罚款 (¥/kWh)␊
cbuy  = 0.60;   csell = 0.50;  cploss = 0.40;  cdre = 0.60;

%%=================== 7. 碳排放静态参数 ====================␊
xi_co2 = 0.886;  xi_nox = 0.0015;  xi_so2 = 0.0018;
CF_base=1.0;  alpha_CF_min=0.80;  alpha_CF_max=1.10;
w_cost_base=0.5;  w_flex_base=0.25;  w_carbon_base=0.25;
xi_sum =0.8893; 
%%==================== 7-A. 隶属度阈值 (Fuzzy Limits) ========␊
% —— 经济成本 (万元 / d) ——␊
Ce_min = 10;      % 完全满意：≤ 10 万␊
Ce_max = 40;      % 完全不满：≥ 30 万␊

% —— 综合排放 (t-CO2-eq / d) ——␊
CF_min =  15;        % 理想排放␊
CF_max = 35;        % 不可接受排放␊

% —— 日功率调节灵活性 (0–1) ——␊
kPR_min = 0.00;      % ≥ 0.05 才算有调节意义␊
kPR_max = 1.00;      % ≥ 0.60 即视为充分灵活␊
kGR_min = 0.00;   kGR_max = 0.50;
%%==================== 8. 财务 & 储能 ====================␊
r = 0.08;  year2 = 10;   % 折现率及经济寿命␊
eta = 0.90;  socmin = 0.10;  socmax = 0.90;
% 设备寿命 (年)␊
life_PV = 20;  life_WT = 20;  life_ESS = 20;  life_SOP = 20;

% 年负荷增长率 (fraction)␊
growth_load = 0.03;

%%==================== 9. 24 h 负荷曲线 (标幺)␊
pl = [ ...␊
    0.7293 0.6764 0.6236 0.5798 0.5473 0.5641 0.6936 0.7660 ...␊
    0.8440 0.9550 1.0166 1.0834 1.1159 1.0753 1.0498 1.0208 ...␊
    1.1019 1.1740 1.2339 1.2668 1.3000 1.1464 1.0187 0.8080 ];
pl = pl(:);   % 转为 24×1 列向量␊

%%==================== 10. 场景占位 ====================␊
K = 1;    T = 24;          % ← 典型日条数 & 每日时段␊

% 只占位，真正的内容由 loadTypicalData.m 再写入␊
seasonCenters  = {};
center_wind    = {};
loadCent       = {};

%%==================== 11. 支路映射 ====================␊
branch2nodes = num2cell(mpc.branch(:,1:2),2); 
%%==================== 12. 潮流基准 & 备用倍率 ====================␊
FEX_factor_up   = 1.1;   % 可调上限倍率␊
FEX_factor_down = 0.9;   % 可调下限倍率␊
alpha_loadrate  = 0.5;   % 单环网 N‑1 理论负载率␊
opt  = mpoption('verbose',0,'out.all',0);
res0 = runpf(mpc, opt);
PNP  = abs(res0.branch(:,14));
PNV  = abs(res0.branch(:,16));
PNP_FEX = FEX_factor_up   * PNP;
PNV_FEX = FEX_factor_down * PNV;
fprintf('\n基准潮流信息:\n');
fprintf('PNP范围: [%.4f, %.4f] MW\n', min(PNP), max(PNP));
fprintf('PNV范围: [%.4f, %.4f] MW\n', min(PNV), max(PNV));
fprintf('PNP_FEX范围: [%.4f, %.4f] MW\n', min(PNP_FEX), max(PNP_FEX));
fprintf('PNV_FEX范围: [%.4f, %.4f] MW\n', min(PNV_FEX), max(PNV_FEX));
%%==================== 13. 灵活性占位 ====================␊

% -------- ① ESS 调节上限 (与之前一致) --------␊
toBusVec   = cellfun(@(x) x(2), branch2nodes);
isESSline  = ismember(toBusVec, st_essc);
P_ESS_max(isESSline) = 3 * 100;            % 300 kW (=3×100)␊
% -------- ② 各母线峰荷 (kW) --------␊
Pd_peak = mpc.bus(:,3) * 1e3;              % case33bw 已是 MW → ×1e3␊
% -------- ③ 可削减负荷上限 ΔP_CL_max (仅正向用) --------␊
P_CL_max  = ratio_CL * Pd_peak(toBusVec);  % 15% 削减 → kW␊
% -------- ④ 可平移负荷上限 ΔP_SL_max (正/负均用) --------␊
P_SL_max  = ratio_SL * Pd_peak(toBusVec);  % 同 15%␊
% -------- ⑤ SOP / 联络容量向量 --------␊
% -------- ⑤ 生成 SOP 容量上限向量 --------␊
S_SOP_ub = 3000;                     % kVA 上限 = 3 MVA␊
S_SOP_max = zeros(numBr,1);          % 初始化为0，实际容量由决策变量决定␊
% 注意：在2选1方案中，SOP安装在联络支路上␊
% 不需要预设容量，将在运行时根据决策变量动态设置␊
min_flow  = -Inf * ones(numBr,1);
max_sw_act = 4;    % 联络/分段开关日动作次数上限␊
% -------- ⑥ 计算DR最大调节能力 -------- ␊
global deltaP_DR_max
% 获取节点18和30的负荷␊
Pd_18 = mpc.bus(18, 3) * 1e3;  % kW␊
Pd_30 = mpc.bus(30, 3) * 1e3;  % kW␊

% DR最大调节能力 = CL + SL的最大调节量␊
deltaP_CL_max = ratio_CL * (Pd_18 + Pd_30);  % 可削减␊
deltaP_SL_max = ratio_SL * (Pd_18 + Pd_30);  % 可平移␊
deltaP_DR_max = deltaP_CL_max + deltaP_SL_max;  % 总DR能力␊

fprintf('DR节点负荷: 节点18=%.2f kW, 节点30=%.2f kW\n', Pd_18, Pd_30);
fprintf('DR最大调节能力: %.2f kW\n', deltaP_DR_max);

% 初始化上层边界（修正调用）␊
try
    [VarMin, VarMax] = init_upper_bounds(numBr);
    fprintf('上层决策变量边界初始化成功\n');
    fprintf('决策变量维度: %d\n', length(VarMin));
catch ME
    error('初始化上层边界失败: %s', ME.message);
end

end  % function parameter 结束
