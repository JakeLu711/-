function f = lower_obj(xSched, upx)
%==============================================================
% lower_obj  —— 运行层(典型日) 经济-排放-灵活性评估
%   f = [ C_cost , C_carbon , -kPR_d , -kGR_d ]
%   适配多点安装 + 联络开关/SOP 2选1方案
%==============================================================

%% ---------- 全局 ----------
global K T gailv baseLoad                       % 典型日概率 & 负荷
global seasonCenters center_wind 
global cbuy cqpv cqw epsilon_CL epsilon_SL      % 成本参数
global ratio_CL ratio_SL xi_sum                 % DR 比例 & 排放系数
global branch2nodes PNP PNP_FEX PNV PNV_FEX     % 潮流基准
global deltaP_DR_max                            % DR 上限
global st_pvc st_windc st_essc st_CLc st_SLc   % 候选节点集
global tieBranches numBr                        % 联络支路
[~,~,~,~,~,~,PD] = idx_bus;                     % MATPOWER bus 索引

%% ---------- 1) 解析上层规划（新结构） ----------
p = 1;

% PV各节点容量 (MW)
cap_pv_nodes = upx(p:p+length(st_pvc)-1);
p = p + length(st_pvc);

% Wind各节点容量 (MW)
cap_wind_nodes = upx(p:p+length(st_windc)-1);
p = p + length(st_windc);

% ESS各节点容量 (MW)
cap_ess_nodes = upx(p:p+length(st_essc)-1);
p = p + length(st_essc);

% 联络开关状态 (0/1)
xL = upx(p:p+numBr-1);
p = p + numBr;

% SOP容量 (MVA)
cap_sop_nodes = upx(p:p+numBr-1);

% 防护：确保xL为0/1离散值
xL = xL >= 0.5;

% CL和SL保持原设计（固定位置和容量）
loc_CL_idx = 1;  % 使用第一个CL候选位置
cap_CL = 1;      % 启用CL
loc_SL_idx = 1;  % 使用第一个SL候选位置
cap_SL = 1;      % 启用SL
loc_CL = st_CLc(min(loc_CL_idx, length(st_CLc)));
loc_SL = st_SLc(min(loc_SL_idx, length(st_SLc)));

% 汇总各类DG总容量 (MW)
total_pv_cap   = sum(cap_pv_nodes);
total_wind_cap = sum(cap_wind_nodes);
total_ess_cap  = sum(cap_ess_nodes);

%% ---------- 2) 解码调度向量 ----------
q = 1;
% 注意：为简化，仍使用总量调度，在潮流计算时按容量比例分配
% 调度变量：出力比例 (0-1)
pv_s   = reshape(xSched(q:q+K*T-1), K, T); q = q + K*T;  % PV出力比例
wind_s = reshape(xSched(q:q+K*T-1), K, T); q = q + K*T;  % Wind出力比例
ess_s  = reshape(xSched(q:q+K*T-1), K, T); q = q + K*T;  % ESS出力比例
mu_CL  = reshape(xSched(q:q+K*T-1), K, T); q = q + K*T;
mu_SL  = reshape(xSched(q:end), K, T);

%% ---------- 3) 基准潮流 case ----------
persistent mpc0;
if isempty(mpc0), mpc0 = case33bw; end

%% ---------- 4) 成本/排放累加 ----------
C_q = 0;          % 弃电罚款
C_g = 0;          % 购电成本
C_DSM = 0;        % 削减/平移负荷补偿
E_grid = 0;       % 购电量 (kWh)

% 检查并规范化 gailv
if isempty(gailv) || any(isnan(gailv))
    error('gailv 未初始化或包含 NaN！');
end

if sum(gailv) ~= 1 && sum(gailv) > 0
    fprintf('Warning: gailv sum = %.4f, normalizing to probability distribution\n', sum(gailv));
    gailv = gailv / sum(gailv);
end

