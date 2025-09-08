function runFourSeasons()
    clear; clc;
    parameter();
    loadTypicalData();
    
    % 需要构建符合新格式的upx
    % 示例：假设某个配置
    cap_pv_nodes = [0.28, 0, 0];      % 只在节点6安装
    cap_wind_nodes = [0, 0.36, 0];    % 只在节点23安装
    cap_ess_nodes = [0, 0.2, 0];      % 只在节点15安装
    xL = [1, 1, 0, 1, 1];             % 4个联络开关闭合
    cap_sop_nodes = [0, 0, 0, 0, 0];  % 不安装SOP
    
    upx = [cap_pv_nodes, cap_wind_nodes, cap_ess_nodes, xL, cap_sop_nodes];
    
    results = cell(4,1);
    for s = 1:4
        updateSeason(s);
        results{s} = runLowerLayer(upx,'GA');
    end
    save('allSeasonResults.mat','results');
end