function main()
% main_improved - 改进的主动配电网源网储多元协调规划主程序
% 修复了收敛曲线、报告生成和图表显示等问题

%% ========== 1. 清理环境和初始化 ==========
fprintf('\n========== 主动配电网源网储多元协调规划 ==========\n');
fprintf('开始时间: %s\n', datestr(now));

clear global;
close all;
clc;

%% ========== 2. 参数设置 ==========
fprintf('\n初始化系统参数...\n');

% ---------- 运行模式选择 ----------
%RUN_MODE = 'NORMAL';  % 改为NORMAL模式以获得更好的优化效果
RUN_MODE = 'QUICK';   % 快速测试模式

% ---------- 算法参数设置 ----------
global HS_MAXITERS HS_HMS HS_HMCR HS_PAR_MIN HS_PAR_MAX
global GA_MAXGEN GA_POPSIZE
global VERBOSE_SEASON

switch RUN_MODE
        case 'QUICK'
        HS_MAXITERS = 50;    % 增加到50次␊
        HS_HMS = 10;
        GA_MAXGEN = 20;
        GA_POPSIZE = 30;
        fprintf('运行模式: 快速测试\n');
    case 'NORMAL'
        HS_MAXITERS = 200;   
        HS_HMS = 10;         
        GA_MAXGEN = 30;      
        GA_POPSIZE = 40;     
        fprintf('运行模式: 正常运行\n');
        
    case 'HIGH_QUALITY'
        HS_MAXITERS = 400;   
        HS_HMS = 15;         
        GA_MAXGEN = 40;      
        GA_POPSIZE = 50;     
        fprintf('运行模式: 高质量优化\n');
end

% ---------- 其他参数 ----------
HS_HMCR = 0.9;           
HS_PAR_MIN = 0.35;       
HS_PAR_MAX = 0.9;        
VERBOSE_SEASON = true;   % 开启季节详细信息输出

% ---------- 并行计算设置 ----------
if license('test', 'Distrib_Computing_Toolbox')
    if isempty(gcp('nocreate'))
        fprintf('启动并行计算...\n');
        parpool('local', min(4, feature('numcores')));
    end
end

%% ========== 3. 数据准备 ==========
fprintf('\n准备数据...\n');

% 初始化参数
parameter();

% 检查并生成典型日数据
if ~exist('pv_typical.mat', 'file') || ~exist('wd_typical.mat', 'file')
    fprintf('生成典型日数据...\n');
    makeTypicalDays();
else
    fprintf('加载已有典型日数据...\n');
end

% 加载典型日数据
loadTypicalData();

% 显示数据信息
global K T numBr
fprintf('典型日场景数: K=%d\n', K);
fprintf('时段数: T=%d\n', T);
fprintf('联络开关数: %d\n', numBr);

%% ========== 4. 运行优化 ==========
fprintf('\n========== 开始优化计算 ==========\n');

% 记录开始时间
tic_main = tic;

% 存储GA收敛历史
global GA_CONVERGENCE_HISTORY
GA_CONVERGENCE_HISTORY = [];

% ---------- 运行主优化 ----------
try
    fprintf('运行和声搜索算法（结合TOPSIS）...\n');
    fprintf('预计运行时间: ');
    switch RUN_MODE
        case 'QUICK'
            fprintf('0.5-1小时\n');
        case 'NORMAL'
            fprintf('4-8小时\n');
        case 'HIGH_QUALITY'
            fprintf('12-24小时\n');
    end
    
    % 调用优化函数
    [best_solution, bestFitHistory, paretoSet] = HScore_TOPSIS();
    
    % 记录结束时间
    elapsed_time = toc(tic_main);
    fprintf('\n优化完成！总耗时: %.2f小时\n', elapsed_time/3600);
    
catch ME
    fprintf('\n✗ 优化过程出错: %s\n', ME.message);
    fprintf('错误位置:\n');
    for i = 1:min(5, length(ME.stack))
        fprintf('  %s (第%d行)\n', ME.stack(i).name, ME.stack(i).line);
    end
    return;
end

%% ========== 5. 结果分析 ==========
fprintf('\n========== 结果分析 ==========\n');

% 5.1 显示和存储最优方案
fprintf('\n--- 最优规划方案 ---\n');
[decoded_solution] = decode_and_display_solution(best_solution);

% 5.2 四季性能分析
fprintf('\n--- 四季运行性能分析 ---\n');
[seasonal_results] = analyze_seasonal_performance(best_solution);

% 5.3 Pareto前沿分析
if size(paretoSet, 1) > 1
    fprintf('\n--- Pareto前沿分析 ---\n');
    fprintf('Pareto前沿解数量: %d\n', size(paretoSet, 1));
    analyze_pareto_front(paretoSet, best_solution);
end

%% ========== 6. 结果可视化 ==========
fprintf('\n生成可视化图表...\n');

