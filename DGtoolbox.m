function varargout = DGtoolbox(action, varargin)
% ================================================================
%  DGtoolbox —— 风机 / 光伏典型日聚类 & 绘图  (单文件版本)
%  数据文件：solar.mat(rad8760)  windspeed.mat(wind8760)  wendu.mat(temp8760)
%
%  典型调用：
%   [pvC,pvP] = DGtoolbox('cluster','pv',   area, gamma, scale, K);
%   [wdC,wdP] = DGtoolbox('cluster','wind', h0, hubH, alpha, K);
%   DGtoolbox('plot', pvC, wdC, K);
% ================================================================
if nargin==0
    help DGtoolbox;
    return
end

switch lower(action)
    case 'cluster'
        [varargout{1:nargout}] = doCluster(varargin{:});

    case 'plot'
        plotDGTypicalCurves(varargin{:});

    otherwise
        error('未知 action: %s (应为 ''cluster'' 或 ''plot'')', action);
end
end


% ------------------ 主功能：聚类 ------------------ %
function [seasonCenters, seasonProb] = doCluster(datType, varargin)
    rng('shuffle');

    switch lower(datType)
        % -------------------- PV -------------------- %
        case 'pv'
            [area, gamma, scale, K] = deal(varargin{:});

            % 读取辐照 & 温度
            rad8760  = load('rad8760.mat',  'rad8760').rad8760;
            temp8760 = load('temp8760.mat', 'temp8760').temp8760;
            assert(numel(rad8760)==8760 && numel(temp8760)==8760, ...
                   'rad8760.mat/temp8760 长度须 8760');

            % 计算光伏功率
            PkW = computePVpower8760(rad8760, temp8760, area, gamma, scale);
            
            % 方案1：基于年度最大值标幺化
            PkW_max = max(PkW);  % 找到全年最大值
            if PkW_max > 0
                dataAll = reshape(PkW/PkW_max, 24, []).';  % 基于最大值标幺化
            else
                warning('光伏年度最大出力为0，使用原始数据');
                dataAll = reshape(PkW, 24, []).';
            end
            
            % 输出标幺化信息
            fprintf('\n=== 光伏标幺化信息 ===\n');
            fprintf('年度最大出力: %.2f kW\n', PkW_max);
            fprintf('设备额定容量: %.2f kW (单台140kW)\n', 140);
            fprintf('容量系数: %.2f%%\n', PkW_max/140*100);
            fprintf('标幺化基准: %.2f kW\n', PkW_max);

        % ------------------- Wind ------------------- %
        case 'wind'
            [h0, hubH, alpha, K] = deal(varargin{:});
            ws8760   = load('wind8760.mat','wind8760').wind8760;
            assert(numel(ws8760)==8760,'windspeed.mat->wind8760 长度须 8760');

            % 计算风电功率
            ws_h     = ws8760 .* (hubH/h0).^alpha;
            PkW      = computeWindPower(ws_h);
            
            % 方案1：基于年度最大值标幺化
            PkW_max = max(PkW);  % 找到全年最大值
            if PkW_max > 0
                dataAll = reshape(PkW/PkW_max, 24, []).';  % 基于最大值标幺化
            else
                warning('风电年度最大出力为0，使用原始数据');
                dataAll = reshape(PkW, 24, []).';
            end
            
            % 输出标幺化信息
            fprintf('\n=== 风电标幺化信息 ===\n');
            fprintf('年度最大出力: %.2f kW\n', PkW_max);
            fprintf('设备额定容量: %.2f kW (单台180kW)\n', 180);
            fprintf('容量系数: %.2f%%\n', PkW_max/180*100);
            fprintf('标幺化基准: %.2f kW\n', PkW_max);

        otherwise
            error('datType 仅支持 ''pv'' 或 ''wind''');
    end

    % ===== 关闭 switch 前，所有 case 都应已设置 dataAll 与 K ====
    % -----------------------------------------------------------------
    % ---- 四季索引 & K-means 聚类 ----
    idx = zeros(365,1);
    idx(60:151)      = 1;   % 春
    idx(152:243)     = 2;   % 夏
    idx(244:334)     = 3;   % 秋
    idx([335:365 1:59]) = 4; % 冬

    seasonCenters = cell(4,1);
    seasonProb    = cell(4,1);
    opts = statset('MaxIter',1000,'Display','off');

    for s = 1:4
        Xs = dataAll(idx==s,:);
        if K==1
            ids = ones(size(Xs,1),1);
            C   = mean(Xs,1);
        else
            [ids,C] = kmeans(Xs, K, 'Replicates',5,'Options',opts);
        end
        cnt = histcounts(ids, 1:K+1);
        seasonCenters{s} = C;            % K×24
        seasonProb{s}    = cnt / sum(cnt);
    end
    
    % 输出各季节信息
    season_names = {'春季', '夏季', '秋季', '冬季'};
    fprintf('\n=== 各季节典型日信息 ===\n');
    for s = 1:4
        fprintf('%s: %d个典型日，最大值%.3f p.u.\n', ...
                season_names{s}, K, max(max(seasonCenters{s})));
    end
