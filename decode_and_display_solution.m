function decode_and_display_solution(best_up)
% 解析并显示最优方案

global st_pvc st_windc st_essc numBr

% 解析决策变量
idx = 1;
% PV
loc_pv = round(best_up(idx)); idx = idx + 1;
cap_pv = best_up(idx); idx = idx + 1;
% Wind
loc_wind = round(best_up(idx)); idx = idx + 1;
cap_wind = best_up(idx); idx = idx + 1;
% ESS
loc_ess = round(best_up(idx)); idx = idx + 1;
cap_ess = best_up(idx); idx = idx + 1;
% 联络开关
xL = best_up(idx:end);

% 显示结果
fprintf('\n=== 最优规划方案 ===\n');
fprintf('光伏配置:\n');
fprintf('  位置: 节点%d\n', st_pvc(loc_pv));
fprintf('  容量: %.2f MW\n', cap_pv);

fprintf('\n风电配置:\n');
fprintf('  位置: 节点%d\n', st_windc(loc_wind));
fprintf('  容量: %.2f MW\n', cap_wind);

fprintf('\n储能配置:\n');
fprintf('  位置: 节点%d\n', st_essc(loc_ess));
fprintf('  容量: %.2f MW\n', cap_ess);

fprintf('\n联络开关配置:\n');
for i = 1:numBr
    if xL(i) == 1
        fprintf('  联络支路%d: 闭合\n', i);
    else
        fprintf('  联络支路%d: 断开\n', i);
    end
end

end