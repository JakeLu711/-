function [best_up, bestFitHistory, paretoSet] = HScore_TOPSIS()
% HScore_TOPSIS - 基于TOPSIS的上层和声搜索算法
% 输出增加paretoSet用于存储Pareto前沿解

%% 全局参数
global VarMin VarMax
LOW  = VarMin;
HIGH = VarMax;
NVAR = numel(LOW);

%% HS算法参数 - 修正：使用全局变量
global HS_MAXITERS HS_HMS;

% 使用全局变量，如果未设置则使用默认值
if isempty(HS_HMS) || HS_HMS == 0
    HMS = 10;
else
    HMS = HS_HMS;
end

if isempty(HS_MAXITERS) || HS_MAXITERS == 0
    MAXITERS = 400;
else
    MAXITERS = HS_MAXITERS;
end

fprintf('📋 HS参数确认: HMS=%d, MAXITERS=%d\n', HMS, MAXITERS);

HMCR     = 0.9;
PAR_MIN  = 0.35;    PAR_MAX = 0.9;
BW_MAX   = 0.02;    BW_MIN  = 1e-5;

%% 初始化
HM = initHarmonyMemory(HMS, NVAR, LOW, HIGH);
bestFitHistory = zeros(MAXITERS,1);

% 用于存储Pareto前沿解
paretoSet = [];  % 每行: [决策变量, 经济成本, 碳排放, 灵活性]

%% 主循环
for gen = 1:MAXITERS
    fprintf('\n🔄 HS迭代 %d/%d:\n', gen, MAXITERS);
    PAR = PAR_MIN + (PAR_MAX-PAR_MIN)*(gen/MAXITERS);
    c   = log(BW_MIN/BW_MAX)/MAXITERS;
    BW  = BW_MAX * exp(c*gen);

    % 生成新和声
    varMatrix = HM(:,1:NVAR);
    stddev  = std(varMatrix,0,1);
    lowHM   = min(varMatrix,[],1);
    highHM  = max(varMatrix,[],1);
    
    NCHV = zeros(1,NVAR);
    for i = 1:NVAR
        if rand < HMCR
            NCHV(i) = HM(randi(HMS), i);
            if rand < PAR
                delta = rand * BW;
                if rand < 0.5
                    NCHV(i) = min(HIGH(i), NCHV(i) + delta);
                else
                    NCHV(i) = max(LOW(i),  NCHV(i) - delta);
                end
            end
        else
            if stddev(i) > 1e-4
                NCHV(i) = LOW(i) + rand*(HIGH(i)-LOW(i));
            else
                NCHV(i) = lowHM(i) + rand*(highHM(i)-lowHM(i));
            end
        end
    end
    
    % 评估新和声的各目标值
    [C_cost, C_carbon, K_flex] = evaluate_objectives(NCHV);
    fprintf('   新和声目标值: [%.2f, %.4f, %.2f]\n', C_cost, C_carbon, K_flex);
    
    % 更新Pareto前沿集
    new_solution = [NCHV, C_cost, C_carbon, K_flex];
    paretoSet = updateParetoSet(paretoSet, new_solution, NVAR);
    
    if ~isempty(paretoSet)
        fprintf('   当前Pareto解数量: %d\n', size(paretoSet,1));
        if size(paretoSet,1) > 1
            costs = paretoSet(:, NVAR+1);
            fprintf('   成本范围: [%.2f, %.2f]\n', min(costs), max(costs));
        end
    end
    
    % 更新和声记忆（使用简单适应度）
    simple_fitness = C_cost - 0.3 * K_flex;  % 临时适应度
    HM = updateMemory(HM, NCHV, simple_fitness, NVAR);
    
    % 记录历史
    bestFitHistory(gen) = min(HM(:,NVAR+1));
    
    % 每隔一定代数输出信息
    if mod(gen, max(1, floor(MAXITERS/10))) == 0
        fprintf('迭代 %d: Pareto前沿解数量 = %d\n', gen, size(paretoSet,1));
    end
end

