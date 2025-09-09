function f = fun_objective(x)
%% ---------- 全局量 ----------
global numBr tieBranches ...
       w_cost_base w_flex_base w_carbon_base
global s_pv s_wind s_cn s_sop_min       % 单台容量 (kW)
global st_pvc st_windc st_essc          % 候选节点集

% 监控输入
persistent call_count input_history;
if isempty(call_count), call_count = 0; input_history = []; end
call_count = call_count + 1;

% 监控代码（保持原有）
if call_count <= 5
    input_history = [input_history; x];
elseif call_count == 6
    input_diff = max(input_history) - min(input_history);
    fprintf('输入变量差异范围: [%.6f, %.6f]\n', min(input_diff), max(input_diff));
    if max(input_diff) < 1e-6
        fprintf('⚠️ 警告：输入变量几乎相同！搜索算法可能有问题\n');
    end
end

try
    %% ---------- 2) 解码连续 / 离散变量 ----------
    idx = 1;
    
    % 解码PV（每个候选点的容量）
    cap_pv_nodes = x(idx:idx+length(st_pvc)-1);
    idx = idx + length(st_pvc);
    
    % 解码Wind（每个候选点的容量）
    cap_wind_nodes = x(idx:idx+length(st_windc)-1);
    idx = idx + length(st_windc);
    
    % 解码ESS（每个候选点的容量）
    cap_ess_nodes = x(idx:idx+length(st_essc)-1);
    idx = idx + length(st_essc);
    
    % 解码支路类型（2选1）
    branch_types = x(idx:idx+numBr-1);
    idx = idx + numBr;
    
    % 解码SOP容量
    sop_cap_raw = x(idx:idx+numBr-1);
    
    %% ---------- 3) 处理2选1逻辑 ----------
    xL = zeros(numBr, 1);           % 联络开关状态
    cap_sop_nodes = zeros(numBr, 1); % SOP容量
    
    for i = 1:numBr
        if branch_types(i) < 0.5
            % 常开，不安装任何设备
            xL(i) = 0;
            cap_sop_nodes(i) = 0;
        elseif branch_types(i) < 1.5
            % 安装联络开关
            xL(i) = 1;
            cap_sop_nodes(i) = 0;
        else
            % 安装SOP
            xL(i) = 0;  % 注意：安装SOP时，联络开关状态为0
            % SOP容量取整到模块数
            num_sop = round(sop_cap_raw(i) * 1e3 / s_sop_min);
            cap_sop_nodes(i) = num_sop * s_sop_min / 1e3;  % MVA
        end
    end
    
    %% ---------- 4) 容量标准化 ----------
    % PV：每个节点的台数
    num_pv_nodes = round(cap_pv_nodes * 1e3 / s_pv);
    cap_pv_nodes = num_pv_nodes * s_pv / 1e3;  % MW
    
    % Wind：每个节点的台数
    num_wind_nodes = round(cap_wind_nodes * 1e3 / s_wind);
    cap_wind_nodes = num_wind_nodes * s_wind / 1e3;  % MW
    
    % ESS：每个节点的台数
    num_ess_nodes = round(cap_ess_nodes * 1e3 / s_cn);
    cap_ess_nodes = num_ess_nodes * s_cn / 1e3;  % MW
    
    %% ---------- 5) 组装传给下层的决策向量 ----------
    upx = [cap_pv_nodes, cap_wind_nodes, cap_ess_nodes, ...
           xL(:)', cap_sop_nodes(:)'];
           
    %% ---------- 6) 四季循环计算 ----------
    % 初始化年度指标
    C_cost_year = 0;      % 年度运行成本
    C_carbon_year = 0;    % 年度碳排放
    kPR_year = 0;         % 年度功率调节灵活性
    kGR_year = 0;         % 年度网架调节灵活性
    
    % 季节权重（基于天数）
    season_days = [92, 92, 91, 90];  % 春夏秋冬天数（非闰年）
    season_weights = season_days / 365;
    
    % 季节名称（用于调试输出）
    season_names = {'春季', '夏季', '秋季', '冬季'};
    
    % 检查是否需要详细输出
    global VERBOSE_SEASON
    if isempty(VERBOSE_SEASON)
        VERBOSE_SEASON = false;  % 默认不输出详细信息
    end
    
    % 循环计算四季
    for s = 1:4
        % 切换到第s季
        updateSeason(s);
        
        % 运行该季的下层优化
        [~, C_cost_s, C_carbon_s, kPR_s, kGR_s] = runLowerLayer(upx, 'GA');
        
        % 累加年度指标（加权平均）
        C_cost_year = C_cost_year + season_weights(s) * C_cost_s;
        C_carbon_year = C_carbon_year + season_weights(s) * C_carbon_s;
        kPR_year = kPR_year + season_weights(s) * kPR_s;
        kGR_year = kGR_year + season_weights(s) * kGR_s;
        
        % 详细输出（可选）
        if VERBOSE_SEASON
            fprintf('  %s: 成本=%.2f万元, 碳排=%.2ft, kPR=%.3f, kGR=%.3f\n', ...
                    season_names{s}, C_cost_s, C_carbon_s, kPR_s, kGR_s);
        end
    end
    
    %% ---------- 7) 计算中长期灵活性 ----------
    % 中长期灵活性考虑系统配置的长期适应能力
    try
        K_flex_long = fun_flexibility(xL, cap_sop_nodes);   % 越大越好
    catch ME
        warning('fun_objective:flex_eval', ...
                'fun_flexibility failed: %s', ME.message);
        K_flex_long = kPR_year + kGR_year + sum(xL) * 10;
    end
    
    % 综合灵活性：结合中长期和短期
    % 可以调整权重：0.7为中长期权重，0.3为短期权重
    K_flex_total = 0.7 * K_flex_long + 0.3 * (kPR_year + kGR_year) / 2;
    
    %% ---------- 8) 计算总成本（包含投资成本） ----------
    % 添加年化投资成本
    C_invest = calculate_investment_cost_2in1(num_pv_nodes, num_wind_nodes, ...
                                             num_ess_nodes, xL, cap_sop_nodes);
    C_cost_total = C_cost_year + C_invest;

    %% ---------- 9) 权重正规化 & 综合目标 ----------
    w_sum = w_cost_base + w_flex_base + w_carbon_base;
    if w_sum == 0
        warning('fun_objective:weights', '权重和为0，使用默认权重');
        w_cost = 0.5;
        w_flex = 0.25;
        w_carbon = 0.25;
    else
        w_cost   = w_cost_base   / w_sum;
        w_flex   = w_flex_base   / w_sum;
        w_carbon = w_carbon_base / w_sum;
    end

    % 统一"越小越优" → 灵活性取负号
    f = w_cost   * C_cost_total   + ...
        w_carbon * C_carbon_year - ...
        w_flex   * K_flex_total;
    
    % 输出汇总信息（可选）
    if VERBOSE_SEASON
        fprintf('年度汇总: 成本=%.2f万元, 碳排=%.2ft, 综合灵活性=%.3f\n', ...
                C_cost_year, C_carbon_year, K_flex_total);
        fprintf('目标函数值: f=%.4f\n', f);
    end
    
    % 监控输出
    if mod(call_count, 10) == 0 || call_count <= 3
        fprintf('调用#%d: 成本=%.2f, 碳排=%.4f, 灵活性=%.2f → 适应度=%.6f\n', ...
                call_count, C_cost_total, C_carbon_year, K_flex_total, f);
    end
    
    % 检测异常值
    if isnan(f) || isinf(f)
        fprintf('❌ 异常：适应度为 %f，输入x[1:5]=[%.3f %.3f %.3f %.3f %.3f]\n', ...
                f, x(1), x(2), x(3), x(4), x(5));
    end