% 定义柔和的配色方案
colors = struct();
colors.hs = [0.4, 0.6, 0.8];        % 柔和蓝色
colors.ga = [0.8, 0.6, 0.4];        % 柔和橙色
colors.spring = [0.6, 0.8, 0.4];    % 柔和绿色
colors.summer = [0.9, 0.7, 0.3];    % 柔和黄色
colors.autumn = [0.8, 0.5, 0.3];    % 柔和棕色
colors.winter = [0.5, 0.6, 0.7];    % 柔和灰蓝
colors.cost = [0.7, 0.7, 0.9];      % 淡紫色
colors.carbon = [0.9, 0.7, 0.7];    % 淡红色
colors.flexibility = [0.7, 0.9, 0.7]; % 淡绿色

%% 6.1 收敛曲线（HS和GA上下排列）
figure('Name', '优化算法收敛曲线', 'Position', [100, 100, 800, 800]);

% 准备数据
iterations_hs = 1:length(bestFitHistory);
has_ga_data = ~isempty(GA_CONVERGENCE_HISTORY);

% 子图1：和声搜索收敛曲线
subplot(2,1,1);
plot(iterations_hs, bestFitHistory, '-', 'LineWidth', 2.5, 'Color', colors.hs);
xlabel('迭代次数', 'FontSize', 12);
ylabel('目标函数值', 'FontSize', 12);
title('和声搜索算法 (HS) 收敛曲线', 'FontSize', 13, 'FontWeight', 'bold');
grid on;
box on;
set(gca, 'GridAlpha', 0.3);

% 添加HS收敛信息
hs_improve = (bestFitHistory(1)-bestFitHistory(end))/bestFitHistory(1)*100;
text_str = sprintf('初始值: %.4f\n最终值: %.4f\n改进率: %.2f%%', ...
    bestFitHistory(1), bestFitHistory(end), hs_improve);
text(0.02, 0.98, text_str, 'Units', 'normalized', ...
     'VerticalAlignment', 'top', 'FontSize', 10, ...
     'BackgroundColor', [1, 1, 1, 0.8], 'EdgeColor', 'none');

% 标记最优值点
[min_val, min_idx] = min(bestFitHistory);
hold on;
plot(min_idx, min_val, 'o', 'MarkerSize', 8, ...
     'MarkerFaceColor', colors.hs*0.8, 'MarkerEdgeColor', colors.hs*0.6);
text(min_idx, min_val, sprintf(' %.4f', min_val), ...
     'VerticalAlignment', 'bottom', 'FontSize', 9);

% 子图2：遗传算法收敛曲线
subplot(2,1,2);
if has_ga_data
    iterations_ga = 1:length(GA_CONVERGENCE_HISTORY);
    plot(iterations_ga, GA_CONVERGENCE_HISTORY, '-', 'LineWidth', 2.5, 'Color', colors.ga);
    xlabel('迭代次数', 'FontSize', 12);
    ylabel('适应度值', 'FontSize', 12);
    title('遗传算法 (GA) 收敛曲线', 'FontSize', 13, 'FontWeight', 'bold');
    grid on;
    box on;
    set(gca, 'GridAlpha', 0.3);
    
    % 添加GA收敛信息
    ga_improve = (GA_CONVERGENCE_HISTORY(1)-GA_CONVERGENCE_HISTORY(end))/GA_CONVERGENCE_HISTORY(1)*100;
    text_str = sprintf('初始值: %.4f\n最终值: %.4f\n改进率: %.2f%%', ...
        GA_CONVERGENCE_HISTORY(1), GA_CONVERGENCE_HISTORY(end), ga_improve);
    text(0.02, 0.98, text_str, 'Units', 'normalized', ...
         'VerticalAlignment', 'top', 'FontSize', 10, ...
         'BackgroundColor', [1, 1, 1, 0.8], 'EdgeColor', 'none');
    
    % 标记最优值点
    [min_val_ga, min_idx_ga] = min(GA_CONVERGENCE_HISTORY);
    hold on;
    plot(min_idx_ga, min_val_ga, 'o', 'MarkerSize', 8, ...
         'MarkerFaceColor', colors.ga*0.8, 'MarkerEdgeColor', colors.ga*0.6);
    text(min_idx_ga, min_val_ga, sprintf(' %.4f', min_val_ga), ...
         'VerticalAlignment', 'bottom', 'FontSize', 9);
else
    % 没有GA数据时显示提示
    text(0.5, 0.5, '暂无GA收敛数据', ...
         'HorizontalAlignment', 'center', ...
         'VerticalAlignment', 'middle', ...
         'FontSize', 14, 'Color', [0.5, 0.5, 0.5]);
    title('遗传算法 (GA) 收敛曲线', 'FontSize', 13, 'FontWeight', 'bold');
    grid on;
    box on;
    set(gca, 'GridAlpha', 0.3);
    xlabel('迭代次数', 'FontSize', 12);
    ylabel('适应度值', 'FontSize', 12);
end

