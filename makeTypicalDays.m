function makeTypicalDays
% --------------------------------------------------------------
% 把风/光/负荷典型日曲线一次性计算并存成 mat 文件
% 之后只需 run parameter + loadTypicalData 即可
% --------------------------------------------------------------
% 检查必要的数据文件
    required_files = {'rad8760.mat', 'wind8760.mat', 'temp8760.mat', 'load8760.mat'};
    missing_files = {};
    
    for i = 1:length(required_files)
        if ~exist(required_files{i}, 'file')
            missing_files{end+1} = required_files{i};
        end
    end
    
    if ~isempty(missing_files)
        error('缺少必要的数据文件：%s', strjoin(missing_files, ', '));
    end
% ---------- 用户自行设定的输入 ----------
pvArea   = 50;       gammaT = 0.0045;   pvEff   = 0.90;
h0       = 10;       hubH   = 60;       alphaWS = 0.14;
K        = 1;

[pvCent,pvProb] = DGtoolbox('cluster','pv',   pvArea,gammaT,pvEff,K);
[wdCent,wdProb] = DGtoolbox('cluster','wind', h0,hubH,alphaWS,K);
% ----------- 压缩为单曲线 -----------
pvRep = cell(4,1);   wdRep = cell(4,1);
for s = 1:4
    pvRep{s} = pvProb{s} * pvCent{s};   % 1 × 24
    wdRep{s} = wdProb{s} * wdCent{s};   % 1 × 24
end
% ---------- 方案 A：读取已有 8760 负荷文件 ----------
 S = load('load8760.mat','load8760');  % 文件里必须有变量 load8760
 load8760 = S.load8760(:);             % 8760×1

[loadCent,~] = buildSeasonMeanLoad(load8760);


 % 保存时包含更多信息
    save pv_typical.mat   'pvCent' 'pvProb' 'pvRep' 'K' 'pvArea' 'gammaT' 'pvEff'
    save wd_typical.mat   'wdCent' 'wdProb' 'wdRep' 'K' 'h0' 'hubH' 'alphaWS'
    save load_typical.mat 'loadCent' 'K'
    
    % 添加数据生成日志
    info = struct();
    info.generateTime = datestr(now);
    info.K = K;
    info.pvParams = struct('area', pvArea, 'gamma', gammaT, 'eff', pvEff);
    info.windParams = struct('h0', h0, 'hubH', hubH, 'alpha', alphaWS);
    save typical_info.mat 'info'
    
    fprintf("√ 已生成每季 %d 条典型曲线\n", K);
    fprintf("  生成时间：%s\n", datestr(now));
end
%save pv_typical.mat   pvCent  pvRepsave wd_typical.mat   wdCent  wdRep
%save load_typical.mat loadCent 
%fprintf("√ 已生成每季 1 条典型曲线：pv_rep / wd_rep / load_cent\n");