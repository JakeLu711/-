function decode_and_display_solution(best_up)
% 解析并显示最优方案（多点安装 + 联络开关/SOP 2选1）

global st_pvc st_windc st_essc numBr

%% 解析决策变量
idx = 1;
% PV容量（按候选节点顺序）
pv_caps = best_up(idx : idx + length(st_pvc) - 1);
idx = idx + length(st_pvc);
% 风电容量
wind_caps = best_up(idx : idx + length(st_windc) - 1);
idx = idx + length(st_windc);
% 储能容量
ess_caps = best_up(idx : idx + length(st_essc) - 1);
idx = idx + length(st_essc);
% 支路类型与SOP容量
branch_types  = best_up(idx : idx + numBr - 1);
idx = idx + numBr;
sop_cap_nodes = best_up(idx : end);

%% 显示结果
fprintf('\n=== 最优规划方案 ===\n');

fprintf('\n光伏配置:\n');
for i = 1:length(st_pvc)
    fprintf('  节点%2d: %.2f MW\n', st_pvc(i), pv_caps(i));
end

fprintf('\n风电配置:\n');
for i = 1:length(st_windc)
    fprintf('  节点%2d: %.2f MW\n', st_windc(i), wind_caps(i));
end

fprintf('\n储能配置:\n');
for i = 1:length(st_essc)
    fprintf('  节点%2d: %.2f MW\n', st_essc(i), ess_caps(i));
end

fprintf('\n支路设备配置:\n');
for i = 1:numBr
    if branch_types(i) < 0.5
        fprintf('  支路%d: 常开\n', i);
    elseif branch_types(i) < 1.5
        fprintf('  支路%d: 联络开关(闭合)\n', i);
    else
        fprintf('  支路%d: SOP, 容量 %.2f MVA\n', i, sop_cap_nodes(i));
    end
end

end
