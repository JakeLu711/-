function [bestSched, C_cost, C_carbon, kPR_d, kGR_d] = runLowerLayer(upx, solver)
%======================================================================
% runLowerLayer - 改进版的日内运行调度（记录GA收敛历史）
% 使用持久变量记录GA收敛过程
%======================================================================

%% ========== 第1部分：基础参数处理 ==========
if nargin < 2, solver = 'GA'; end

% 全局变量声明
global K T;
global GA_MAXGEN GA_POPSIZE;
global w_cost_base w_flex_base w_carbon_base;
global Ce_min Ce_max kPR_min kPR_max CF_min CF_max;
global GA_CONVERGENCE_HISTORY;  % 新增：GA收敛历史

% 清空之前的GA收敛历史
GA_CONVERGENCE_HISTORY = [];

%% ========== 第2部分：GA参数获取与验证 ==========
fprintf('\n=== runLowerLayer 参数获取 ===\n');

% 从全局变量获取GA参数
if exist('GA_MAXGEN', 'var') && ~isempty(GA_MAXGEN) && GA_MAXGEN > 0
    ga_max_gen = GA_MAXGEN;
else
    ga_max_gen = 20;
end
if exist('GA_POPSIZE', 'var') && ~isempty(GA_POPSIZE) && GA_POPSIZE > 0
    ga_pop_size = GA_POPSIZE;
else
    ga_pop_size = 30;
end

% 参数范围约束␊
ga_max_gen = max(1, min(ga_max_gen, 100));
ga_pop_size = max(3, min(ga_pop_size, 100));

%% ========== 第3部分：决策变量设置 ==========
nVar = 5 * K * T;
lb = zeros(1, nVar);
ub = ones(1, nVar);

fprintf('📐 决策变量信息:\n');
fprintf('   变量总数: %d\n', nVar);
fprintf('   GA参数: %d代 × %d个体\n', ga_max_gen, ga_pop_size);

%% ========== 第4部分：优化求解器 ==========
switch upper(solver)
    case 'GA'
        % 目标函数定义
        objFun = @(x) fitnessFcn(x, upx);
        
        % GA选项设置
        elite_count = max(1, floor(ga_pop_size / 5));
        elite_count = min(elite_count, ga_pop_size - 1);
        
        % 设置输出函数
        opts = optimoptions('ga', ...
            'PopulationSize', ga_pop_size, ...
            'MaxGenerations', ga_max_gen, ...
            'EliteCount', elite_count, ...
            'MutationFcn', {@mutationuniform, 0.1}, ...
            'CrossoverFcn', @crossoverscattered, ...
            'SelectionFcn', @selectionroulette, ...
            'Display', 'iter', ...
            'PlotFcn', [], ...
            'OutputFcn', @gaOutputFcn_simple, ...  % 使用简单的输出函数
            'UseParallel', false);

        % 执行GA优化
        fprintf('\n🚀 开始GA优化...\n');
        tic_ga = tic;
        
        try
            [bestSched, best_fval] = ga(objFun, nVar, [], [], [], [], lb, ub, [], opts);
            elapsed_ga = toc(tic_ga);
            
            fprintf('✅ GA优化完成!\n');
            fprintf('   总耗时: %.2f秒\n', elapsed_ga);
            fprintf('   最优适应度: %.6f\n', best_fval);
            
            % 如果收敛历史为空，至少记录最终值
            if isempty(GA_CONVERGENCE_HISTORY)
                GA_CONVERGENCE_HISTORY = best_fval;
            end
            
        catch ME
            elapsed_ga = toc(tic_ga);
            fprintf('❌ GA优化失败 (已运行%.2f秒)\n', elapsed_ga);
            fprintf('   错误信息: %s\n', ME.message);
            bestSched = rand(1, nVar) * 0.5;
            GA_CONVERGENCE_HISTORY = [];
        end

    case 'PSO'
        error('runLowerLayer: PSO求解器尚未实现');
        
    case 'RANDOM'
        fprintf('使用随机调度方案\n');
        bestSched = rand(1, nVar) * 0.5;
        GA_CONVERGENCE_HISTORY = [];
        
    otherwise
        error('runLowerLayer: 未实现求解器 %s', solver);
