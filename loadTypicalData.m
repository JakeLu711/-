function loadTypicalData()
    global seasonCenters seasonProb center_wind seasonWindProb loadCent
    global gailv K
    global baseLoad pl  % 添加这行
    
    gailv = ones(K,1);
    S = load('pv_typical.mat','pvRep');
    seasonCenters = S.pvRep;          % 4×1 cell，每格 1×24
    seasonProb    = {1;1;1;1};

    S = load('wd_typical.mat','wdRep');
    center_wind   = S.wdRep;
    seasonWindProb= {1;1;1;1};

    S = load('load_typical.mat','loadCent');
    loadCent      = S.loadCent;       % 4×24 double
    
    % 确保有 baseLoad 数据
    if isempty(baseLoad) || isempty(pl)
        fprintf('初始化 baseLoad...\n');
        mpc = case33bw();
        Pd_peak = mpc.bus(:,3) * 1e3;  % kW
        
        % 使用第一季（春季）的负荷曲线作为默认
        pl = loadCent(1,:)';  % 24×1
        baseLoad = pl * Pd_peak';  % 24×33 kW
    end
end