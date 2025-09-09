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
        idx = 1;
        % PV, wind and ESS capacities (direct use of continuous values)
        cap_pv_nodes  = x(idx:idx+2); idx = idx + 3;
        cap_wind_nodes= x(idx:idx+2); idx = idx + 3;
        cap_ess_nodes = x(idx:idx+2); idx = idx + 3;
        % Branch type selection and raw SOP capacities
        branch_types  = x(idx:idx+numBr-1); idx = idx + numBr;
        sop_cap_raw   = x(idx:idx+numBr-1);

        %% ---- Map branch types to switch state and SOP capacity ----
        xL = zeros(numBr,1);
        cap_sop_nodes = zeros(numBr,1);
        for i = 1:numBr
            if branch_types(i) < 0.5
                % keep normally open, no device installed
                xL(i) = 0;
                cap_sop_nodes(i) = 0;
            elseif branch_types(i) < 1.5
                % install tie switch
                xL(i) = 1;
                cap_sop_nodes(i) = 0;
            else
                % install SOP, discretise capacity to 0.1 MW steps
                xL(i) = 0;
                cap_sop_nodes(i) = round(sop_cap_raw(i)*1e3/100)*100/1e3;
            end
        end

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
