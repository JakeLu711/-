function K_SF = fun_flexibility(xL, cap_sop_nodes)
    % fun_flexibility - 计算中长期灵活性（2选1方案）
    % 输入：
    %   xL - 联络开关状态向量 (numBr×1)
    %   cap_sop_nodes - SOP容量向量 (numBr×1) MVA
    % 输出：
    %   K_SF - 中长期灵活性指标
    
    %% 全局变量
    global P_ESS_max P_CL_max P_SL_max
    global PNP PNP_FEX PNV PNV_FEX
    global tieBranches
    
    %% 1) 识别有效支路
   % 联络开关支路（排除已安装SOP的支路）
    switch_branches = find(xL == 1 & cap_sop_nodes == 0);
    % SOP支路
    sop_branches = find(cap_sop_nodes > 0);
    % 所有有效支路（联络开关或SOP）
    effective_branches = union(switch_branches, sop_branches);
    
    if isempty(effective_branches)
        K_SF = 0;
        return;
    end
    
    % 获取实际支路索引
    br_idx = tieBranches(effective_branches);
    
    %% 2) 计算调节能力（严格按照PDF公式）
    % ESS双向调节能力 (kW)
    deltaP_ESS = sum(P_ESS_max(br_idx));
    
    % CL单向削减能力 (kW)
    deltaP_CL = sum(P_CL_max(br_idx));
    
    % SL双向平移能力 (kW)
    deltaP_SL = sum(P_SL_max(br_idx));
    
    % SOP双向传输能力 (kW)
    S_SOP_total = sum(cap_sop_nodes) * 1000;  % MVA转kW
    
    % 联络开关转移能力（假设每个5MVA）
    S_switch_total = length(switch_branches) * 5000;  % kW
    
    %% 3) 功率调节灵活性 K_PR（按PDF公式14-16）
    % 正向调节能力（减负荷方向）
    A_positive = deltaP_ESS + deltaP_CL + deltaP_SL + S_SOP_total + S_switch_total;
    
    % 负向调节能力（增负荷方向，CL不参与）
    A_negative = deltaP_ESS + deltaP_SL + S_SOP_total + S_switch_total;
    
    % 分母计算（使用潮流极限差值）
    den_plus = max(max(PNP_FEX - PNP) * 1000, 1e-6);   % MW转kW
    den_minus = max(max(PNV - PNV_FEX) * 1000, 1e-6);  % MW转kW
    
    % 计算K_PR+和K_PR-
    K_PR_plus = A_positive / den_plus;
    K_PR_minus = A_negative / den_minus;
    
    % 综合功率调节灵活性
    K_PR = 0.5 * (K_PR_plus + K_PR_minus);
    K_PR = min(K_PR, 1);  % 限制在[0,1]
    
    %% 4) 网架调节灵活性 K_GR（按PDF公式17）
    % 可转移容量S_C包括：联络开关和SOP
    S_C_total = S_switch_total + S_SOP_total;
    
    % 用最大净负荷作为分母
    P_N_max = max(PNP) * 1000;  % MW转kW
    
    if P_N_max > 0
        K_GR = S_C_total / P_N_max;
    else
        K_GR = 0;
    end
    K_GR = min(K_GR, 1);  % 限制在[0,1]
    
    %% 5) 中长期灵活性（综合指标）
    K_SF = K_PR + K_GR;
    
    %% 6) 调试输出（可选）
    global VERBOSE_FLEXIBILITY
    if ~isempty(VERBOSE_FLEXIBILITY) && VERBOSE_FLEXIBILITY
        fprintf('\n=== 中长期灵活性计算 ===\n');
        fprintf('有效支路数: %d (开关:%d, SOP:%d)\n', ...
                length(effective_branches), length(switch_branches), length(sop_branches));
        fprintf('调节能力: ESS=%.0f kW, CL=%.0f kW, SL=%.0f kW\n', ...
                deltaP_ESS, deltaP_CL, deltaP_SL);
        fprintf('传输能力: 开关=%.0f kW, SOP=%.0f kW\n', ...
                S_switch_total, S_SOP_total);
        fprintf('灵活性指标: K_PR=%.3f (K_PR+=%.3f, K_PR-=%.3f)\n', ...
                K_PR, K_PR_plus, K_PR_minus);
       fprintf('           K_GR=%.3f, K_SF=%.3f\n', K_GR, K_SF);
    end
end
