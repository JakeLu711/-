function updateSeason(s)
    global pl baseLoad loadCent seasonCenters center_wind

    % ① 负荷曲线
    pl = loadCent(s,:).';                % 24×1 p.u.
    Pd_peak = case33bw(); Pd_peak = Pd_peak.bus(:,3)*1e3;
    baseLoad = pl * Pd_peak.';           % 24×33 kW

    % ② 风光曲线，如有需要也可写进全局
    pv24h = seasonCenters{s};            % 1×24
    wt24h = center_wind{s};
    assignin('base','pv24h',pv24h);      % 若下层模型直接从 base 取
    assignin('base','wt24h',wt24h);
end