%% 子函数：评估目标值（修改版）
function [C_cost, C_carbon, K_flex] = evaluate_objectives(x)
    global numBr;
    
    try
        % 新的upx结构已经在fun_objective中处理
        % 这里直接调用fun_objective获取综合结果
        f = fun_objective(x);
        
        % 或者，如果需要单独获取各项指标：
        % 1. 解码x（与fun_objective相同的逻辑）
        idx = 1;
        % PV容量
        cap_pv_nodes = x(idx:idx+2);  % 假设3个候选点
        idx = idx + 3;
        % Wind容量
        cap_wind_nodes = x(idx:idx+2);
        idx = idx + 3;
        % ESS容量
        cap_ess_nodes = x(idx:idx+2);
        idx = idx + 3;
        % 支路类型
        branch_types = x(idx:idx+numBr-1);
        idx = idx + numBr;
        % SOP容量
        sop_cap_raw = x(idx:idx+numBr-1);
        
        % 2. 处理2选1逻辑
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
                cap_sop_nodes(i) = round(sop_cap_raw(i) * 1e3 / 100) * 100 / 1e3;
            end
        end
        
        % 3. 构建新格式的upx
        upx = [cap_pv_nodes, cap_wind_nodes, cap_ess_nodes, xL(:)', cap_sop_nodes(:)'];
        
        % 4. 调用runLowerLayer
        [~, C_cost, C_carbon, kPR_d, kGR_d] = runLowerLayer(upx, 'GA');
        
        % 5. 计算中长期灵活性（确保联络开关状态离散化）
        xL = xL >= 0.5;
        K_flex = fun_flexibility(xL, cap_sop_nodes);
        
    catch ME
        fprintf('❌ 目标函数计算失败: %s\n', ME.message);
        C_cost = 1e6;
        C_carbon = 1e6;
        K_flex = 0;
    end
end