for k = 1:K
    gk = gailv(k);
    for t = 1:T
        mpc = mpc0;                    % 深拷贝

        %% === 处理支路状态（2选1） ===
         for i = 1:numBr
            br_idx = tieBranches(i);

            if cap_sop_nodes(i) > 0
                % 安装了SOP，支路闭合且有容量限制
                mpc.branch(br_idx, 11) = 1;  % BR_STATUS = 1
                mpc.branch(br_idx, 6) = cap_sop_nodes(i);  % RATE_A (MVA)
                % 降低支路阻抗以模拟SOP的低损耗特性
                mpc.branch(br_idx, 3) = mpc.branch(br_idx, 3) * 0.1;  % 降低电阻
                mpc.branch(br_idx, 4) = mpc.branch(br_idx, 4) * 0.1;  % 降低电抗

            elseif xL(i) == 1
                % 安装了联络开关，支路闭合
                mpc.branch(br_idx, 11) = 1;  % BR_STATUS = 1

            else
                % 常开状态␊
                mpc.branch(br_idx, 11) = 0;  % BR_STATUS = 0␊
            end
         end

        %% === (a) 负荷 (kW→MW) ===
        mpc.bus(:,PD) = baseLoad(t,:)'/1e3;

      %% === (b) 分布式电源注入（多点） ===
        % PV：出力比例×节点容量×资源曲线 (MW)
        for i = 1:length(st_pvc)
            if cap_pv_nodes(i) > 0
                pv_inject = pv_s(k,t) * cap_pv_nodes(i) * seasonCenters{k}(t);   % MW
                mpc.bus(st_pvc(i), PD) = mpc.bus(st_pvc(i), PD) - pv_inject;
            end
        end

        % Wind：出力比例×节点容量×资源曲线 (MW)
        for i = 1:length(st_windc)
            if cap_wind_nodes(i) > 0
                wind_inject = wind_s(k,t) * cap_wind_nodes(i) * center_wind{k}(t);  % MW
                mpc.bus(st_windc(i), PD) = mpc.bus(st_windc(i), PD) - wind_inject;
            end
        end

        % ESS：出力比例×节点容量 (MW)
        for i = 1:length(st_essc)
            if cap_ess_nodes(i) > 0
                ess_inject = ess_s(k,t) * cap_ess_nodes(i);  % MW
                mpc.bus(st_essc(i), PD) = mpc.bus(st_essc(i), PD) - ess_inject;
            end
        end

        %% === (c) DR 执行量 ===
        if cap_CL > 0
            Pd_CL = baseLoad(t,loc_CL);    % kW, 原始负荷
            P_shed = ratio_CL * mu_CL(k,t) * Pd_CL;   % kW
            mpc.bus(loc_CL,PD) = mpc.bus(loc_CL,PD) - P_shed /1e3;
        else
            P_shed = 0;
        end
        
        if cap_SL > 0
            Pd_SL = baseLoad(t,loc_SL);    % kW
            P_shift = ratio_SL * mu_SL(k,t) * Pd_SL;   % kW
            mpc.bus(loc_SL,PD) = mpc.bus(loc_SL,PD) - P_shift/1e3;
        else
            P_shift = 0;
        end

        %% === (d) 潮流计算 ===
        res = runpf(mpc, mpoption('out.all',0,'verbose',0));

        % ---------- 失败 / NaN 防护 ----------
        if ~res.success || isnan(res.gen(1,2))
           fprintf('✗ PF fail  k=%d  t=%02d\n', k, t);
           f = [1e9 1e9 0 0];
           return
        end
        
        Pg = res.gen(1,2) * 1e3;    % kW
        
         % 调试信息（只在第一个时段打印）
        if t == 1 && k == 1
            DG_total = pv_s(k,t) * total_pv_cap * seasonCenters{k}(t) + ...
                       wind_s(k,t) * total_wind_cap * center_wind{k}(t) + ...
                       ess_s(k,t) * total_ess_cap;
            fprintf('Debug t=%d: 负荷总和=%.2f MW, DG总和=%.2f MW, Pg=%.2f kW\n', ...
                    t, sum(mpc.bus(:,PD)), DG_total, Pg);
        end
        
        % 只累积购电量（Pg > 0），售电不计入碳排放
        if Pg > 0
            E_grid = E_grid + gk * Pg;     % kWh
            C_g    = C_g    + gk * cbuy * Pg /1e3; % → 万元
        else
            % 售电情况
            if t == 1 && k == 1
                fprintf('Warning: 向电网售电 Pg=%.2f kW at t=%d\n', Pg, t);
            end
        end
        
        %% === (e) 弃电罚款（考虑多点） ===
         % PV弃电␊
        for i = 1:length(st_pvc)
            if cap_pv_nodes(i) > 0
                pv_available = cap_pv_nodes(i) * 1000 * seasonCenters{k}(t);  % kW␊
                pv_actual    = pv_s(k,t) * cap_pv_nodes(i) * seasonCenters{k}(t) * 1000;  % kW
                C_q = C_q + gk * cqpv * max(0, pv_available - pv_actual) / 1e4;
            end
        end

        % Wind弃电␊
        for i = 1:length(st_windc)
            if cap_wind_nodes(i) > 0
                wind_available = cap_wind_nodes(i) * 1000 * center_wind{k}(t);  % kW␊
                wind_actual    = wind_s(k,t) * cap_wind_nodes(i) * center_wind{k}(t) * 1000;  % kW
                C_q = C_q + gk * cqw * max(0, wind_available - wind_actual) / 1e4;
            end
        end

        %% === (f) DSM 补偿 ===
        C_DSM = C_DSM + gk * ( ...
                 epsilon_CL * P_shed  + ...
                 epsilon_SL * P_shift ) /1e4;      % 元→万元
    end
