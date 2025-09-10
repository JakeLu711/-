function [C_cost, C_carbon, K_flex] = evaluate_objectives(x)
%evaluate_objectives Evaluate cost, carbon emission and flexibility.
%   This standalone implementation decodes the branch type decision
%   variables before invoking lower level evaluations. The mapping from
%   branch types to the discrete switch state xL and SOP capacity
%   cap_sop_nodes is performed here to ensure that runLowerLayer and
%   fun_flexibility receive properly discretised inputs.

    global numBr;
    try
        %% ---- Decode upper level decision variables ----
        [cap_pv_nodes, cap_wind_nodes, cap_ess_nodes, xL, cap_sop_nodes] = ...
            decode_upper_decisions(x);

        %% ---- Assemble vector and evaluate lower layer ----
        upx = [cap_pv_nodes, cap_wind_nodes, cap_ess_nodes, xL(:)', cap_sop_nodes(:)'];
        [~, C_cost, C_carbon, kPR_d, kGR_d] = runLowerLayer(upx, 'GA');

        %% ---- Compute long term flexibility ----
        K_flex = fun_flexibility(xL, cap_sop_nodes);
    catch ME
        fprintf('❌ 目标函数计算失败: %s\n', ME.message);
        C_cost = 1e6;
        C_carbon = 1e6;
        K_flex = 0;
    end
end