% 调整子图间距
set(gcf, 'Position', [100, 100, 800, 700]);

%% 6.2 四季性能综合图（柱状图组合）
figure('Name', '四季运行性能对比', 'Position', [950, 100, 1000, 600]);

season_names = {'春', '夏', '秋', '冬'};
x_pos = 1:4;

% 准备数据（归一化处理）
cost_data = seasonal_results(:, 1);
carbon_data = seasonal_results(:, 2);
kPR_data = seasonal_results(:, 3);
kGR_data = seasonal_results(:, 4);

% 创建子图1：成本和碳排放
subplot(2,1,1);
hold on;

% 设置柱状图宽度
bar_width = 0.35;

% 绘制成本柱状图
b1 = bar(x_pos - bar_width/2, cost_data, bar_width, ...
         'FaceColor', colors.cost, 'EdgeColor', 'none');

% 绘制碳排放柱状图（使用双Y轴）
yyaxis right;
b2 = bar(x_pos + bar_width/2, carbon_data, bar_width, ...
         'FaceColor', colors.carbon, 'EdgeColor', 'none');

% 设置坐标轴
yyaxis left;
ylabel('运行成本 (万元/日)', 'FontSize', 12);
ylim([0, max(cost_data) * 1.2]);
ax = gca;
ax.YAxis(1).Color = colors.cost * 0.8;

yyaxis right;
ylabel('碳排放 (t CO_2/日)', 'FontSize', 12);
ylim([0, max(carbon_data) * 1.2]);
ax.YAxis(2).Color = colors.carbon * 0.8;

% 设置x轴
set(gca, 'XTick', x_pos);
set(gca, 'XTickLabel', season_names);
xlabel('季节', 'FontSize', 12);
title('经济性与环保性指标', 'FontSize', 13);

% 添加数值标签
for i = 1:4
    % 成本标签
    text(x_pos(i) - bar_width/2, cost_data(i) + max(cost_data)*0.02, ...
         sprintf('%.1f', cost_data(i)), ...
         'HorizontalAlignment', 'center', 'FontSize', 10);
    % 碳排放标签
    text(x_pos(i) + bar_width/2, carbon_data(i) + max(carbon_data)*0.02, ...
         sprintf('%.2f', carbon_data(i)), ...
         'HorizontalAlignment', 'center', 'FontSize', 10);
end

legend({'运行成本', '碳排放'}, 'Location', 'northwest', 'FontSize', 11);
grid on;
set(gca, 'GridAlpha', 0.3);

% 创建子图2：灵活性指标
subplot(2,1,2);
hold on;

% 绘制功率灵活性
b3 = bar(x_pos - bar_width/2, kPR_data, bar_width, ...
         'FaceColor', colors.flexibility, 'EdgeColor', 'none');

% 绘制网架灵活性
b4 = bar(x_pos + bar_width/2, kGR_data, bar_width, ...
         'FaceColor', colors.flexibility * 0.8, 'EdgeColor', 'none');

% 设置坐标轴
ylabel('灵活性指标', 'FontSize', 12);
ylim([0, 1.2]);
set(gca, 'XTick', x_pos);
set(gca, 'XTickLabel', season_names);
xlabel('季节', 'FontSize', 12);
title('灵活性指标', 'FontSize', 13);

% 添加数值标签
for i = 1:4
    text(x_pos(i) - bar_width/2, kPR_data(i) + 0.02, ...
         sprintf('%.3f', kPR_data(i)), ...
         'HorizontalAlignment', 'center', 'FontSize', 10);
    text(x_pos(i) + bar_width/2, kGR_data(i) + 0.02, ...
         sprintf('%.3f', kGR_data(i)), ...
         'HorizontalAlignment', 'center', 'FontSize', 10);
end

legend({'功率调节灵活性 (k_{PR})', '网架调节灵活性 (k_{GR})'}, ...
       'Location', 'best', 'FontSize', 11);
grid on;
set(gca, 'GridAlpha', 0.3);

%% 6.3 如果有Pareto前沿，绘制3D图（使用柔和配色）
if size(paretoSet, 1) > 3
    figure('Name', 'Pareto前沿', 'Position', [100, 400, 800, 600]);
    plot_pareto_front_3d_soft(paretoSet, best_solution);
end
%% ========== 7. 保存结果 ==========
fprintf('\n保存优化结果...\n');

% 生成时间戳
timestamp = datestr(now, 'yyyymmdd_HHMMSS');

% 保存结果
save_filename = sprintf('optimization_result_%s_%s.mat', RUN_MODE, timestamp);
save(save_filename, 'best_solution', 'bestFitHistory', 'paretoSet', ...
     'elapsed_time', 'RUN_MODE', 'decoded_solution', 'seasonal_results', ...
     'GA_CONVERGENCE_HISTORY');

fprintf('结果已保存至: %s\n', save_filename);

% 生成详细报告
generate_detailed_report(best_solution, decoded_solution, seasonal_results, ...
                        paretoSet, elapsed_time, timestamp);

