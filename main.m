function main()
% main - Active Distribution Network Source-Grid-Storage Multi-element Coordination Planning
% Modified version with English figures and 7cm width

%% ========== 1. Environment Cleanup and Initialization ==========
fprintf('\n========== Active Distribution Network Planning Optimization ==========\n');
fprintf('Start time: %s\n', datestr(now));

clear global;
close all;
clc;

%% ========== 2. Parameter Settings ==========
fprintf('\nInitializing system parameters...\n');

% ---------- Run Mode Selection ----------
%RUN_MODE = 'NORMAL';  % Change to NORMAL for better optimization results
RUN_MODE = 'QUICK';   % Quick test mode
% Initialize parameters
parameter();
% ---------- Algorithm Parameter Settings ----------
global HS_MAXITERS HS_HMS HS_HMCR HS_PAR_MIN HS_PAR_MAX
global GA_MAXGEN GA_POPSIZE
global VERBOSE_SEASON

switch RUN_MODE
    case 'QUICK'
        HS_MAXITERS = 5;    % Increased to 50
        HS_HMS = 5;         
        GA_MAXGEN = 5;      
        GA_POPSIZE = 5;     
        fprintf('Run mode: Quick test\n');
        
    case 'NORMAL'
        HS_MAXITERS = 150;   
        HS_HMS = 15;         
        GA_MAXGEN = 40;      
        GA_POPSIZE = 40;     
        fprintf('Run mode: Normal run\n');
        
    case 'HIGH_QUALITY'
        HS_MAXITERS = 400;   
        HS_HMS = 15;         
        GA_MAXGEN = 40;      
        GA_POPSIZE = 50;     
        fprintf('Run mode: High quality optimization\n');
end

% ---------- Other Parameters ----------
HS_HMCR = 0.9;           
HS_PAR_MIN = 0.35;       
HS_PAR_MAX = 0.9;        
VERBOSE_SEASON = true;   % Enable seasonal detailed output

% ---------- Parallel Computing Setup ----------
if license('test', 'Distrib_Computing_Toolbox')
    if isempty(gcp('nocreate'))
        fprintf('Starting parallel computing...\n');
        parpool('local', min(4, feature('numcores')));
    end
end

%% ========== 3. Data Preparation ==========
fprintf('\nPreparing data...\n');

% Check and generate typical day data
if ~exist('pv_typical.mat', 'file') || ~exist('wd_typical.mat', 'file')
    fprintf('Generating typical day data...\n');
    makeTypicalDays();
else
    fprintf('Loading existing typical day data...\n');
end

% Load typical day data
loadTypicalData();

% Display data information
global K T numBr
fprintf('Typical day scenarios: K=%d\n', K);
fprintf('Time periods: T=%d\n', T);
fprintf('Tie switches: %d\n', numBr);

%% ========== 4. Run Optimization ==========
fprintf('\n========== Starting Optimization ==========\n');

% Record start time
tic_main = tic;

% Store GA convergence history
global GA_CONVERGENCE_HISTORY
GA_CONVERGENCE_HISTORY = [];

% ---------- Run Main Optimization ----------
try
    fprintf('Running Harmony Search Algorithm (with TOPSIS)...\n');
    fprintf('Estimated run time: ');
    switch RUN_MODE
        case 'QUICK'
            fprintf('0.5-1 hours\n');
        case 'NORMAL'
            fprintf('4-8 hours\n');
        case 'HIGH_QUALITY'
            fprintf('12-24 hours\n');
    end
    
    % Call optimization function
    [best_solution, bestFitHistory, paretoSet] = HScore_TOPSIS();
    
    % Record end time
    elapsed_time = toc(tic_main);
    fprintf('\nOptimization completed! Total time: %.2f hours\n', elapsed_time/3600);
    
catch ME
    fprintf('\n✗ Optimization error: %s\n', ME.message);
    fprintf('Error location:\n');
    for i = 1:min(5, length(ME.stack))
        fprintf('  %s (line %d)\n', ME.stack(i).name, ME.stack(i).line);
    end
    return;
end

%% ========== 5. Results Analysis ==========
fprintf('\n========== Results Analysis ==========\n');

% 5.1 Display and store optimal solution
fprintf('\n--- Optimal Planning Solution ---\n');
[decoded_solution] = decode_and_display_solution(best_solution);

% 5.2 Four-season performance analysis
fprintf('\n--- Seasonal Performance Analysis ---\n');
[seasonal_results] = analyze_seasonal_performance(best_solution);

% 5.3 Pareto front analysis
if size(paretoSet, 1) > 1
    fprintf('\n--- Pareto Front Analysis ---\n');
    fprintf('Number of Pareto solutions: %d\n', size(paretoSet, 1));
    analyze_pareto_front(paretoSet, best_solution);
end

%% ========== 6. Results Visualization ==========
fprintf('\nGenerating visualization charts...\n');