catch ME
    % 使用规范的warning格式
    warning('fun_objective:error', '%s', ME.message);
    fprintf('错误位置:\n');
    for i = 1:min(3, length(ME.stack))
        fprintf('  %s (第%d行)\n', ME.stack(i).name, ME.stack(i).line);
    end
    f = 1e8;
end

end  % 主函数结束

%% 子函数：2选1方案的投资成本计算
function C_invest = calculate_investment_cost_2in1(num_pv_nodes, num_wind_nodes, ...
                                                   num_ess_nodes, xL, cap_sop_nodes)
    global cpv cwind cP_ess cE_ess csop sc
    global s_pv s_wind s_cn s_sop_min
    global r life_PV life_WT life_ESS life_SOP
    
    % 计算总投资
    C_pv = sum(num_pv_nodes) * s_pv * cpv;
    C_wind = sum(num_wind_nodes) * s_wind * cwind;
    C_ess = sum(num_ess_nodes) * s_cn * (cP_ess + cE_ess * 4);  % 假设4小时储能
    
    % 联络开关投资（假设单价）
    C_switch = sum(xL) * 50000;  % 假设每个联络开关5万元
    
    % SOP投资
    C_sop = 0;
    for i = 1:length(cap_sop_nodes)
        if cap_sop_nodes(i) > 0
            num_sop = round(cap_sop_nodes(i) * 1e3 / s_sop_min);
            C_sop = C_sop + num_sop * s_sop_min * csop + sc;
        end
    end
    
    % 年化（使用资本回收系数）
    CRF_pv = r * (1+r)^life_PV / ((1+r)^life_PV - 1);
    CRF_wind = r * (1+r)^life_WT / ((1+r)^life_WT - 1);
    CRF_ess = r * (1+r)^life_ESS / ((1+r)^life_ESS - 1);
    CRF_sop = r * (1+r)^life_SOP / ((1+r)^life_SOP - 1);
    CRF_switch = r * (1+r)^20 / ((1+r)^20 - 1);  % 假设开关寿命20年
    
    % 年化投资成本（万元）
    C_invest = (C_pv * CRF_pv + C_wind * CRF_wind + ...
                C_ess * CRF_ess + C_sop * CRF_sop + ...
                C_switch * CRF_switch) / 1e4 / 365;  % 日均
end