%% 使用TOPSIS选择最终方案
if ~isempty(paretoSet)
    % 提取目标值
    objectives = paretoSet(:, NVAR+1:end);  % [经济成本, 碳排放, 灵活性]
    
    % 设置权重和准则
    weights = [0.5, 0.25, 0.25];  % 经济:碳排放:灵活性 = 0.5:0.25:0.25
    criteria = [false, false, true];  % 经济和碳排放越小越好，灵活性越大越好
    
    % TOPSIS评估
    [best_idx, scores] = topsis_evaluation(objectives, weights, criteria);
    
    % 输出TOPSIS结果
    fprintf('\n=== TOPSIS评估结果 ===\n');
    fprintf('Pareto前沿解数量: %d\n', size(paretoSet,1));
    fprintf('最优方案索引: %d\n', best_idx);
    fprintf('TOPSIS得分: %.4f\n', scores(best_idx));
    fprintf('最优方案目标值:\n');
    fprintf('  经济成本: %.4f 万元\n', objectives(best_idx,1));
    fprintf('  碳排放: %.4f t\n', objectives(best_idx,2));
    fprintf('  灵活性: %.4f\n', objectives(best_idx,3));
    
    % 返回最优方案
    best_up = paretoSet(best_idx, 1:NVAR);
else
    % 如果没有Pareto解，返回和声记忆中最好的
    [~, idx] = min(HM(:,NVAR+1));
    best_up = HM(idx, 1:NVAR);
end

end

%% 子函数：初始化和声记忆
function HM = initHarmonyMemory(HMS, NVAR, LOW, HIGH)
    HM = zeros(HMS, NVAR+1);
    for n = 1:HMS
        x = LOW + (HIGH-LOW).*rand(1, NVAR);
        HM(n,1:NVAR) = x;
        HM(n,NVAR+1) = fun_objective(x);  % 使用简单适应度
    end
end

%% 子函数：更新和声记忆
function HM = updateMemory(HM, NCHV, fval, NVAR)
    [~, worstIdx] = max(HM(:,NVAR+1));
    if fval < HM(worstIdx, NVAR+1)
        HM(worstIdx,1:NVAR) = NCHV;
        HM(worstIdx,NVAR+1) = fval;
    end
end

%% 子函数：评估目标值
function [C_cost, C_carbon, K_flex] = evaluate_objectives(x)
    % 调试版本的目标函数评估
    persistent call_count;
    if isempty(call_count), call_count = 0; end
    call_count = call_count + 1;
    
    try
        % 获取支路类型与SOP容量
        global numBr;
        branch_types   = x(end-2*numBr+1:end-numBr);
        sop_cap_nodes  = x(end-numBr+1:end);
        % 将支路类型编码转换为0/1联络开关状态
        xL = double(branch_types >= 0.5 & branch_types < 1.5);
        % 调用下层优化
        [~, C_cost, C_carbon, kPR_d, kGR_d] = runLowerLayer(x, 'GA');
        
        % 计算中长期灵活性 (如果fun_flexibility不存在或失败，用简化版本)
        if exist('fun_flexibility', 'file')
            try
                K_flex = fun_flexibility(xL, sop_cap_nodes);
            catch MEflex
                fprintf('⚠️ 灵活性计算失败: %s\n', MEflex.message);
                K_flex = kPR_d + kGR_d + sum(xL) * 10;  % 回退简化计算
            end
        else
            % 简化的灵活性计算
            K_flex = kPR_d + kGR_d + sum(xL) * 10;  % 临时计算
        end
        
        % 调试输出 - 每20次输出一次
        if call_count <= 3 || mod(call_count, 20) == 0
            fprintf('📊 目标函数调用#%d:\n', call_count);
            fprintf('   输入变量范围: [%.4f, %.4f]\n', min(x), max(x));
            fprintf('   经济成本: %.2f 万元\n', C_cost);
            fprintf('   碳排放: %.4f t\n', C_carbon);
            fprintf('   短期灵活性: kPR=%.3f, kGR=%.3f\n', kPR_d, kGR_d);
            fprintf('   中长期灵活性: %.2f\n', K_flex);
            fprintf('   联络开关状态: %s\n', mat2str(round(xL)));
            fprintf('   SOP容量: %s\n', mat2str(sop_cap_nodes,3));
        end
        
        % 异常检测
        if isnan(C_cost) || isinf(C_cost) || C_cost <= 0
            fprintf('⚠️ 异常：经济成本 = %.4f\n', C_cost);
        end
        
        if isnan(K_flex) || isinf(K_flex)
            fprintf('⚠️ 异常：灵活性指标 = %.4f\n', K_flex);
        end
        
    catch ME
        fprintf('❌ 目标函数计算失败: %s\n', ME.message);
        C_cost = 1e6;
        C_carbon = 1e6;
        K_flex = 0;
    end