% Define soft color scheme
colors = struct();
colors.hs = [0.4, 0.6, 0.8];        % Soft blue
colors.ga = [0.8, 0.6, 0.4];        % Soft orange
colors.spring = [0.6, 0.8, 0.4];    % Soft green
colors.summer = [0.9, 0.7, 0.3];    % Soft yellow
colors.autumn = [0.8, 0.5, 0.3];    % Soft brown
colors.winter = [0.5, 0.6, 0.7];    % Soft gray-blue
colors.cost = [0.7, 0.7, 0.9];      % Light purple
colors.carbon = [0.9, 0.7, 0.7];    % Light red
colors.flexibility = [0.7, 0.9, 0.7]; % Light green

%% Figure size settings (7cm width)
cm_to_inch = 1/2.54;
dpi = 96;
fig_width_cm = 7;
fig_width_pixels = fig_width_cm * cm_to_inch * dpi;
fig_height_pixels = fig_width_pixels * 1.2;  % Taller for subplots

%% 6.1 Convergence curves (HS and GA stacked)
figure('Name', 'Optimization Algorithm Convergence', ...
       'Position', [100, 100, fig_width_pixels, fig_height_pixels], ...
       'PaperUnits', 'centimeters', ...
       'PaperSize', [fig_width_cm, fig_width_cm*1.2], ...
       'PaperPosition', [0, 0, fig_width_cm, fig_width_cm*1.2]);

% Prepare data
iterations_hs = 1:length(bestFitHistory);
has_ga_data = ~isempty(GA_CONVERGENCE_HISTORY);

% Subplot 1: Harmony Search convergence
subplot(2,1,1);
plot(iterations_hs, bestFitHistory, '-', 'LineWidth', 2, 'Color', colors.hs);
xlabel('Iterations', 'FontSize', 8);
ylabel('Objective Value', 'FontSize', 8);
title('Harmony Search (HS) Convergence', 'FontSize', 9, 'FontWeight', 'bold');
grid on;
box on;
set(gca, 'GridAlpha', 0.3, 'FontSize', 7);

% Add HS convergence info (commented out for cleaner plot)
% hs_improve = (bestFitHistory(1)-bestFitHistory(end))/bestFitHistory(1)*100;
% text_str = sprintf('Initial: %.4f\nFinal: %.4f\nImprovement: %.2f%%', ...
%     bestFitHistory(1), bestFitHistory(end), hs_improve);
% text(0.02, 0.98, text_str, 'Units', 'normalized', ...
%      'VerticalAlignment', 'top', 'FontSize', 6, ...
%      'BackgroundColor', [1, 1, 1, 0.8], 'EdgeColor', 'none');

% Mark optimal value point
[min_val, min_idx] = min(bestFitHistory);
hold on;
plot(min_idx, min_val, 'o', 'MarkerSize', 5, ...
     'MarkerFaceColor', colors.hs*0.8, 'MarkerEdgeColor', colors.hs*0.6);

% Subplot 2: Genetic Algorithm convergence
subplot(2,1,2);
if has_ga_data
    iterations_ga = 1:length(GA_CONVERGENCE_HISTORY);
    plot(iterations_ga, GA_CONVERGENCE_HISTORY, '-', 'LineWidth', 2, 'Color', colors.ga);
    xlabel('Iterations', 'FontSize', 8);
    ylabel('Fitness Value', 'FontSize', 8);
    title('Genetic Algorithm (GA) Convergence', 'FontSize', 9, 'FontWeight', 'bold');
    grid on;
    box on;
    set(gca, 'GridAlpha', 0.3, 'FontSize', 7);
    
    % Add GA convergence info (commented out for cleaner plot)
    % ga_improve = (GA_CONVERGENCE_HISTORY(1)-GA_CONVERGENCE_HISTORY(end))/GA_CONVERGENCE_HISTORY(1)*100;
    % text_str = sprintf('Initial: %.4f\nFinal: %.4f\nImprovement: %.2f%%', ...
    %     GA_CONVERGENCE_HISTORY(1), GA_CONVERGENCE_HISTORY(end), ga_improve);
    % text(0.02, 0.98, text_str, 'Units', 'normalized', ...
    %      'VerticalAlignment', 'top', 'FontSize', 6, ...
    %      'BackgroundColor', [1, 1, 1, 0.8], 'EdgeColor', 'none');
    
    % Mark optimal value point
    [min_val_ga, min_idx_ga] = min(GA_CONVERGENCE_HISTORY);
    hold on;
    plot(min_idx_ga, min_val_ga, 'o', 'MarkerSize', 5, ...
         'MarkerFaceColor', colors.ga*0.8, 'MarkerEdgeColor', colors.ga*0.6);