end

%% ========== 第5部分：结果计算与输出 ==========
fprintf('\n📊 计算最终运行指标...\n');

try
    [C_cost, C_carbon, kPR_d, kGR_d] = evaluateSchedule(bestSched, upx);
    
    fprintf('✅ 指标计算完成:\n');
    fprintf('   经济成本: %.4f 万元/日\n', C_cost);
    fprintf('   碳排放量: %.6f t CO2/日\n', C_carbon);
    fprintf('   功率调节灵活性: %.4f\n', kPR_d);
    fprintf('   网架调节灵活性: %.4f\n', kGR_d);
    
catch ME
    fprintf('❌ 指标计算失败: %s\n', ME.message);
    C_cost = 1e6;
    C_carbon = 1e6;
    kPR_d = 0;
    kGR_d = 0;
end

end  % 主函数结束

%% ========== 子函数定义 ==========

% GA输出函数（简化版，使用全局变量）
function [state, options, optchanged] = gaOutputFcn_simple(options, state, flag)
    global GA_CONVERGENCE_HISTORY;
    
    optchanged = false;
    
    switch flag
        case 'iter'
            % 记录每代的最佳适应度
            if isempty(GA_CONVERGENCE_HISTORY)
                GA_CONVERGENCE_HISTORY = state.Best(end);
            else
                GA_CONVERGENCE_HISTORY(end+1) = state.Best(end);
            end
            
            % 输出进度
            if mod(state.Generation, max(1, floor(options.MaxGenerations/5))) == 0 || state.Generation == 1
                fprintf('   GA进度: 第%d/%d代, 最优: %.6f\n', ...
                        state.Generation, options.MaxGenerations, state.Best(end));
            end
    end
end

% 适应度函数
function f = fitnessFcn(xSched, upx)
    try
        [C_cost_temp, C_carbon_temp, kPR_d_temp, kGR_d_temp] = evaluateSchedule(xSched, upx);
        [phi1, phi2, phi3] = fuzzMembership(C_cost_temp, C_carbon_temp, kPR_d_temp, kGR_d_temp);
        
        % 获取权重
        global w_cost_base w_flex_base w_carbon_base;
        if isempty(w_cost_base) || isempty(w_flex_base) || isempty(w_carbon_base)
            wc  = 0.5;
            wcb = 0.25;
            wf  = 0.25;
        else
            wc  = w_cost_base;
            wcb = w_carbon_base;
            wf  = w_flex_base;
        end

        satisfaction = wc*phi1 + wcb*phi2 + wf*phi3;
        f = -satisfaction;
        
        if isnan(f) || isinf(f)
            f = 1e6;
        end
        
    catch
        f = 1e6;
    end
end

% 评估调度方案
function [C_cost_out, C_carbon_out, kPR_d_out, kGR_d_out] = evaluateSchedule(xSched, upx)
    try
        res = lower_obj(xSched, upx);
        C_cost_out    = res(1);
        C_carbon_out  = res(2);
        kPR_d_out     = -res(3);
        kGR_d_out     = -res(4);
        
        % 数据合理性检查
        if isnan(C_cost_out) || isinf(C_cost_out) || C_cost_out < 0
            C_cost_out = 1e6;
        end
        
        if isnan(C_carbon_out) || isinf(C_carbon_out) || C_carbon_out < 0
            C_carbon_out = 1e6;
        end
        
        if isnan(kPR_d_out) || isinf(kPR_d_out)
            kPR_d_out = 0;
        end
        
        if isnan(kGR_d_out) || isinf(kGR_d_out)
            kGR_d_out = 0;
        end
        
    catch
        C_cost_out   = 1e9;
        C_carbon_out = 1e9;
        kPR_d_out    = 0;
        kGR_d_out    = 0;
    end
end
