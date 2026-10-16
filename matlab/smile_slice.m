function sl = smile_slice(s, res, expiry, n)
%SMILE_SLICE Smile (iv vs log-moneyness) for one expiry: market points + surface curve.
%   sl = smile_slice(s, res, "2026-11-20")      n curve points (default 100)
%   Fields: k, iv (surface curve), kMarket, ivMarket, tau, expiry.
    if nargin < 4, n = 100; end
    expiry = string(expiry);
    m = res.expiry == expiry & isfinite(res.iv_matlab);
    if ~any(m)
        error('smile_slice:noExpiry', 'No data for expiry %s. Available: %s', ...
            expiry, strjoin(unique(res.expiry), ', '));
    end
    kM = res.k(m);  ivM = res.iv_matlab(m);  tau0 = mean(res.tau(m));

    % The first/last expiry lies exactly on the hull boundary; nudge inward so
    % boundary round-off cannot turn the whole curve into NaN.
    padT = 1e-9 * (s.tauRange(2) - s.tauRange(1));
    tauQ = min(max(tau0, s.tauRange(1) + padT), s.tauRange(2) - padT);
    padK = 1e-6 * (max(kM) - min(kM));

    sl.k  = linspace(min(kM) + padK, max(kM) - padK, n)';
    sl.iv = s.F(sl.k, tauQ * ones(size(sl.k)));
    sl.kMarket = kM;  sl.ivMarket = ivM;  sl.tau = tau0;  sl.expiry = expiry;
end
