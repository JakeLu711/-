function [best_idx, scores] = topsis_evaluation(objectives, weights, criteria)
% topsis_evaluation - TOPSIS多准则决策方法
% 输入:
%   objectives - m×n矩阵，m个方案，n个目标
%   weights - 1×n向量，各目标权重
%   criteria - 1×n逻辑向量，true表示越大越好，false表示越小越好
% 输出:
%   best_idx - 最优方案索引
%   scores - m×1向量，各方案的TOPSIS得分

    %% 1. 参数验证
    [m, n] = size(objectives);
    
    if length(weights) ~= n
        error('权重向量长度必须与目标数量一致');
    end
    
    if length(criteria) ~= n
        error('准则向量长度必须与目标数量一致');
    end
    
    % 归一化权重
    weights = weights / sum(weights);
    
    %% 2. 数据预处理
    % 处理极端值（避免除零错误）
    objectives(objectives == 0) = eps;
    
    %% 3. 规范化决策矩阵
    % 使用向量规范化方法
    norm_matrix = zeros(m, n);
    for j = 1:n
        denom = sqrt(sum(objectives(:,j).^2));
        if denom > 0
            norm_matrix(:,j) = objectives(:,j) / denom;
        else
            norm_matrix(:,j) = objectives(:,j);
        end
    end
    
    %% 4. 构造加权规范化决策矩阵
    weighted_matrix = zeros(m, n);
    for j = 1:n
        weighted_matrix(:,j) = norm_matrix(:,j) * weights(j);
    end
    
    %% 5. 确定正理想解(A+)和负理想解(A-)
    A_plus = zeros(1, n);   % 正理想解
    A_minus = zeros(1, n);  % 负理想解
    
    for j = 1:n
        if criteria(j)  % 越大越好的指标
            A_plus(j) = max(weighted_matrix(:,j));
            A_minus(j) = min(weighted_matrix(:,j));
        else  % 越小越好的指标
            A_plus(j) = min(weighted_matrix(:,j));
            A_minus(j) = max(weighted_matrix(:,j));
        end
    end
    
    %% 6. 计算各方案到正负理想解的距离
    D_plus = zeros(m, 1);   % 到正理想解的距离
    D_minus = zeros(m, 1);  % 到负理想解的距离
    
    for i = 1:m
        D_plus(i) = sqrt(sum((weighted_matrix(i,:) - A_plus).^2));
        D_minus(i) = sqrt(sum((weighted_matrix(i,:) - A_minus).^2));
    end
    
    %% 7. 计算相对贴近度（TOPSIS得分）
    scores = zeros(m, 1);
    for i = 1:m
        if (D_plus(i) + D_minus(i)) > 0
            scores(i) = D_minus(i) / (D_plus(i) + D_minus(i));
        else
            scores(i) = 0;
        end
    end
    
    %% 8. 找出最优方案
    [~, best_idx] = max(scores);
    
    %% 9. 调试输出（可选）
    fprintf('\n=== TOPSIS评估详情 ===\n');
    fprintf('方案数量: %d\n', m);
    fprintf('目标数量: %d\n', n);
    fprintf('权重: %s\n', mat2str(weights, 3));
    fprintf('准则: %s (1=越大越好, 0=越小越好)\n', mat2str(double(criteria)));
    
    % 显示前5个方案的得分
    num_display = min(5, m);
    fprintf('\n前%d个方案的TOPSIS得分:\n', num_display);
    [sorted_scores, sorted_idx] = sort(scores, 'descend');
    for i = 1:num_display
        idx = sorted_idx(i);
        fprintf('  方案%d: 得分=%.4f, 目标值=[%.4f, %.4f, %.4f]\n', ...
                idx, sorted_scores(i), objectives(idx,1), ...
                objectives(idx,2), objectives(idx,3));
    end
    
    %% 10. 数据合理性检查
    if any(isnan(scores)) || any(isinf(scores))
        warning('TOPSIS计算结果包含NaN或Inf值');
        % 如果出现异常，选择第一个有效方案
        valid_idx = find(~isnan(scores) & ~isinf(scores));
        if ~isempty(valid_idx)
            [~, best_among_valid] = max(scores(valid_idx));
            best_idx = valid_idx(best_among_valid);
        else
            best_idx = 1;  % 默认选择第一个
        end
    end
    
end