else
    % No GA data
    text(0.5, 0.5, 'No GA convergence data', ...
         'HorizontalAlignment', 'center', ...
         'VerticalAlignment', 'middle', ...
         'FontSize', 10, 'Color', [0.5, 0.5, 0.5]);
    title('Genetic Algorithm (GA) Convergence', 'FontSize', 9, 'FontWeight', 'bold');
    grid on;
    box on;
    set(gca, 'GridAlpha', 0.3, 'FontSize', 7);
    xlabel('Iterations', 'FontSize', 8);
    ylabel('Fitness Value', 'FontSize', 8);
end

% Adjust subplot spacing
set(gcf, 'Position', [100, 100, fig_width_pixels, fig_height_pixels]);

%% 6.2 Seasonal performance comparison (bar charts)
fig_height_pixels2 = fig_width_pixels * 1.0;  % Square for two subplots
figure('Name', 'Seasonal Performance Comparison', ...
       'Position', [150 + fig_width_pixels, 100, fig_width_pixels, fig_height_pixels2], ...
       'PaperUnits', 'centimeters', ...
       'PaperSize', [fig_width_cm, fig_width_cm], ...
       'PaperPosition', [0, 0, fig_width_cm, fig_width_cm]);

season_names = {'Spr', 'Sum', 'Aut', 'Win'};  % Shortened for small figure
x_pos = 1:4;

% Prepare data
cost_data = seasonal_results(:, 1);
carbon_data = seasonal_results(:, 2);
kPR_data = seasonal_results(:, 3);
kGR_data = seasonal_results(:, 4);

% Subplot 1: Cost and carbon emissions
subplot(2,1,1);
hold on;

% Bar width
bar_width = 0.35;

% Cost bars
b1 = bar(x_pos - bar_width/2, cost_data, bar_width, ...
         'FaceColor', colors.cost, 'EdgeColor', 'none');

% Carbon emissions (dual Y-axis)
yyaxis right;
b2 = bar(x_pos + bar_width/2, carbon_data, bar_width, ...
         'FaceColor', colors.carbon, 'EdgeColor', 'none');

% Set axes
yyaxis left;
ylabel('Cost (10^4 CNY/day)', 'FontSize', 7);
ylim([0, max(cost_data) * 1.2]);
ax = gca;
ax.YAxis(1).Color = colors.cost * 0.8;

yyaxis right;
ylabel('Carbon (t CO_2/day)', 'FontSize', 7);
ylim([0, max(carbon_data) * 1.2]);
ax.YAxis(2).Color = colors.carbon * 0.8;

% Set x-axis
set(gca, 'XTick', x_pos);
set(gca, 'XTickLabel', season_names, 'FontSize', 7);
xlabel('Season', 'FontSize', 8);
title('Economic and Environmental Indicators', 'FontSize', 9);

% Add value labels
for i = 1:4
    % Cost labels
    text(x_pos(i) - bar_width/2, cost_data(i) + max(cost_data)*0.02, ...
         sprintf('%.1f', cost_data(i)), ...
         'HorizontalAlignment', 'center', 'FontSize', 6);
    % Carbon labels
    text(x_pos(i) + bar_width/2, carbon_data(i) + max(carbon_data)*0.02, ...
         sprintf('%.2f', carbon_data(i)), ...
         'HorizontalAlignment', 'center', 'FontSize', 6);
end

legend({'Cost', 'Carbon'}, 'Location', 'northwest', 'FontSize', 6, 'Box', 'off');
grid on;
set(gca, 'GridAlpha', 0.3);

% Subplot 2: Flexibility indicators
subplot(2,1,2);
hold on;

% Power flexibility
b3 = bar(x_pos - bar_width/2, kPR_data, bar_width, ...
         'FaceColor', colors.flexibility, 'EdgeColor', 'none');

% Grid flexibility
b4 = bar(x_pos + bar_width/2, kGR_data, bar_width, ...
         'FaceColor', colors.flexibility * 0.8, 'EdgeColor', 'none');

% Set axes
ylabel('Flexibility Index', 'FontSize', 7);
ylim([0, 1.2]);
set(gca, 'XTick', x_pos);
set(gca, 'XTickLabel', season_names, 'FontSize', 7);
xlabel('Season', 'FontSize', 8);
title('Flexibility Indicators', 'FontSize', 9);

% Add value labels
for i = 1:4
    text(x_pos(i) - bar_width/2, kPR_data(i) + 0.02, ...
         sprintf('%.3f', kPR_data(i)), ...
         'HorizontalAlignment', 'center', 'FontSize', 6);
    text(x_pos(i) + bar_width/2, kGR_data(i) + 0.02, ...
         sprintf('%.3f', kGR_data(i)), ...
         'HorizontalAlignment', 'center', 'FontSize', 6);
end

legend({'Power Flexibility (k_{PR})', 'Grid Flexibility (k_{GR})'}, ...
       'Location', 'best', 'FontSize', 6, 'Box', 'off');
grid on;
set(gca, 'GridAlpha', 0.3);