end

%% 子函数：简单适应度函数（用于初始化）
function f = fun_objective(x)
    % 简化的适应度计算，避免初始化时过于复杂
    try
        [~, C_cost, C_carbon, kPR_d, kGR_d] = runLowerLayer(x, 'GA');
        % 简单的加权适应度
        f = C_cost - 0.3 * (kPR_d + kGR_d);
    catch
        % 如果计算失败，返回大惩罚值
        f = 1e6;
    end
end

%% 子函数：更新Pareto前沿集
function paretoSet = updateParetoSet(paretoSet, new_solution, NVAR)
    if isempty(paretoSet)
        paretoSet = new_solution;
        return;
    end
    
    % 检查是否被支配
    objectives_new = new_solution(NVAR+1:end);
    dominated = false;
    
    to_remove = [];
    for i = 1:size(paretoSet,1)
        objectives_i = paretoSet(i, NVAR+1:end);
        
        % 检查new_solution是否被第i个解支配
        % 注意：对于最小化的目标（成本、排放），值越小越好
        % 对于最大化的目标（灵活性），值越大越好
        if (objectives_i(1) <= objectives_new(1) && ...
            objectives_i(2) <= objectives_new(2) && ...
            objectives_i(3) >= objectives_new(3)) && ...
           (objectives_i(1) < objectives_new(1) || ...
            objectives_i(2) < objectives_new(2) || ...
            objectives_i(3) > objectives_new(3))
            dominated = true;
            break;
        end
        
        % 检查第i个解是否被new_solution支配
        if (objectives_new(1) <= objectives_i(1) && ...
            objectives_new(2) <= objectives_i(2) && ...
            objectives_new(3) >= objectives_i(3)) && ...
           (objectives_new(1) < objectives_i(1) || ...
            objectives_new(2) < objectives_i(2) || ...
            objectives_new(3) > objectives_i(3))
            to_remove = [to_remove, i];
        end
    end
    
    % 更新Pareto集
    if ~dominated
        paretoSet(to_remove,:) = [];  % 移除被支配的解
        paretoSet = [paretoSet; new_solution];  % 添加新解
        
        % 限制Pareto集大小（可选）
        if size(paretoSet,1) > 50
            % 保留分布最均匀的50个解
            paretoSet = maintainDiversity(paretoSet, 50, NVAR);
        end
    end
end

%% 子函数：维持Pareto集的多样性
function paretoSet = maintainDiversity(paretoSet, maxSize, NVAR)
    if size(paretoSet,1) <= maxSize
        return;
    end
    
    % 使用拥挤距离排序
    objectives = paretoSet(:, NVAR+1:end);
    n = size(paretoSet,1);
    crowding_distance = zeros(n,1);
    
    % 对每个目标维度计算拥挤距离
    for m = 1:size(objectives,2)
        [~, idx] = sort(objectives(:,m));
        crowding_distance(idx(1)) = inf;
        crowding_distance(idx(end)) = inf;
        
        for i = 2:n-1
            crowding_distance(idx(i)) = crowding_distance(idx(i)) + ...
                (objectives(idx(i+1),m) - objectives(idx(i-1),m));
        end
    end
    
    % 选择拥挤距离最大的解
    [~, idx] = sort(crowding_distance, 'descend');
    paretoSet = paretoSet(idx(1:maxSize), :);
end