fprintf('\n========== 优化完成 ==========\n');
fprintf('结束时间: %s\n', datestr(now));

end

%% ========== 改进的辅助函数 ==========
function [decoded] = decode_and_display_solution(solution)
% decode_and_display_solution - 解码并显示优化解决方案
% 支持多点安装 + 联络开关/SOP 2选1方案

    global st_pvc st_windc st_essc tieBranches numBr
    global s_pv s_wind s_cn s_sop_min
    
    idx = 1;
    
    %% ========== 解码PV（多点） ==========
    cap_pv_nodes = solution(idx:idx+length(st_pvc)-1);
    idx = idx + length(st_pvc);
    num_pv_nodes = round(cap_pv_nodes * 1e3 / s_pv);
    
    fprintf('\n========== 最优规划方案 ==========\n');
    fprintf('光伏配置:\n');
    total_pv = 0;
    pv_installed = false;
    for i = 1:length(st_pvc)
        if num_pv_nodes(i) > 0
            fprintf('  节点%d: %.2f MW (%d台 × %d kW/台)\n', ...
                    st_pvc(i), cap_pv_nodes(i), num_pv_nodes(i), s_pv);
            total_pv = total_pv + cap_pv_nodes(i);
            pv_installed = true;
        end
    end
    if ~pv_installed
        fprintf('  未安装光伏\n');
    else
        fprintf('  总容量: %.2f MW\n', total_pv);
    end
    
    %% ========== 解码Wind（多点） ==========
    cap_wind_nodes = solution(idx:idx+length(st_windc)-1);
    idx = idx + length(st_windc);
    num_wind_nodes = round(cap_wind_nodes * 1e3 / s_wind);
    
    fprintf('\n风电配置:\n');
    total_wind = 0;
    wind_installed = false;
    for i = 1:length(st_windc)
        if num_wind_nodes(i) > 0
            fprintf('  节点%d: %.2f MW (%d台 × %d kW/台)\n', ...
                    st_windc(i), cap_wind_nodes(i), num_wind_nodes(i), s_wind);
            total_wind = total_wind + cap_wind_nodes(i);
            wind_installed = true;
        end
    end
    if ~wind_installed
        fprintf('  未安装风电\n');
    else
        fprintf('  总容量: %.2f MW\n', total_wind);
    end
    
    %% ========== 解码ESS（多点） ==========
    cap_ess_nodes = solution(idx:idx+length(st_essc)-1);
    idx = idx + length(st_essc);
    num_ess_nodes = round(cap_ess_nodes * 1e3 / s_cn);
    
    fprintf('\n储能配置:\n');
    total_ess = 0;
    ess_installed = false;
    for i = 1:length(st_essc)
        if num_ess_nodes(i) > 0
            fprintf('  节点%d: %.2f MW (%d台 × %d kW/台)\n', ...
                    st_essc(i), cap_ess_nodes(i), num_ess_nodes(i), s_cn);
            total_ess = total_ess + cap_ess_nodes(i);
            ess_installed = true;
        end
    end
    if ~ess_installed
        fprintf('  未安装储能\n');
    else
        fprintf('  总容量: %.2f MW\n', total_ess);
        fprintf('  储能时长: 4小时（假设）\n');
    end
    
    %% ========== 解码支路配置（2选1） ==========
    branch_types = solution(idx:idx+numBr-1);
    idx = idx + numBr;
    sop_cap_raw = solution(idx:idx+numBr-1);
    
    % 处理2选1逻辑
    xL = zeros(numBr, 1);
    cap_sop_nodes = zeros(numBr, 1);
    
    fprintf('\n支路配置（联络开关/SOP）:\n');
    mpc = case33bw();
    num_switches = 0;
    num_sops = 0;
    total_sop = 0;
    
    for i = 1:numBr
        br_idx = tieBranches(i);
        from_bus = mpc.branch(br_idx, 1);
        to_bus = mpc.branch(br_idx, 2);
        
        if branch_types(i) < 0.5
            fprintf('  支路%d (节点%d-%d): 常开\n', br_idx, from_bus, to_bus);
        elseif branch_types(i) < 1.5
            fprintf('  支路%d (节点%d-%d): 联络开关\n', br_idx, from_bus, to_bus);
            xL(i) = 1;
            num_switches = num_switches + 1;
        else
            num_sop = round(sop_cap_raw(i) * 1e3 / s_sop_min);
            cap_sop = num_sop * s_sop_min / 1e3;
            cap_sop_nodes(i) = cap_sop;
            if cap_sop > 0
                fprintf('  支路%d (节点%d-%d): SOP %.2f MVA (%d模块 × %d kVA/模块)\n', ...
                        br_idx, from_bus, to_bus, cap_sop, num_sop, s_sop_min);
                num_sops = num_sops + 1;
                total_sop = total_sop + cap_sop;
            else
                fprintf('  支路%d (节点%d-%d): 常开\n', br_idx, from_bus, to_bus);
            end
        end
    end
    
    fprintf('\n统计汇总:\n');
    fprintf('  联络开关: %d个\n', num_switches);
    fprintf('  SOP: %d个 (总容量%.2f MVA)\n', num_sops, total_sop);
    fprintf('  常开支路: %d条\n', numBr - num_switches - num_sops);
    
    %% ========== 投资估算 ==========
    global cpv cwind cP_ess cE_ess csop sc
    
    % 计算投资成本
    invest_pv = sum(num_pv_nodes) * s_pv * cpv / 1e4;  % 万元
    invest_wind = sum(num_wind_nodes) * s_wind * cwind / 1e4;
    invest_ess = sum(num_ess_nodes) * s_cn * (cP_ess + cE_ess * 4) / 1e4;  % 4小时储能
    invest_switch = num_switches * sc / 1e4;  % 使用sc参数（6万元/台）
    invest_sop = 0;
    for i = 1:numBr
       if cap_sop_nodes(i) > 0
        num_sop = round(cap_sop_nodes(i) * 1e3 / s_sop_min);
        % 取消SOP的一次性费用
        invest_sop = invest_sop + (num_sop * s_sop_min * csop) / 1e4;
       end
    end
    
    total_invest = invest_pv + invest_wind + invest_ess + invest_switch + invest_sop;
    
    fprintf('\n投资成本估算:\n');
    fprintf('  光伏: %.2f 万元\n', invest_pv);
    fprintf('  风电: %.2f 万元\n', invest_wind);
    fprintf('  储能: %.2f 万元\n', invest_ess);
    fprintf('  联络开关: %.2f 万元\n', invest_switch);
    fprintf('  SOP: %.2f 万元\n', invest_sop);
    fprintf('  总投资: %.2f 万元\n', total_invest);
    
    %% ========== 返回解码结果 ==========
    decoded = struct();
    decoded.pv = struct('nodes', st_pvc, 'caps', cap_pv_nodes, 'nums', num_pv_nodes, ...
                       'total_cap', total_pv);
    decoded.wind = struct('nodes', st_windc, 'caps', cap_wind_nodes, 'nums', num_wind_nodes, ...
                         'total_cap', total_wind);
    decoded.ess = struct('nodes', st_essc, 'caps', cap_ess_nodes, 'nums', num_ess_nodes, ...
                        'total_cap', total_ess);
    decoded.switches = xL;
    decoded.sop = struct('caps', cap_sop_nodes, 'total_cap', total_sop);
    decoded.branch_types = branch_types;
    decoded.investment = struct('pv', invest_pv, 'wind', invest_wind, 'ess', invest_ess, ...
                               'switch', invest_switch, 'sop', invest_sop, 'total', total_invest);
