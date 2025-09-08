function plotSeasonalProfiles(useGlobal, normMethod)
% plotSeasonalProfiles - Display normalized PV/Wind/Load profiles for four seasons
% 
% Features:
%   1. Read existing typical day data from global variables or mat files
%   2. Plot seasonal PV and wind curves (in the same figure)
%   3. Plot seasonal load curves (in another figure)
%   4. Support multiple normalization methods
%
% Prerequisites:
%   - Need to run main.m first to generate data, or ensure typical day mat files exist
%
% Usage:
%   plotSeasonalProfiles()                    % Interactive selection, read from files
%   plotSeasonalProfiles(true)                % Interactive selection, read from global variables
%   plotSeasonalProfiles(false, 'annual')     % Normalize by annual average
%   plotSeasonalProfiles(false, 'cluster')    % Normalize by cluster maximum
%   plotSeasonalProfiles(false, 'seasonal')   % Normalize by seasonal average

    %% Parse input arguments
    if nargin < 1
        useGlobal = false;  % Default: read from files
    end
    
    if nargin < 2
        % If normalization method not specified, show selection dialog
        normMethod = questdlg('Select normalization method:', 'Normalization Method', ...
            'Annual Average', 'Cluster Maximum', 'Seasonal Average', 'Annual Average');
        if isempty(normMethod)
            normMethod = 'Annual Average';  % Default selection
        end
    else
        % Convert abbreviations to full names
        switch lower(normMethod)
            case {'annual', 'annual_average', 'annual_avg'}
                normMethod = 'Annual Average';
            case {'cluster', 'cluster_max', 'max'}
                normMethod = 'Cluster Maximum';
            case {'seasonal', 'seasonal_average', 'seasonal_avg'}
                normMethod = 'Seasonal Average';
            otherwise
                warning('Unknown normalization method, using default annual average');
                normMethod = 'Annual Average';
        end
    end
    
    %% 1. Get data
    fprintf('Loading data...\n');
    
    if useGlobal
        % Read from global variables
        global seasonCenters center_wind loadCent
        
        if isempty(seasonCenters) || isempty(center_wind) || isempty(loadCent)
            error('Global variables are empty! Please run main.m first to generate data, or use plotSeasonalProfiles() to read from files');
        end
        
        pvProfiles = seasonCenters;
        windProfiles = center_wind;
        loadProfiles = loadCent;
        
    else
        % Read from files
        if ~exist('pv_typical.mat', 'file') || ~exist('wd_typical.mat', 'file') || ~exist('load_typical.mat', 'file')
            error('Typical day data files do not exist! Please run main.m first to generate data');
        end
        
        % Load PV data
        pvData = load('pv_typical.mat');
        if isfield(pvData, 'pvRep')
            pvProfiles = pvData.pvRep;  % 4×1 cell, each is 1×24
        elseif isfield(pvData, 'pvCent')
            % If only pvCent exists, compress to single curve
            pvProfiles = cell(4,1);
            for s = 1:4
                pvProfiles{s} = pvData.pvProb{s} * pvData.pvCent{s};
            end
        else
            error('PV data format error');
        end
        
        % Load wind data
        windData = load('wd_typical.mat');
        if isfield(windData, 'wdRep')
            windProfiles = windData.wdRep;  % 4×1 cell, each is 1×24
        elseif isfield(windData, 'wdCent')
            % If only wdCent exists, compress to single curve
            windProfiles = cell(4,1);
            for s = 1:4
                windProfiles{s} = windData.wdProb{s} * windData.wdCent{s};
            end
        else
            error('Wind data format error');
        end
        
        % Load load data
        loadData = load('load_typical.mat');
        if isfield(loadData, 'loadCent')
            loadProfiles = loadData.loadCent;  % 4×24 matrix
        else
            error('Load data format error');
        end
    end
    
    %% 2. Data normalization
    fprintf('Performing normalization...\n');
    
    % Calculate normalization base values
    fprintf('Using normalization method: %s\n', normMethod);
    
    % Calculate base values for each data type
    switch normMethod
        case 'Annual Average'
            % Calculate annual average (average of all seasons and hours)
            pv_base = calculateAnnualAverage(pvProfiles);
            wind_base = calculateAnnualAverage(windProfiles);
            load_base = calculateAnnualAverage(loadProfiles);
            
        case 'Cluster Maximum'
            % Use maximum value from clustered typical days
            pv_base = calculateClusterMax(pvProfiles);
            wind_base = calculateClusterMax(windProfiles);
            load_base = calculateClusterMax(loadProfiles);
            
        case 'Seasonal Average'
            % Each season uses its own average (returns 4 values)
            pv_base = calculateSeasonalAverage(pvProfiles);
            wind_base = calculateSeasonalAverage(windProfiles);
            load_base = calculateSeasonalAverage(loadProfiles);
    end
    
    % Display base value information
    if ~iscell(pv_base)
        fprintf('Normalization base values:\n');
        fprintf('  PV: %.4f\n', pv_base);
        fprintf('  Wind: %.4f\n', wind_base);
        fprintf('  Load: %.4f\n', load_base);
    end
    
    % Time axis (24 hours)
    hours = 1:24;
    
    % Season names in English
    seasons = {'Spring', 'Summer', 'Autumn', 'Winter'};
    
    % Use softer color scheme
    % Spring green, summer orange, autumn brown, winter blue
    colors = {[0.2, 0.6, 0.2],    % Soft green
              [0.9, 0.5, 0.1],    % Soft orange
              [0.7, 0.4, 0.1],    % Soft brown
              [0.2, 0.4, 0.8]};   % Soft blue
    
    %% Figure size settings
    % Convert 7cm to pixels (assuming 96 DPI)
    cm_to_inch = 1/2.54;
    dpi = 96;
    fig_width_cm = 7;
    fig_width_pixels = fig_width_cm * cm_to_inch * dpi;  % 7cm in pixels
    fig_height_pixels = fig_width_pixels * 0.75;  % 4:3 aspect ratio
    
    %% 3. Plot PV and wind curves (same axes)
    figure('Name', 'Seasonal PV and Wind Output Curves', ...
           'Position', [100, 100, fig_width_pixels, fig_height_pixels], ...
           'PaperUnits', 'centimeters', ...
           'PaperSize', [fig_width_cm, fig_width_cm*0.75], ...
           'PaperPosition', [0, 0, fig_width_cm, fig_width_cm*0.75]);
    hold on;
    grid on;
    
    % Plot PV curves (dashed) and wind curves (solid)
    for s = 1:4
        % PV curves (dashed)
        pv_curve = pvProfiles{s};
        % Ensure row vector
        if size(pv_curve, 1) > size(pv_curve, 2)
            pv_curve = pv_curve';
        end
        % Use new normalization base
        if iscell(pv_base)
            pv_normalized = pv_curve / pv_base{s};  % Different base for each season
        else
            pv_normalized = pv_curve / pv_base;      % Unified base
        end
        plot(hours, pv_normalized, '--', 'Color', colors{s}, 'LineWidth', 1.5, ...
            'DisplayName', [seasons{s} ' - PV']);
        
        % Wind curves (solid)
        wind_curve = windProfiles{s};
        % Ensure row vector
        if size(wind_curve, 1) > size(wind_curve, 2)
            wind_curve = wind_curve';
        end
        % Use new normalization base
        if iscell(wind_base)
            wind_normalized = wind_curve / wind_base{s};  % Different base for each season
        else
            wind_normalized = wind_curve / wind_base;      % Unified base
        end
        plot(hours, wind_normalized, '-', 'Color', colors{s}, 'LineWidth', 1.5, ...
            'DisplayName', [seasons{s} ' - Wind']);
    end
    
    % Set axis labels with Times New Roman font, 8pt
    xlabel('Time (h)', 'FontSize', 8, 'FontName', 'Times New Roman');
    ylabel('Normalized Output', 'FontSize', 8, 'FontName', 'Times New Roman');
    
    % Set title with Times New Roman font, 9pt, no bold
    title('Seasonal PV and Wind Output', 'FontSize', 9, 'FontWeight', 'normal', 'FontName', 'Times New Roman');
    
    % Adjust legend for small figure with Times New Roman font, 8pt
    legend('Location', 'southoutside', 'NumColumns', 2, 'FontSize', 8, ...
           'Orientation', 'horizontal', 'Box', 'off', 'FontName', 'Times New Roman');
    
    xlim([1, 24]);
    % Set tick labels font to Times New Roman, 8pt
    set(gca, 'XTick', 0:6:24, 'FontSize', 8, 'FontName', 'Times New Roman');
    
    % Set background color to light gray
    set(gca, 'Color', [0.95, 0.95, 0.95]);
    
    % Adjust layout
    set(gca, 'Position', [0.12, 0.25, 0.83, 0.65]);  % Leave space for legend
    
    %% 4. Plot load curves (second figure)
    figure('Name', 'Seasonal Load Curves', ...
           'Position', [100 + fig_width_pixels + 20, 100, fig_width_pixels, fig_height_pixels], ...
           'PaperUnits', 'centimeters', ...
           'PaperSize', [fig_width_cm, fig_width_cm*0.75], ...
           'PaperPosition', [0, 0, fig_width_cm, fig_width_cm*0.75]);
    hold on;
    grid on;
    
    for s = 1:4
        load_curve = loadProfiles(s, :);
        % Use new normalization base
        if iscell(load_base)
            load_normalized = load_curve / load_base{s};  % Different base for each season
        else
            load_normalized = load_curve / load_base;      % Unified base
        end
        plot(hours, load_normalized, '-', 'Color', colors{s}, 'LineWidth', 2, ...
            'DisplayName', seasons{s});
    end
    
    % Set axis labels with Times New Roman font, 8pt
    xlabel('Time (h)', 'FontSize', 8, 'FontName', 'Times New Roman');
    ylabel('Normalized Load', 'FontSize', 8, 'FontName', 'Times New Roman');
    
    % Set title with Times New Roman font, 9pt, no bold
    title('Seasonal Load Curves', 'FontSize', 9, 'FontWeight', 'normal', 'FontName', 'Times New Roman');
    
    % Set legend with Times New Roman font, 8pt
    legend('Location', 'best', 'FontSize', 8, 'Box', 'off', 'FontName', 'Times New Roman');
    xlim([1, 24]);
    
    % Dynamic y-axis range adjustment
    if iscell(load_base)
        ylim([0, max(loadProfiles(:))/min(cell2mat(load_base))*1.1]);
    else
        ylim([0, max(loadProfiles(:))/load_base*1.1]);
    end
    
    % Set tick labels font to Times New Roman, 8pt
    set(gca, 'XTick', 0:6:24, 'FontSize', 8, 'FontName', 'Times New Roman');
    
    % Set background color to light gray
    set(gca, 'Color', [0.95, 0.95, 0.95]);
    
    %% 5. Output statistics
    fprintf('\n=== Data Statistics ===\n');
    fprintf('Normalization method: %s\n', normMethod);
    
    for s = 1:4
        fprintf('\n%s:\n', seasons{s});
        
        % PV statistics
        pv = pvProfiles{s};
        if iscell(pv_base)
            pv_norm = pv / pv_base{s};
            fprintf('  PV - Base: %.4f, Peak p.u.: %.2f, Average p.u.: %.2f\n', ...
                pv_base{s}, max(pv_norm), mean(pv_norm));
        else
            pv_norm = pv / pv_base;
            fprintf('  PV - Base: %.4f, Peak p.u.: %.2f, Average p.u.: %.2f\n', ...
                pv_base, max(pv_norm), mean(pv_norm));
        end
        
        % Wind statistics
        wind = windProfiles{s};
        if iscell(wind_base)
            wind_norm = wind / wind_base{s};
            fprintf('  Wind - Base: %.4f, Peak p.u.: %.2f, Average p.u.: %.2f\n', ...
                wind_base{s}, max(wind_norm), mean(wind_norm));
        else
            wind_norm = wind / wind_base;
            fprintf('  Wind - Base: %.4f, Peak p.u.: %.2f, Average p.u.: %.2f\n', ...
                wind_base, max(wind_norm), mean(wind_norm));
        end
        
        % Load statistics
        load_s = loadProfiles(s, :);
        if iscell(load_base)
            load_norm = load_s / load_base{s};
            fprintf('  Load - Base: %.4f, Peak p.u.: %.2f, Average p.u.: %.2f\n', ...
                load_base{s}, max(load_norm), mean(load_norm));
        else
            load_norm = load_s / load_base;
            fprintf('  Load - Base: %.4f, Peak p.u.: %.2f, Average p.u.: %.2f\n', ...
                load_base, max(load_norm), mean(load_norm));
        end
    end
    
    fprintf('\nPlotting completed!\n');
    
    %% Save figures option
    response = input('Save figures as images? (y/n) [n]: ', 's');
    if strcmpi(response, 'y')
        % Save PV and Wind figure
        figure(1);
        print('seasonal_pv_wind_7cm.png', '-dpng', '-r300');
        print('seasonal_pv_wind_7cm.eps', '-depsc2');
        
        % Save Load figure
        figure(2);
        print('seasonal_load_7cm.png', '-dpng', '-r300');
        print('seasonal_load_7cm.eps', '-depsc2');
        
        fprintf('Figures saved as PNG and EPS formats.\n');
    end
