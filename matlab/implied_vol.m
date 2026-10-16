function [iv, usedBisection] = implied_vol(price, S, K, T, r, q, isCall, fns, tol)
%IMPLIED_VOL Safeguarded Newton-Raphson implied volatility (scalar inputs).
%   [iv, usedBisection] = implied_vol(price, S, K, T, r, q, isCall, fns)
%
%   Newton's method with vega from the symbolic derivation, kept inside a
%   shrinking bracket [lo, hi]. If vega is tiny or a Newton step leaves the
%   bracket, the step falls back to bisection. Returns NaN when the price is
%   outside the no-arbitrage range (no root in [1e-4, 5]) or if it fails to
%   converge. usedBisection is true if any bisection step was needed.

    if nargin < 9, tol = 1e-8; end
    maxIter = 200;
    lo = 1e-4;  hi = 5;
    usedBisection = false;

    if isCall, pf = fns.call; else, pf = fns.put; end
    f = @(s) pf(S, K, T, r, q, s) - price;

    if ~(f(lo) <= 0 && f(hi) >= 0)       % price outside attainable range
        iv = NaN;  return
    end

    sig = 0.3;
    for k = 1:maxIter
        fv = f(sig);
        if abs(fv) < tol || (hi - lo) < 1e-13
            iv = sig;  return
        end
        if fv > 0, hi = sig; else, lo = sig; end   % price monotone in sigma

        v = fns.vega(S, K, T, r, q, sig);
        sNew = sig - fv / v;
        if ~isfinite(sNew) || v < 1e-10 || sNew <= lo || sNew >= hi
            sNew = 0.5 * (lo + hi);
            usedBisection = true;
        end
        sig = sNew;
    end
    iv = NaN;                             % did not converge
end
