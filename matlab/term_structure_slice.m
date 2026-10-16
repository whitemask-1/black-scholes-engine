function ts = term_structure_slice(s, k0, n)
%TERM_STRUCTURE_SLICE Implied vol vs maturity at fixed log-moneyness k0 (default 0 = at the forward).
%   ts = term_structure_slice(s)  or  term_structure_slice(s, -0.05, 80)
%   Only maturities where k0 lies inside the data hull are returned.
%   Fields: tau, days, iv, k.
    if nargin < 2 || isempty(k0), k0 = 0; end
    if nargin < 3, n = 100; end
    pad = 1e-9 * (s.tauRange(2) - s.tauRange(1));
    taus = linspace(s.tauRange(1) + pad, s.tauRange(2) - pad, n)';
    iv = s.F(k0 * ones(size(taus)), taus);
    ok = isfinite(iv);
    if nnz(ok) < 2
        warning('term_structure_slice:outsideData', ...
            'k0 = %.3f is outside the data for almost every maturity (k range %.3f to %.3f).', ...
            k0, s.kRange(1), s.kRange(2));
    end
    ts.tau = taus(ok);  ts.days = ts.tau * 365.25;  ts.iv = iv(ok);  ts.k = k0;
end