end

C_cost   = (C_q + C_g + C_DSM);              % 万元
C_carbon = E_grid * xi_sum / 1e6;            % g→t CO₂-eq

% 调试信息
fprintf('Debug: E_grid=%.2f kWh, xi_sum=%.4f, C_carbon=%.4f t\n', ...
        E_grid, xi_sum, C_carbon);

%% ---------- 5) 短期灵活性（考虑多点安装和SOP） ----------
% 参数设置
global alpha_loadrate  % 理论负载率 (0.5)
S_max = max(abs([PNP; PNV])) * 1.2;  % 馈线最大载荷估算 (MW)

% 计算净负荷（简化：用首个时段代表）
total_load = sum(baseLoad(1,:)) / 1000;  % MW
% 考虑各DG的平均出力（假设容量因子）
total_DG = sum(cap_pv_nodes) * 0.3 + ...     % PV平均容量因子30%
           sum(cap_wind_nodes) * 0.35;       % Wind平均容量因子35%
P_N = total_load - total_DG;  % 净负荷 MW

% 计算调节能力总和 (kW)
% ESS：所有安装点的总容量
A_ESS = sum(cap_ess_nodes) * 1000;  % MW转kW，双向调节

% CL和SL
A_CL = 0;
A_SL = 0;
if cap_CL > 0
    A_CL = ratio_CL * sum(baseLoad(1, loc_CL));  % CL只能削减
end
if cap_SL > 0
    A_SL = ratio_SL * sum(baseLoad(1, loc_SL));  % SL可双向
end
% 联络开关和SOP的转移能力
A_switch = sum(xL==1 & cap_sop_nodes==0) * 5000;           % 每个联络开关5MVA
A_SOP = sum(cap_sop_nodes) * 1000;      % MVA转kVA␊