end  % <-- 这是关闭 doCluster 的 END


% ------------ PV 功率：8760 实测温度 -----------------
function PkW = computePVpower8760(rad, temp, area, gamma, scale)
% rad   : 8760×1  辐照 (W/m²) 或归一化辐照
% temp  : 8760×1  实测温度 (℃)
% area  : 组件面积 (m²)
% gamma : 温度系数 (≈0.0045 /℃)
% scale : 系统效率 (0–1)
% ---------------------------------------------------------------
    nt  = numel(rad);
    PkW = zeros(nt,1);

    for t = 1:nt
        h   = mod(t-1,24) + 1;                                   % 小时 1–24
        Prw = rad(t) * area * (1 - gamma*(temp(t) - 25)) * scale; % W

        % —— 判定低辐照或夜间归零 —— 
        if rad(t) < 50 || h < 6 || h > 19       % 50 W/m² 阈值可自行调整
            Prw = 0;
        elseif Prw < 0                          % 防止负功率
            Prw = 0;
        end

        PkW(t) = Prw / 1000;                    % 转 kW
    end
end    % ← 别忘了结束 function

% --------------- 风机功率 -----------------
function Pw = computeWindPower(ws)
    v_in=3.5; v_r=14; v_out=27; Pr=180; coeff=Pr/v_r^3;
    Pw = zeros(size(ws));
    Pw(ws>v_in & ws<=v_r)  = coeff*ws(ws>v_in & ws<=v_r).^3;
    Pw(ws>v_r  & ws<v_out) = Pr;
end

% --------------- 绘图函数 -----------------
function plotDGTypicalCurves(pvCent, windCent, K)
    if nargin<3, K = size(pvCent{1},1); end
    clr = {'#f1c232','#cc4125','#d0a36c','#000000'};

    figure('Color','w'); hold on; box on;
    for s = 1:4
        for k = 1:K
            plot(1:24, windCent{s}(k,:),'-','Color',clr{s},'LineWidth',1.2);
            plot(1:24, pvCent{s}(k,:),'--','Color',clr{s},'LineWidth',1.2);
        end
    end
    xlim([1 24]); ylim([0 1]);
    xlabel('时间 / h'); ylabel('风机、光伏输出 / p.u.');
    title('风机、光伏四季典型输出曲线');
    grid on;

    hPV = arrayfun(@(s) plot(nan,nan,'--','Color',clr{s}), 1:4);
    hWT = arrayfun(@(s) plot(nan,nan,'-','Color',clr{s}),  1:4);
    legend([hPV hWT], ...
           {'光伏(春)','光伏(夏)','光伏(秋)','光伏(冬)', ...
            '风电(春)','风电(夏)','风电(秋)','风电(冬)'}, ...
           'Location','northwest');
end