%% 6.3 If Pareto front exists, plot 3D (with soft colors)
if size(paretoSet, 1) > 3
    fig_3d_width = fig_width_cm * 1.5;  % Wider for 3D
    fig_3d_pixels = fig_3d_width * cm_to_inch * dpi;
    figure('Name', 'Pareto Front', ...
           'Position', [100, 400, fig_3d_pixels, fig_3d_pixels*0.8], ...
           'PaperUnits', 'centimeters', ...
           'PaperSize', [fig_3d_width, fig_3d_width*0.8], ...
           'PaperPosition', [0, 0, fig_3d_width, fig_3d_width*0.8]);
    plot_pareto_front_3d_soft(paretoSet, best_solution);
end

%% Save figures option
response = input('\nSave all figures as images? (y/n) [n]: ', 's');
if strcmpi(response, 'y')
    % Save convergence figure
    figure(1);
    print('convergence_curves_7cm.png', '-dpng', '-r300');
    print('convergence_curves_7cm.eps', '-depsc2');
    
    % Save seasonal performance figure
    figure(2);
    print('seasonal_performance_7cm.png', '-dpng', '-r300');
    print('seasonal_performance_7cm.eps', '-depsc2');
    
    % Save Pareto front if exists
    if size(paretoSet, 1) > 3
        figure(3);
        print('pareto_front_3d.png', '-dpng', '-r300');
        print('pareto_front_3d.eps', '-depsc2');
    end
    
    fprintf('Figures saved as PNG and EPS formats.\n');
end

%% ========== 7. Save Results ==========
fprintf('\nSaving optimization results...\n');

% Generate timestamp
timestamp = datestr(now, 'yyyymmdd_HHMMSS');

% Save results
save_filename = sprintf('optimization_result_%s_%s.mat', RUN_MODE, timestamp);
save(save_filename, 'best_solution', 'bestFitHistory', 'paretoSet', ...
     'elapsed_time', 'RUN_MODE', 'decoded_solution', 'seasonal_results', ...
     'GA_CONVERGENCE_HISTORY');

fprintf('Results saved to: %s\n', save_filename);

% Generate detailed report
generate_detailed_report(best_solution, decoded_solution, seasonal_results, ...
                        paretoSet, elapsed_time, timestamp);

fprintf('\n========== Optimization Completed ==========\n');
fprintf('End time: %s\n', datestr(now));

end

