function[VarMin, VarMax] = init_upper_bounds(numBr)
    % =================  init_upper_bounds.m  =================
    % 把"上层决策变量"的上下界写进 VarMin / VarMax （全局）
    % 支持多点安装 + 联络开关/SOP 2选1方案
    
    %% 全局量（来自 parameter.m）
    global st_pvc st_windc st_essc ...
           min_pv max_pv min_wind max_wind ...
           min_ess max_ess s_pv s_wind s_cn ...
           S_SOP_ub s_sop_min
    
    %% 参数验证
    % 1. 检查输入参数
    if nargin < 1
        if exist('numBr', 'var') && ~isempty(numBr)
            % 使用全局变量中的 numBr
        else
            error('init_upper_bounds: 缺少必要参数 numBr');
        end
    end
    
    % 2. 检查必要的全局变量是否存在
    required_vars = {'st_pvc', 'st_windc', 'st_essc', ...
                     'min_pv', 'max_pv', 's_pv', 's_wind', 's_cn', ...
                     'S_SOP_ub', 's_sop_min'};
    for i = 1:length(required_vars)
        eval_str = sprintf('exist(''%s'', ''var'') && ~isempty(%s)', ...
                          required_vars{i}, required_vars{i});
        if ~eval(eval_str)
            error('init_upper_bounds: 缺少必要的全局变量 %s', required_vars{i});
        end
    end
    
    %% ==== 1) PV容量（每个候选点独立，以 MW 为单位） ====
    % st_pvc = [6 21 31]，3个候选点
    pv_cap_min = zeros(1, length(st_pvc));  % [0, 0, 0]
    pv_cap_max = ones(1, length(st_pvc)) * max_pv * s_pv / 1000;  % 每个点最多max_pv台
    
    %% ==== 2) Wind容量（每个候选点独立，以 MW 为单位） ====
    % st_windc = [15 23 29]，3个候选点
    wind_cap_min = zeros(1, length(st_windc));  % [0, 0, 0]
    wind_cap_max = ones(1, length(st_windc)) * max_wind * s_wind / 1000;
    
    %% ==== 3) ESS容量（每个候选点独立，以 MW 为单位） ====
    % st_essc = [6 15 23]，3个候选点
    ess_cap_min = zeros(1, length(st_essc));  % [0, 0, 0]
    ess_cap_max = ones(1, length(st_essc)) * max_ess * s_cn / 1000;
    
    %% ==== 4) 支路配置类型（联络开关/SOP 2选1） ====
    % 每条支路的配置用一个连续变量表示：
    % [0, 0.5) → 常开（无设备）
    % [0.5, 1.5) → 联络开关
    % [1.5, 2] → SOP
    branch_type_min = zeros(1, numBr);  % [0, 0, 0, 0, 0]
    branch_type_max = 2 * ones(1, numBr);  % [2, 2, 2, 2, 2]
    
    %% ==== 5) SOP容量（仅当选择SOP时有效，以 MVA 为单位） ====
    % 每条支路的SOP容量（如果该支路选择安装SOP）
    sop_cap_min = zeros(1, numBr);  % [0, 0, 0, 0, 0]
    sop_cap_max = ones(1, numBr) * S_SOP_ub / 1000;  % [3, 3, 3, 3, 3] MVA
    
    %% ==== 6) 拼接成 VarMin / VarMax ====
    VarMin = [pv_cap_min, wind_cap_min, ess_cap_min, ...
              branch_type_min, sop_cap_min];
              
    VarMax = [pv_cap_max, wind_cap_max, ess_cap_max, ...
              branch_type_max, sop_cap_max];
    
    %% ==== 7) 输出信息 ====
    fprintf('\n========== 决策变量结构（多点安装 + 2选1方案） ==========\n');
    fprintf('PV容量变量: %d个 (节点: %s)\n', length(pv_cap_min), mat2str(st_pvc));
    fprintf('  范围: [%.2f, %.2f] MW/节点\n', min(pv_cap_min), max(pv_cap_max));
    
    fprintf('Wind容量变量: %d个 (节点: %s)\n', length(wind_cap_min), mat2str(st_windc));
    fprintf('  范围: [%.2f, %.2f] MW/节点\n', min(wind_cap_min), max(wind_cap_max));
    
    fprintf('ESS容量变量: %d个 (节点: %s)\n', length(ess_cap_min), mat2str(st_essc));
    fprintf('  范围: [%.2f, %.2f] MW/节点\n', min(ess_cap_min), max(ess_cap_max));
    
    fprintf('支路类型变量: %d个\n', numBr);
    fprintf('  0-0.5: 常开, 0.5-1.5: 联络开关, 1.5-2: SOP\n');
    
    fprintf('SOP容量变量: %d个\n', numBr);
    fprintf('  范围: [%.2f, %.2f] MVA/支路\n', min(sop_cap_min), max(sop_cap_max));
    
    fprintf('决策变量总数: %d\n', length(VarMin));
    fprintf('=========================================================\n');
end