end

%% Helper function: Calculate annual average
function avgValue = calculateAnnualAverage(data)
    % Calculate average of all seasons and hours
    if iscell(data)
        % For cell arrays (PV, wind)
        allData = [];
        for s = 1:length(data)
            allData = [allData, data{s}(:)'];
        end
        avgValue = mean(allData);
    else
        % For matrices (load)
        avgValue = mean(data(:));
    end
end

%% Helper function: Calculate cluster maximum
function maxValue = calculateClusterMax(data)
    % Use maximum value from clustered typical days
    if iscell(data)
        % For cell arrays (PV, wind)
        maxValues = zeros(1, length(data));
        for s = 1:length(data)
            maxValues(s) = max(data{s}(:));
        end
        maxValue = max(maxValues);  % Maximum across all seasons
    else
        % For matrices (load)
        maxValue = max(data(:));
    end
end

%% Helper function: Calculate seasonal average
function avgValues = calculateSeasonalAverage(data)
    % Calculate average for each season
    if iscell(data)
        % For cell arrays (PV, wind)
        avgValues = cell(size(data));
        for s = 1:length(data)
            avgValues{s} = mean(data{s}(:));
        end
    else
        % For matrices (load)
        avgValues = cell(4, 1);
        for s = 1:4
            avgValues{s} = mean(data(s, :));
        end
    end
end