end

function [results] = analyze_seasonal_performance(solution)
% analyze_seasonal_performance - 分析四季运行性能
% 支持多点安装 + 联络开关/SOP 2选1方案

    global st_pvc st_windc st_essc numBr
    global s_pv s_wind s_cn s_sop_min
    
    %% ========== 解码solution ==========
    idx = 1;
    
    % 解码PV容量
    cap_pv_nodes = solution(idx:idx+length(st_pvc)-1);
    idx = idx + length(st_pvc);
    % 标准化到整数台数
    num_pv_nodes = round(cap_pv_nodes * 1e3 / s_pv);
    cap_pv_nodes = num_pv_nodes * s_pv / 1e3;
    
    % 解码Wind容量
    cap_wind_nodes = solution(idx:idx+length(st_windc)-1);
    idx = idx + length(st_windc);
    num_wind_nodes = round(cap_wind_nodes * 1e3 / s_wind);
    cap_wind_nodes = num_wind_nodes * s_wind / 1e3;
    
    % 解码ESS容量
    cap_ess_nodes = solution(idx:idx+length(st_essc)-1);
    idx = idx + length(st_essc);
    num_ess_nodes = round(cap_ess_nodes * 1e3 / s_cn);
    cap_ess_nodes = num_ess_nodes * s_cn / 1e3;
    
    % 解码支路配置（2选1）
    branch_types = solution(idx:idx+numBr-1);
    idx = idx + numBr;
    sop_cap_raw = solution(idx:idx+numBr-1);
    
    % 处理2选1逻辑
    xL = zeros(numBr, 1);
    cap_sop_nodes = zeros(numBr, 1);
    
    for i = 1:numBr
        if branch_types(i) < 0.5
            xL(i) = 0;
            cap_sop_nodes(i) = 0;
        elseif branch_types(i) < 1.5
            xL(i) = 1;
            cap_sop_nodes(i) = 0;
        else
            xL(i) = 0;
            num_sop = round(sop_cap_raw(i) * 1e3 / s_sop_min);
            cap_sop_nodes(i) = num_sop * s_sop_min / 1e3;
        end
    end
    
    %% ========== 构建upx ==========
    upx = [cap_pv_nodes, cap_wind_nodes, cap_ess_nodes, xL(:)', cap_sop_nodes(:)'];
    
    %% ========== 四季分析 ==========
    season_names = {'春季', '夏季', '秋季', '冬季'};
    results = zeros(4, 4); % [成本, 碳排放, kPR, kGR]
    
    fprintf('\n========== 四季运行性能分析 ==========\n');
    fprintf('季节\t成本(万元)\t碳排放(t)\tkPR\t\tkGR\n');
    fprintf('-----------------------------------------------\n');
    
    for s = 1:4
        % 切换到第s季
        updateSeason(s);
        
        % 运行下层优化
        [~, cost, carbon, kPR, kGR] = runLowerLayer(upx, 'GA');
        results(s, :) = [cost, carbon, kPR, kGR];
        
        fprintf('%s\t%.2f\t\t%.4f\t\t%.3f\t\t%.3f\n', ...
                season_names{s}, cost, carbon, kPR, kGR);
    end
    
    fprintf('-----------------------------------------------\n');
    
    %% ========== 计算年度指标 ==========
    % 季节权重（基于天数）
    season_days = [92, 92, 91, 90];  % 春夏秋冬天数（非闰年）
    season_weights = season_days / 365;
    
    % 年度加权平均
    annual_avg = season_weights * results;
    fprintf('年均\t%.2f\t\t%.4f\t\t%.3f\t\t%.3f\n', ...
            annual_avg(1), annual_avg(2), annual_avg(3), annual_avg(4));
    
    %% ========== 分析季节差异 ==========
    fprintf('\n季节性能差异分析:\n');
    
    % 成本差异
    [max_cost, max_cost_season] = max(results(:, 1));
    [min_cost, min_cost_season] = min(results(:, 1));
    fprintf('  成本: 最高在%s(%.2f万元), 最低在%s(%.2f万元), 差异%.1f%%\n', ...
            season_names{max_cost_season}, max_cost, ...
            season_names{min_cost_season}, min_cost, ...
            (max_cost - min_cost) / min_cost * 100);
    
    % 碳排放差异
    [max_carbon, max_carbon_season] = max(results(:, 2));
    [min_carbon, min_carbon_season] = min(results(:, 2));
    fprintf('  碳排放: 最高在%s(%.4ft), 最低在%s(%.4ft), 差异%.1f%%\n', ...
            season_names{max_carbon_season}, max_carbon, ...
            season_names{min_carbon_season}, min_carbon, ...
            (max_carbon - min_carbon) / min_carbon * 100);
    
    % 灵活性差异
    [min_kPR, min_kPR_season] = min(results(:, 3));
    [max_kPR, max_kPR_season] = max(results(:, 3));
    fprintf('  功率灵活性: 最低在%s(%.3f), 最高在%s(%.3f)\n', ...
            season_names{min_kPR_season}, min_kPR, ...
            season_names{max_kPR_season}, max_kPR);
    
    %% ========== 计算全年总量 ==========
    fprintf('\n年度总量估算:\n');
    annual_cost = sum(results(:, 1) .* season_days(:));  % 万元/年
    annual_carbon = sum(results(:, 2) .* season_days(:));  % t CO2/年
    fprintf('  年度运行成本: %.2f 万元\n', annual_cost);
    fprintf('  年度碳排放: %.2f t CO2\n', annual_carbon);
    
    % 加上投资成本年化值
    global r life_PV life_WT life_ESS life_SOP
    if exist('r', 'var') && ~isempty(r)
        % 计算年化投资成本
        [decoded] = decode_and_display_solution(solution);
        CRF = r * (1+r)^20 / ((1+r)^20 - 1);  % 假设统一20年寿命
        annual_invest = decoded.investment.total * CRF;
        fprintf('  年化投资成本: %.2f 万元\n', annual_invest);
        fprintf('  年度总成本: %.2f 万元\n', annual_cost + annual_invest);
    end
    
    %% ========== 资源利用率分析 ==========
    fprintf('\n资源利用分析:\n');
    
    % DG总容量
    total_pv = sum(cap_pv_nodes);
    total_wind = sum(cap_wind_nodes);
    total_ess = sum(cap_ess_nodes);
    
    if total_pv > 0 || total_wind > 0
        fprintf('  DG装机容量: PV=%.2fMW, Wind=%.2fMW\n', total_pv, total_wind);
        
        % 估算容量因子（基于碳排放反推）
        % 假设总负荷和DG出力的关系
        base_carbon = 30;  % 假设无DG时的基准碳排放 t/日
        carbon_reduction = (base_carbon - annual_avg(2)) / base_carbon * 100;
        fprintf('  碳减排效果: %.1f%%\n', carbon_reduction);
    end
    
  % 网架利用␊␊
    effective_branches = sum(xL==1 & cap_sop_nodes==0) + sum(cap_sop_nodes > 0);
    fprintf('  网架利用: %d/%d条支路启用 (%.0f%%)\n', ...
            effective_branches, numBr, effective_branches/numBr*100);