%% ========== Helper Functions ==========
function [decoded] = decode_and_display_solution(solution)
% decode_and_display_solution - Decode and display optimization solution
% Support multi-point installation + tie switch/SOP either-or scheme

    global st_pvc st_windc st_essc tieBranches numBr
    global s_pv s_wind s_cn s_sop_min
    
    idx = 1;
    
    %% ========== Decode PV (multi-point) ==========
    cap_pv_nodes = solution(idx:idx+length(st_pvc)-1);
    idx = idx + length(st_pvc);
    num_pv_nodes = round(cap_pv_nodes * 1e3 / s_pv);
    
    fprintf('\n========== Optimal Planning Solution ==========\n');
    fprintf('PV Configuration:\n');
    total_pv = 0;
    pv_installed = false;
    for i = 1:length(st_pvc)
        if num_pv_nodes(i) > 0
            fprintf('  Bus %d: %.2f MW (%d units × %d kW/unit)\n', ...
                    st_pvc(i), cap_pv_nodes(i), num_pv_nodes(i), s_pv);
            total_pv = total_pv + cap_pv_nodes(i);
            pv_installed = true;
        end
    end
    if ~pv_installed
        fprintf('  No PV installed\n');
    else
        fprintf('  Total capacity: %.2f MW\n', total_pv);
    end
    
    %% ========== Decode Wind (multi-point) ==========
    cap_wind_nodes = solution(idx:idx+length(st_windc)-1);
    idx = idx + length(st_windc);
    num_wind_nodes = round(cap_wind_nodes * 1e3 / s_wind);
    
    fprintf('\nWind Configuration:\n');
    total_wind = 0;
    wind_installed = false;
    for i = 1:length(st_windc)
        if num_wind_nodes(i) > 0
            fprintf('  Bus %d: %.2f MW (%d units × %d kW/unit)\n', ...
                    st_windc(i), cap_wind_nodes(i), num_wind_nodes(i), s_wind);
            total_wind = total_wind + cap_wind_nodes(i);
            wind_installed = true;
        end
    end
    if ~wind_installed
        fprintf('  No wind power installed\n');
    else
        fprintf('  Total capacity: %.2f MW\n', total_wind);
    end
    
    %% ========== Decode ESS (multi-point) ==========
    cap_ess_nodes = solution(idx:idx+length(st_essc)-1);
    idx = idx + length(st_essc);
    num_ess_nodes = round(cap_ess_nodes * 1e3 / s_cn);
    
    fprintf('\nESS Configuration:\n');
    total_ess = 0;
    ess_installed = false;
    for i = 1:length(st_essc)
        if num_ess_nodes(i) > 0
            fprintf('  Bus %d: %.2f MW (%d units × %d kW/unit)\n', ...
                    st_essc(i), cap_ess_nodes(i), num_ess_nodes(i), s_cn);
            total_ess = total_ess + cap_ess_nodes(i);
            ess_installed = true;
        end
    end
    if ~ess_installed
        fprintf('  No ESS installed\n');
    else
        fprintf('  Total capacity: %.2f MW\n', total_ess);
        fprintf('  Storage duration: 4 hours (assumed)\n');
    end
    
    %% ========== Decode branch configuration (either-or) ==========
    branch_types = solution(idx:idx+numBr-1);
    idx = idx + numBr;
    sop_cap_raw = solution(idx:idx+numBr-1);
    
    % Process either-or logic
    xL = zeros(numBr, 1);
    cap_sop_nodes = zeros(numBr, 1);
    
    fprintf('\nBranch Configuration (Tie Switch/SOP):\n');
    mpc = case33bw();
    num_switches = 0;
    num_sops = 0;
    total_sop = 0;
    
    for i = 1:numBr
        br_idx = tieBranches(i);
        from_bus = mpc.branch(br_idx, 1);
        to_bus = mpc.branch(br_idx, 2);
        
        if branch_types(i) < 0.5
            fprintf('  Branch %d (Bus %d-%d): Open\n', br_idx, from_bus, to_bus);
        elseif branch_types(i) < 1.5
            fprintf('  Branch %d (Bus %d-%d): Tie Switch\n', br_idx, from_bus, to_bus);
            xL(i) = 1;
            num_switches = num_switches + 1;
        else
            num_sop = round(sop_cap_raw(i) * 1e3 / s_sop_min);
            cap_sop = num_sop * s_sop_min / 1e3;
            cap_sop_nodes(i) = cap_sop;
            if cap_sop > 0
                fprintf('  Branch %d (Bus %d-%d): SOP %.2f MVA (%d modules × %d kVA/module)\n', ...
                        br_idx, from_bus, to_bus, cap_sop, num_sop, s_sop_min);
                num_sops = num_sops + 1;
                total_sop = total_sop + cap_sop;
            else
                fprintf('  Branch %d (Bus %d-%d): Open\n', br_idx, from_bus, to_bus);
            end
        end
    end
    
    fprintf('\nSummary:\n');
    fprintf('  Tie switches: %d\n', num_switches);
    fprintf('  SOPs: %d (Total capacity: %.2f MVA)\n', num_sops, total_sop);
    fprintf('  Open branches: %d\n', numBr - num_switches - num_sops);
    
    %% ========== Investment estimation ==========
    global cpv cwind cP_ess cE_ess csop sc
    
    % Calculate investment costs
    invest_pv = sum(num_pv_nodes) * s_pv * cpv / 1e4;  % 10k CNY
    invest_wind = sum(num_wind_nodes) * s_wind * cwind / 1e4;
    invest_ess = sum(num_ess_nodes) * s_cn * (cP_ess + cE_ess * 4) / 1e4;  % 4-hour storage
    invest_switch = num_switches * sc / 1e4;  % Use sc parameter
    invest_sop = 0;
    for i = 1:numBr
       if cap_sop_nodes(i) > 0
        num_sop = round(cap_sop_nodes(i) * 1e3 / s_sop_min);
        invest_sop = invest_sop + (num_sop * s_sop_min * csop) / 1e4;
       end
    end
    
    total_invest = invest_pv + invest_wind + invest_ess + invest_switch + invest_sop;
    
    fprintf('\nInvestment Cost Estimation:\n');
    fprintf('  PV: %.2f ×10^4 CNY\n', invest_pv);
    fprintf('  Wind: %.2f ×10^4 CNY\n', invest_wind);
    fprintf('  ESS: %.2f ×10^4 CNY\n', invest_ess);
    fprintf('  Tie switches: %.2f ×10^4 CNY\n', invest_switch);
    fprintf('  SOP: %.2f ×10^4 CNY\n', invest_sop);
    fprintf('  Total investment: %.2f ×10^4 CNY\n', total_invest);
    
    %% ========== Return decoded results ==========
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
% analyze_seasonal_performance - Analyze four-season operation performance

    global st_pvc st_windc st_essc numBr
    global s_pv s_wind s_cn s_sop_min
    
    %% ========== Decode solution ==========
    idx = 1;
    
    % Decode PV capacity
    cap_pv_nodes = solution(idx:idx+length(st_pvc)-1);
    idx = idx + length(st_pvc);
    % Standardize to integer units
    num_pv_nodes = round(cap_pv_nodes * 1e3 / s_pv);
    cap_pv_nodes = num_pv_nodes * s_pv / 1e3;
    
    % Decode Wind capacity
    cap_wind_nodes = solution(idx:idx+length(st_windc)-1);
    idx = idx + length(st_windc);
    num_wind_nodes = round(cap_wind_nodes * 1e3 / s_wind);
    cap_wind_nodes = num_wind_nodes * s_wind / 1e3;
    
    % Decode ESS capacity
    cap_ess_nodes = solution(idx:idx+length(st_essc)-1);
    idx = idx + length(st_essc);
    num_ess_nodes = round(cap_ess_nodes * 1e3 / s_cn);
    cap_ess_nodes = num_ess_nodes * s_cn / 1e3;
    
    % Decode branch configuration (either-or)
    branch_types = solution(idx:idx+numBr-1);
    idx = idx + numBr;
    sop_cap_raw = solution(idx:idx+numBr-1);
    
    % Process either-or logic
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
    
    %% ========== Build upx ==========
    upx = [cap_pv_nodes, cap_wind_nodes, cap_ess_nodes, xL(:)', cap_sop_nodes(:)'];
    
    %% ========== Four-season analysis ==========
    season_names = {'Spring', 'Summer', 'Autumn', 'Winter'};
    results = zeros(4, 4); % [cost, carbon, kPR, kGR]
    
    fprintf('\n========== Seasonal Performance Analysis ==========\n');
    fprintf('Season\tCost(10^4CNY)\tCarbon(t)\tkPR\t\tkGR\n');
    fprintf('-----------------------------------------------\n');
    
    for s = 1:4
        % Switch to season s
        updateSeason(s);
        
        % Run lower layer optimization
        [~, cost, carbon, kPR, kGR] = runLowerLayer(upx, 'GA');
        results(s, :) = [cost, carbon, kPR, kGR];
        
        fprintf('%s\t%.2f\t\t%.4f\t\t%.3f\t\t%.3f\n', ...
                season_names{s}, cost, carbon, kPR, kGR);
    end
    
    fprintf('-----------------------------------------------\n');
    
    %% ========== Calculate annual indicators ==========
    % Season weights (based on days)
    season_days = [92, 92, 91, 90];  % Spring, summer, autumn, winter (non-leap year)
    season_weights = season_days / 365;
    
    % Annual weighted average
    annual_avg = season_weights * results;
    fprintf('Annual\t%.2f\t\t%.4f\t\t%.3f\t\t%.3f\n', ...
            annual_avg(1), annual_avg(2), annual_avg(3), annual_avg(4));
    
    %% ========== Analyze seasonal differences ==========
    fprintf('\nSeasonal Performance Difference Analysis:\n');
    
    % Cost differences
    [max_cost, max_cost_season] = max(results(:, 1));
    [min_cost, min_cost_season] = min(results(:, 1));
    fprintf('  Cost: Highest in %s (%.2f), Lowest in %s (%.2f), Difference %.1f%%\n', ...
            season_names{max_cost_season}, max_cost, ...
            season_names{min_cost_season}, min_cost, ...
            (max_cost - min_cost) / min_cost * 100);
    
    % Carbon emission differences
    [max_carbon, max_carbon_season] = max(results(:, 2));
    [min_carbon, min_carbon_season] = min(results(:, 2));
    fprintf('  Carbon: Highest in %s (%.4ft), Lowest in %s (%.4ft), Difference %.1f%%\n', ...
            season_names{max_carbon_season}, max_carbon, ...
            season_names{min_carbon_season}, min_carbon, ...
            (max_carbon - min_carbon) / min_carbon * 100);
    
    % Flexibility differences
    [min_kPR, min_kPR_season] = min(results(:, 3));
    [max_kPR, max_kPR_season] = max(results(:, 3));
    fprintf('  Power flexibility: Lowest in %s (%.3f), Highest in %s (%.3f)\n', ...
            season_names{min_kPR_season}, min_kPR, ...
            season_names{max_kPR_season}, max_kPR);
    
    %% ========== Calculate annual totals ==========
    fprintf('\nAnnual Total Estimation:\n');
    annual_cost = sum(results(:, 1) .* season_days(:));  % 10^4 CNY/year
    annual_carbon = sum(results(:, 2) .* season_days(:));  % t CO2/year
    fprintf('  Annual operation cost: %.2f ×10^4 CNY\n', annual_cost);
    fprintf('  Annual carbon emission: %.2f t CO2\n', annual_carbon);
    
    % Add annualized investment cost
    global r life_PV life_WT life_ESS life_SOP
    if exist('r', 'var') && ~isempty(r)
        % Calculate annualized investment cost
        [decoded] = decode_and_display_solution(solution);
        CRF = r * (1+r)^20 / ((1+r)^20 - 1);  % Assume 20-year life
        annual_invest = decoded.investment.total * CRF;
        fprintf('  Annualized investment cost: %.2f ×10^4 CNY\n', annual_invest);
        fprintf('  Total annual cost: %.2f ×10^4 CNY\n', annual_cost + annual_invest);
    end
    
    %% ========== Resource utilization analysis ==========
    fprintf('\nResource Utilization Analysis:\n');
    
    % Total DG capacity
    total_pv = sum(cap_pv_nodes);
    total_wind = sum(cap_wind_nodes);
    total_ess = sum(cap_ess_nodes);
    
    if total_pv > 0 || total_wind > 0
        fprintf('  DG capacity: PV=%.2fMW, Wind=%.2fMW\n', total_pv, total_wind);
        
        % Estimate capacity factor
        base_carbon = 30;  % Assumed baseline carbon emission without DG (t/day)
        carbon_reduction = (base_carbon - annual_avg(2)) / base_carbon * 100;
        fprintf('  Carbon reduction effect: %.1f%%\n', carbon_reduction);
    end
    
    % Grid utilization
    effective_branches = sum(xL) + sum(cap_sop_nodes > 0);
    fprintf('  Grid utilization: %d/%d branches active (%.0f%%)\n', ...
            effective_branches, numBr, effective_branches/numBr*100);