% 总调节能力
A_sum_positive = A_ESS + A_CL + A_SL + A_switch + A_SOP;  % 正向调节（减负荷）
A_sum_negative = A_ESS + A_SL + A_switch + A_SOP;        % 负向调节（增负荷）
% 根据净负荷情况计算功率灵活性
fprintf('\n=== 短期功率灵活性计算 ===\n');
fprintf('净负荷 P_N = %.2f MW\n', P_N);
fprintf('α*S_max = %.2f MW (α=%.2f)\n', alpha_loadrate * S_max, alpha_loadrate);
fprintf('正向调节能力: %.2f kW (ESS:%.0f, CL:%.0f, SL:%.0f, Switch:%.0f, SOP:%.0f)\n', ...
        A_sum_positive, A_ESS, A_CL, A_SL, A_switch, A_SOP);
fprintf('负向调节能力: %.2f kW\n', A_sum_negative);

if P_N > alpha_loadrate * S_max
    % 情况1：净负荷超过安全阈值
    kPR_d = A_sum_positive / ((P_N - alpha_loadrate * S_max) * 1000);
    fprintf('情况1: 净负荷过高，需要削减\n');
elseif P_N >= 0 && P_N <= alpha_loadrate * S_max
    % 情况2：净负荷在安全范围内
    kPR_d = 1;
    fprintf('情况2: 净负荷在安全范围内\n');
else
    % 情况3：净负荷为负（逆向潮流）
    kPR_d = A_sum_negative / ((-P_N) * 1000);
    fprintf('情况3: 出现逆向潮流\n');
end

% 限制在合理范围
kPR_d = max(0, min(kPR_d, 1));
fprintf('功率调节灵活性 kPR = %.4f\n', kPR_d);

%% 网架调节灵活性
% 有效支路数（联络开关或SOP）␊␊
effective_branches = sum(xL==1 & cap_sop_nodes==0) + sum(cap_sop_nodes > 0);
% 总转移容量
S_C_total = A_switch + A_SOP;

% 计算网架灵活性
if abs(P_N) > 0 && effective_branches > 0
    kGR_d = min(S_C_total / (abs(P_N) * 1000), 1);  % P_N从MW转kW
    fprintf('\n网架灵活性: 有效支路=%d, 总容量=%.0f kVA, kGR=%.4f\n', ...
            effective_branches, S_C_total, kGR_d);
else
    kGR_d = 0;
end

%% ---------- 6) 返回 ----------
% 最终调试输出
fprintf('\n=== lower_obj 结果汇总 ===\n');
fprintf('E_grid = %.2f kWh\n', E_grid);
fprintf('C_q = %.4f 万元 (弃电罚款)\n', C_q);
fprintf('C_g = %.4f 万元 (购电成本)\n', C_g);
fprintf('C_DSM = %.4f 万元 (需求响应补偿)\n', C_DSM);
fprintf('C_cost = %.4f 万元 (总成本)\n', C_cost);
fprintf('C_carbon = %.4f t CO2 (xi_sum=%.4f)\n', C_carbon, xi_sum);
fprintf('kPR_d = %.4f, kGR_d = %.4f\n', kPR_d, kGR_d);

% 多点安装信息
fprintf('\n多点安装配置:\n');
fprintf('  PV: %s MW at nodes %s\n', mat2str(cap_pv_nodes, 2), mat2str(st_pvc));
fprintf('  Wind: %s MW at nodes %s\n', mat2str(cap_wind_nodes, 2), mat2str(st_windc));
fprintf('  ESS: %s MW at nodes %s\n', mat2str(cap_ess_nodes, 2), mat2str(st_essc));
fprintf('  Switches: %d个, SOP: %d个 (总%.1f MVA)\n', ...
    sum(xL==1 & cap_sop_nodes==0), sum(cap_sop_nodes > 0), sum(cap_sop_nodes));

% 构建返回值
f = zeros(1, 4);  % 预分配
f(1) = C_cost;
f(2) = C_carbon;
f(3) = -kPR_d;
f(4) = -kGR_d;

% 最终确认
fprintf('最终返回值: f = [%.4e, %.4e, %.4e, %.4e]\n', f(1), f(2), f(3), f(4));

end  % function lower_obj 结束