end

function plot_seasonal_performance_improved(seasonal_results)
% 改进的季节性能绘图（双Y轴）
    
    season_names = {'春', '夏', '秋', '冬'};
    
    % 创建双Y轴图
    yyaxis left
    bar(seasonal_results(:, 1), 'FaceColor', [0.2, 0.4, 0.8]);
    ylabel('运行成本 (万元)');
    ylim([0, max(seasonal_results(:, 1)) * 1.2]);
    
    yyaxis right
    hold on;
    bar_width = 0.3;
    x_pos = 1:4;
    bar(x_pos - bar_width/2, seasonal_results(:, 2), bar_width, ...
        'FaceColor', [0.8, 0.2, 0.2]);
    ylabel('碳排放 (t CO_2)');
    ylim([0, max(seasonal_results(:, 2)) * 1.5]);
    
    % 设置x轴
    set(gca, 'XTick', 1:4);
    set(gca, 'XTickLabel', season_names);
    xlabel('季节');
    title('四季运行指标对比');
    
    % 添加数值标签
    for i = 1:4
        % 成本标签
        text(i, seasonal_results(i,1)/2, sprintf('%.1f', seasonal_results(i,1)), ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
    end
    
    % 添加图例
    legend('运行成本', '碳排放', 'Location', 'northwest');
    grid on;
end

function generate_detailed_report(solution, decoded, seasonal_results, ...
                                 paretoSet, elapsed_time, timestamp)
% 生成详细的文本报告
    
    filename = sprintf('optimization_report_%s.txt', timestamp);
    fid = fopen(filename, 'w');
    
    fprintf(fid, '主动配电网源网储多元协调规划优化报告\n');
    fprintf(fid, '=====================================\n');
    fprintf(fid, '生成时间: %s\n', datestr(now));
    fprintf(fid, '优化耗时: %.2f小时\n', elapsed_time/3600);
    
    fprintf(fid, '\n========== 最优规划方案 ==========\n');
    
    % 光伏配置
    fprintf(fid, '光伏配置:\n');
    if isfield(decoded.pv, 'nodes') && isfield(decoded.pv, 'caps')
        for i = 1:length(decoded.pv.nodes)
            if decoded.pv.caps(i) > 0
                fprintf(fid, '  节点%d: %.2f MW (%d台 × 140 kW/台)\n', ...
                        decoded.pv.nodes(i), decoded.pv.caps(i), decoded.pv.nums(i));
            end
        end
        fprintf(fid, '  总容量: %.2f MW\n', decoded.pv.total_cap);
    end
    
    % 风电配置
    fprintf(fid, '\n风电配置:\n');
    if isfield(decoded.wind, 'nodes') && isfield(decoded.wind, 'caps')
        for i = 1:length(decoded.wind.nodes)
            if decoded.wind.caps(i) > 0
                fprintf(fid, '  节点%d: %.2f MW (%d台 × 180 kW/台)\n', ...
                        decoded.wind.nodes(i), decoded.wind.caps(i), decoded.wind.nums(i));
            end
        end
        fprintf(fid, '  总容量: %.2f MW\n', decoded.wind.total_cap);
    end
    
    % 储能配置
    fprintf(fid, '\n储能配置:\n');
    if isfield(decoded.ess, 'nodes') && isfield(decoded.ess, 'caps')
        for i = 1:length(decoded.ess.nodes)
            if decoded.ess.caps(i) > 0
                fprintf(fid, '  节点%d: %.2f MW (%d台 × 100 kW/台)\n', ...
                        decoded.ess.nodes(i), decoded.ess.caps(i), decoded.ess.nums(i));
            end
        end
        fprintf(fid, '  总容量: %.2f MW\n', decoded.ess.total_cap);
    end
    
    fprintf(fid, '\n联络开关配置:\n');
    fprintf(fid, '  开关状态: %s\n', mat2str(decoded.switches));
    fprintf(fid, '  闭合数量: %d / %d\n', sum(decoded.switches), length(decoded.switches));
    
    fprintf(fid, '\n========== 四季运行性能 ==========\n');
    season_names = {'春季', '夏季', '秋季', '冬季'};
    fprintf(fid, '季节\t成本(万元)\t碳排放(t)\tkPR\tkGR\n');
    for s = 1:4
        fprintf(fid, '%s\t%.2f\t\t%.4f\t\t%.3f\t%.3f\n', ...
                season_names{s}, seasonal_results(s,1), seasonal_results(s,2), ...
                seasonal_results(s,3), seasonal_results(s,4));
    end
    
    % 年度平均
    season_weights = [92, 92, 91, 90] / 365;
    annual_avg = season_weights * seasonal_results;
    fprintf(fid, '年均\t%.2f\t\t%.4f\t\t%.3f\t%.3f\n', ...
            annual_avg(1), annual_avg(2), annual_avg(3), annual_avg(4));
    
    fprintf(fid, '\n========== Pareto前沿分析 ==========\n');
    fprintf(fid, 'Pareto前沿解数量: %d\n', size(paretoSet, 1));
    
    % 投资成本总结
    if isfield(decoded, 'investment')
        fprintf(fid, '\n========== 投资成本汇总 ==========\n');
        fprintf(fid, '光伏投资: %.2f 万元\n', decoded.investment.pv);
        fprintf(fid, '风电投资: %.2f 万元\n', decoded.investment.wind);
        fprintf(fid, '储能投资: %.2f 万元\n', decoded.investment.ess);
        fprintf(fid, '联络开关投资: %.2f 万元\n', decoded.investment.switch);
        fprintf(fid, 'SOP投资: %.2f 万元\n', decoded.investment.sop);
        fprintf(fid, '总投资: %.2f 万元\n', decoded.investment.total);
    end
    
    fclose(fid);
    fprintf('详细报告已生成: %s\n', filename);
end

function analyze_pareto_front(paretoSet, best_solution)
% 分析Pareto前沿
    
    global VarMin
    n_vars = length(VarMin);
    objectives = paretoSet(:, n_vars+1:end);
    
    fprintf('Pareto前沿统计:\n');
    fprintf('  成本范围: [%.2f, %.2f] 万元\n', ...
            min(objectives(:,1)), max(objectives(:,1)));
    fprintf('  碳排放范围: [%.4f, %.4f] t\n', ...
            min(objectives(:,2)), max(objectives(:,2)));
    fprintf('  灵活性范围: [%.3f, %.3f]\n', ...
            min(objectives(:,3)), max(objectives(:,3)));
    
    % 找出折衷解
    % 归一化目标值
    obj_norm = zeros(size(objectives));
    for i = 1:size(objectives, 2)
        min_val = min(objectives(:,i));
        max_val = max(objectives(:,i));
        if max_val > min_val
            if i == 3  % 灵活性是最大化目标
                obj_norm(:,i) = (objectives(:,i) - min_val) / (max_val - min_val);
            else  % 成本和碳排放是最小化目标
                obj_norm(:,i) = (max_val - objectives(:,i)) / (max_val - min_val);
            end
        else
            obj_norm(:,i) = 1;
        end
    end
    
    % 计算每个解到理想点的距离
    ideal_point = ones(1, size(obj_norm, 2));
    distances = sqrt(sum((obj_norm - ideal_point).^2, 2));
    [~, best_idx] = min(distances);
    
    fprintf('\n折衷最优解:\n');
    fprintf('  成本: %.2f 万元\n', objectives(best_idx, 1));
    fprintf('  碳排放: %.4f t\n', objectives(best_idx, 2));
    fprintf('  灵活性: %.3f\n', objectives(best_idx, 3));
end

function plot_pareto_front_3d_soft(paretoSet, best_solution)
% 使用柔和配色的3D Pareto前沿图

    global VarMin
    n_vars = length(VarMin);
    objectives = paretoSet(:, n_vars+1:end);
    
    % 定义柔和的渐变色
    n_points = size(objectives, 1);
    colors_grad = [linspace(0.4, 0.8, n_points)', ...
                   linspace(0.6, 0.7, n_points)', ...
                   linspace(0.8, 0.4, n_points)'];
    
    % 创建3D散点图
    scatter3(objectives(:,1), objectives(:,2), objectives(:,3), ...
             80, colors_grad, 'filled', ...
             'MarkerEdgeColor', [0.3, 0.3, 0.3], ...
             'LineWidth', 0.5);
    
    % 标记TOPSIS选择的最优解
    [~, best_idx] = ismember(best_solution(1:n_vars), paretoSet(:,1:n_vars), 'rows');
    if best_idx > 0
        hold on;
        scatter3(objectives(best_idx,1), objectives(best_idx,2), ...
                 objectives(best_idx,3), 300, [0.9, 0.3, 0.3], ...
                 'pentagram', 'filled', ...
                 'MarkerEdgeColor', [0.2, 0.2, 0.2], 'LineWidth', 2);
        
        % 添加标注
        text(objectives(best_idx,1), objectives(best_idx,2), ...
             objectives(best_idx,3) + 0.05, ...
             '  最优解', 'FontSize', 12, 'FontWeight', 'bold');
    end
    
    % 设置坐标轴
    xlabel('经济成本 (万元)', 'FontSize', 12);
    ylabel('碳排放 (t CO_2)', 'FontSize', 12);
    zlabel('灵活性指标', 'FontSize', 12);
    title('Pareto前沿三维可视化', 'FontSize', 14);
    
    % 设置网格和视角
    grid on;
    box on;
    view(45, 30);
    set(gca, 'GridAlpha', 0.3);
    
    % 使用柔和的背景色
    set(gcf, 'Color', [0.98, 0.98, 0.98]);
    set(gca, 'Color', [1, 1, 1]);
end