end

function plot_pareto_front_3d_soft(paretoSet, best_solution)
% 3D Pareto front plot with soft colors and English labels

    global VarMin
    n_vars = length(VarMin);
    objectives = paretoSet(:, n_vars+1:end);
    
    % Define soft gradient colors
    n_points = size(objectives, 1);
    colors_grad = [linspace(0.4, 0.8, n_points)', ...
                   linspace(0.6, 0.7, n_points)', ...
                   linspace(0.8, 0.4, n_points)'];
    
    % Create 3D scatter plot
    scatter3(objectives(:,1), objectives(:,2), objectives(:,3), ...
             60, colors_grad, 'filled', ...
             'MarkerEdgeColor', [0.3, 0.3, 0.3], ...
             'LineWidth', 0.5);
    
    % Mark TOPSIS-selected optimal solution
    [~, best_idx] = ismember(best_solution(1:n_vars), paretoSet(:,1:n_vars), 'rows');
    if best_idx > 0
        hold on;
        scatter3(objectives(best_idx,1), objectives(best_idx,2), ...
                 objectives(best_idx,3), 200, [0.9, 0.3, 0.3], ...
                 'pentagram', 'filled', ...
                 'MarkerEdgeColor', [0.2, 0.2, 0.2], 'LineWidth', 1.5);
        
        % Add annotation
        text(objectives(best_idx,1), objectives(best_idx,2), ...
             objectives(best_idx,3) + 0.05, ...
             '  Optimal', 'FontSize', 9, 'FontWeight', 'bold');
    end
    
    % Set axes
    xlabel('Economic Cost (10^4 CNY)', 'FontSize', 8);
    ylabel('Carbon Emission (t CO_2)', 'FontSize', 8);
    zlabel('Flexibility Index', 'FontSize', 8);
    title('3D Pareto Front Visualization', 'FontSize', 10);
    
    % Set grid and view
    grid on;
    box on;
    view(45, 30);
    set(gca, 'GridAlpha', 0.3, 'FontSize', 7);
    
    % Use soft background color
    set(gcf, 'Color', [0.98, 0.98, 0.98]);
    set(gca, 'Color', [1, 1, 1]);
end

function generate_detailed_report(solution, decoded, seasonal_results, ...
                                 paretoSet, elapsed_time, timestamp)
% Generate detailed text report in English
    
    filename = sprintf('optimization_report_%s.txt', timestamp);
    fid = fopen(filename, 'w');
    
    fprintf(fid, 'Active Distribution Network Multi-element Coordination Planning Report\n');
    fprintf(fid, '=====================================================================\n');
    fprintf(fid, 'Generated: %s\n', datestr(now));
    fprintf(fid, 'Optimization time: %.2f hours\n', elapsed_time/3600);
    
    fprintf(fid, '\n========== Optimal Planning Solution ==========\n');
    
    % PV configuration
    fprintf(fid, 'PV Configuration:\n');
    if isfield(decoded.pv, 'nodes') && isfield(decoded.pv, 'caps')
        for i = 1:length(decoded.pv.nodes)
            if decoded.pv.caps(i) > 0
                fprintf(fid, '  Bus %d: %.2f MW (%d units × 140 kW/unit)\n', ...
                        decoded.pv.nodes(i), decoded.pv.caps(i), decoded.pv.nums(i));
            end
        end
        fprintf(fid, '  Total capacity: %.2f MW\n', decoded.pv.total_cap);
    end
    
    % Wind configuration
    fprintf(fid, '\nWind Configuration:\n');
    if isfield(decoded.wind, 'nodes') && isfield(decoded.wind, 'caps')
        for i = 1:length(decoded.wind.nodes)
            if decoded.wind.caps(i) > 0
                fprintf(fid, '  Bus %d: %.2f MW (%d units × 180 kW/unit)\n', ...
                        decoded.wind.nodes(i), decoded.wind.caps(i), decoded.wind.nums(i));
            end
        end
        fprintf(fid, '  Total capacity: %.2f MW\n', decoded.wind.total_cap);
    end
    
    % ESS configuration
    fprintf(fid, '\nESS Configuration:\n');
    if isfield(decoded.ess, 'nodes') && isfield(decoded.ess, 'caps')
        for i = 1:length(decoded.ess.nodes)
            if decoded.ess.caps(i) > 0
                fprintf(fid, '  Bus %d: %.2f MW (%d units × 100 kW/unit)\n', ...
                        decoded.ess.nodes(i), decoded.ess.caps(i), decoded.ess.nums(i));
            end
        end
        fprintf(fid, '  Total capacity: %.2f MW\n', decoded.ess.total_cap);
    end
    
    fprintf(fid, '\nTie Switch Configuration:\n');
    fprintf(fid, '  Switch states: %s\n', mat2str(decoded.switches));
    fprintf(fid, '  Closed switches: %d / %d\n', sum(decoded.switches), length(decoded.switches));
    
    fprintf(fid, '\n========== Seasonal Performance ==========\n');
    season_names = {'Spring', 'Summer', 'Autumn', 'Winter'};
    fprintf(fid, 'Season\tCost(10^4CNY)\tCarbon(t)\tkPR\tkGR\n');
    for s = 1:4
        fprintf(fid, '%s\t%.2f\t\t%.4f\t\t%.3f\t%.3f\n', ...
                season_names{s}, seasonal_results(s,1), seasonal_results(s,2), ...
                seasonal_results(s,3), seasonal_results(s,4));
    end
    
    % Annual average
    season_weights = [92, 92, 91, 90] / 365;
    annual_avg = season_weights * seasonal_results;
    fprintf(fid, 'Annual\t%.2f\t\t%.4f\t\t%.3f\t%.3f\n', ...
            annual_avg(1), annual_avg(2), annual_avg(3), annual_avg(4));
    
    fprintf(fid, '\n========== Pareto Front Analysis ==========\n');
    fprintf(fid, 'Number of Pareto solutions: %d\n', size(paretoSet, 1));
    
    % Investment cost summary
    if isfield(decoded, 'investment')
        fprintf(fid, '\n========== Investment Cost Summary ==========\n');
        fprintf(fid, 'PV investment: %.2f ×10^4 CNY\n', decoded.investment.pv);
        fprintf(fid, 'Wind investment: %.2f ×10^4 CNY\n', decoded.investment.wind);
        fprintf(fid, 'ESS investment: %.2f ×10^4 CNY\n', decoded.investment.ess);
        fprintf(fid, 'Tie switch investment: %.2f ×10^4 CNY\n', decoded.investment.switch);
        fprintf(fid, 'SOP investment: %.2f ×10^4 CNY\n', decoded.investment.sop);
        fprintf(fid, 'Total investment: %.2f ×10^4 CNY\n', decoded.investment.total);
    end
    
    fclose(fid);
    fprintf('Detailed report generated: %s\n', filename);
end

function analyze_pareto_front(paretoSet, best_solution)
% Analyze Pareto front
    
    global VarMin
    n_vars = length(VarMin);
    objectives = paretoSet(:, n_vars+1:end);
    
    fprintf('Pareto Front Statistics:\n');
    fprintf('  Cost range: [%.2f, %.2f] ×10^4 CNY\n', ...
            min(objectives(:,1)), max(objectives(:,1)));
    fprintf('  Carbon emission range: [%.4f, %.4f] t\n', ...
            min(objectives(:,2)), max(objectives(:,2)));
    fprintf('  Flexibility range: [%.3f, %.3f]\n', ...
            min(objectives(:,3)), max(objectives(:,3)));
    
    % Find compromise solution
    % Normalize objectives
    obj_norm = zeros(size(objectives));
    for i = 1:size(objectives, 2)
        min_val = min(objectives(:,i));
        max_val = max(objectives(:,i));
        if max_val > min_val
            if i == 3  % Flexibility is maximization objective
                obj_norm(:,i) = (objectives(:,i) - min_val) / (max_val - min_val);
            else  % Cost and carbon are minimization objectives
                obj_norm(:,i) = (max_val - objectives(:,i)) / (max_val - min_val);
            end
        else
            obj_norm(:,i) = 1;
        end
    end
    
    % Calculate distance to ideal point
    ideal_point = ones(1, size(obj_norm, 2));
    distances = sqrt(sum((obj_norm - ideal_point).^2, 2));
    [~, best_idx] = min(distances);
    
    fprintf('\nCompromise Optimal Solution:\n');
    fprintf('  Cost: %.2f ×10^4 CNY\n', objectives(best_idx, 1));
    fprintf('  Carbon emission: %.4f t\n', objectives(best_idx, 2));
    fprintf('  Flexibility: %.3f\n', objectives(best_idx, 3));
end
