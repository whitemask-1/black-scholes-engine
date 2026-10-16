function s = build_surface(res, varargin)
%BUILD_SURFACE Interpolate a volatility surface iv(k, tau) from solved IV points.
%   s = build_surface(res)
%   s = build_surface(res, 'Space','totalvar', 'Method','linear', ...
%                          'NGridK',60, 'NGridTau',40)
%
%   res: table from run_vol_checks (needs columns k = ln(K/F), tau in years,
%        iv_matlab). Rows with non-finite or non-positive values are dropped.
%
%   Options
%     Space   'totalvar' (default) interpolates total variance w = iv^2*tau,
%             which behaves better across maturities; 'iv' interpolates iv.
%     Method  'linear' (default) or 'natural' (smoother, scatteredInterpolant).
%
%   Returns struct s with
%     s.F(kq, tq)      handle -> implied vol at query points (scalars/vectors/
%                      matrices; scalar and vector inputs broadcast). NaN
%                      outside the convex hull of the data - no extrapolation.
%     s.kGrid, s.tauGrid, s.ivGrid (rows = tau, cols = k), s.KK, s.TT
%     s.kRange, s.tauRange, s.coverage (fraction of grid inside the hull),
%     s.nPoints, s.method, s.space
%
%   Both axes are rescaled to [0,1] before triangulating: tau spans ~0.02-0.2
%   while k spans ~-0.25-0.25, and Delaunay triangulation is scale-sensitive.

    p = inputParser;
    addRequired(p, 'res', @istable);
    addParameter(p, 'Method', 'linear');
    addParameter(p, 'Space', 'totalvar');
    addParameter(p, 'NGridK', 60);
    addParameter(p, 'NGridTau', 40);
    parse(p, res, varargin{:});
    o = p.Results;
    method = validatestring(o.Method, {'linear', 'natural'});
    space  = validatestring(o.Space,  {'totalvar', 'iv'});

    need = ["k" "tau" "iv_matlab"];
    have = string(res.Properties.VariableNames);
    if ~all(ismember(need, have))
        error('build_surface:missingColumns', ...
            'res must contain column(s): %s (missing: %s)', ...
            strjoin(need, ', '), strjoin(need(~ismember(need, have)), ', '));
    end

    k = res.k;  tau = res.tau;  iv = res.iv_matlab;
    ok = isfinite(k) & isfinite(tau) & isfinite(iv) & iv > 0 & tau > 0;
    if any(~ok)
        warning('build_surface:droppedRows', ...
            'Dropped %d of %d rows with non-finite or non-positive values.', nnz(~ok), numel(ok));
    end
    k = k(ok);  tau = tau(ok);  iv = iv(ok);

    if numel(k) < 3 || numel(unique(tau)) < 2 || max(k) == min(k)
        error('build_surface:tooFewPoints', ...
            ['Need at least 3 points spanning 2+ expiries and 2+ log-moneyness values ' ...
             '(have %d points, %d expiries).'], numel(k), numel(unique(tau)));
    end

    kmin = min(k);  kmax = max(k);  tmin = min(tau);  tmax = max(tau);
    nk = @(x) (x - kmin) / (kmax - kmin);
    nt = @(x) (x - tmin) / (tmax - tmin);

    if strcmp(space, 'totalvar'), val = iv.^2 .* tau; else, val = iv; end

    % scatteredInterpolant rejects repeated sites: average duplicates
    [pts, ~, ic] = unique([nk(k) nt(tau)], 'rows');
    val = accumarray(ic, val, [], @mean);
    F = scatteredInterpolant(pts(:,1), pts(:,2), val, method, 'none');

    s.F = @(kq, tq) evalSurface(F, nk, nt, space, kq, tq);
    s.kGrid   = linspace(kmin, kmax, o.NGridK);
    s.tauGrid = linspace(tmin, tmax, o.NGridTau);
    [s.KK, s.TT] = meshgrid(s.kGrid, s.tauGrid);
    % Evaluate a hair inside the bounds so exact-boundary round-off cannot punch
    % NaN holes along the edge ring of the grid.
    padK = 1e-9 * (kmax - kmin);  padT = 1e-9 * (tmax - tmin);
    s.ivGrid = s.F(min(max(s.KK, kmin + padK), kmax - padK), ...
                   min(max(s.TT, tmin + padT), tmax - padT));
    s.kRange = [kmin kmax];  s.tauRange = [tmin tmax];
    s.coverage = mean(isfinite(s.ivGrid(:)));
    s.nPoints = numel(k);  s.method = method;  s.space = space;

    fprintf('Surface: %d points, %d expiries, %s interpolation of %s, grid coverage %.0f%%\n', ...
        s.nPoints, numel(unique(tau)), method, space, 100 * s.coverage);
end

function v = evalSurface(F, nk, nt, space, kq, tq)
    kq = kq + 0 * tq;                    % broadcast scalar/vector against each other
    tq = tq + 0 * kq;
    w = F(nk(kq), nt(tq));
    if strcmp(space, 'totalvar')
        % NOTE: do not use max(w,0) here - MATLAB's max() ignores NaN and would turn
        % every outside-the-hull point into 0. Clamp negatives only; NaN stays NaN.
        w(w < 0) = 0;                    % 'natural' interpolation can overshoot below 0
        v = sqrt(w ./ tq);
    else
        v = w;
    end
end
