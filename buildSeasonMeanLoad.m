function [ldMean, prob] = buildSeasonMeanLoad(load8760)
% buildSeasonMeanLoad  按陈鑫方法生成四季平均日负荷 (已标幺)
% 输出:
%   ldMean : 4×24  (春夏秋冬每季 1 条平均曲线, 单位 p.u.)
%   prob   : 4×1   (各季出现概率, = 天数/365)

    % --- Step-0 归一化到全年峰值 ----------------------------
    load8760 = load8760(:);
    load8760 = load8760 / max(load8760);

    % --- Step-1 构造 365×24 的日矩阵 ------------------------
    Pday = reshape(load8760, 24, []).';       % 365×24

    % --- Step-2 季节索引 -----------------------------------
    idx = zeros(365,1);
    idx( 60:151)  = 1;  % 春
    idx(152:243)  = 2;  % 夏
    idx(244:334)  = 3;  % 秋
    idx([335:365,1:59]) = 4;  % 冬

    % --- Step-3 求 24h 均值 & 概率 -------------------------
    ldMean = zeros(4,24);
    prob   = zeros(4,1);
    for s = 1:4
        Pseason       = Pday(idx==s,:);
        ldMean(s,:)   = mean(Pseason, 1);     % 24h 均值
        prob(s)       = size(Pseason,1) / 365;
    end
end

