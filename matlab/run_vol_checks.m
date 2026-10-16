function res = run_vol_checks(csvPath, varargin)
%RUN_VOL_CHECKS Load any options-chain CSV, solve IVs in MATLAB, compare to reference.
%   res = run_vol_checks('snapshots/AAPL_latest.csv')
%   res = run_vol_checks(csv, 'Plot', false, 'OTMOnly', true, 'Tol', 1e-8)
%
%   Pipeline: load_chain -> bs_symbolic -> forward_from_parity -> select_otm
%             -> implied_vol (per row) -> compare against iv_ocaml if present.
%   Returns a table with one row per solved contract and prints a summary.

    p = inputParser;
    addRequired(p, 'csvPath');
    addParameter(p, 'Plot', true);
    addParameter(p, 'OTMOnly', true);
    addParameter(p, 'Tol', 1e-8);
    addParameter(p, 'RefColumn', 'iv_ocaml');
    addParameter(p, 'Verbose', true);        % false: don't print the symbolic derivation
    parse(p, csvPath, varargin{:});
    o = p.Results;

    chain = load_chain(o.csvPath);
    fns   = bs_symbolic(logical(o.Verbose));
    chain = forward_from_parity(chain);
    if o.OTMOnly
        chain = chain(select_otm(chain), :);
    end
    n = height(chain);
    fprintf('\nSolving implied vol for %d contracts across %d expiries...\n', ...
        n, numel(unique(chain.expiry)));

    iv = nan(n, 1);  bis = false(n, 1);
    for i = 1:n
        [iv(i), bis(i)] = implied_vol(chain.mid(i), chain.spot(i), chain.strike(i), ...
            chain.tau(i), chain.r(i), chain.q(i), chain.type(i) == "call", fns, o.Tol);
    end

    res = table(chain.expiry, chain.tau, chain.type, chain.strike, chain.mid, chain.F, ...
        log(chain.strike ./ chain.F), iv, bis, ...
        'VariableNames', {'expiry','tau','type','strike','mid','F','k','iv_matlab','used_bisection'});

    fprintf('  solved: %d, failed (NaN): %d, needed bisection fallback: %d\n', ...
        nnz(isfinite(iv)), nnz(~isfinite(iv)), nnz(bis));
    fprintf('  forward source: %d parity / %d model fallback rows\n', ...
        nnz(chain.fwd_src == "parity"), nnz(chain.fwd_src == "model"));

    % ---- compare against reference IV, if the CSV has one ------------------
    ref = lower(string(o.RefColumn));
    hasRef = ismember(ref, string(chain.Properties.VariableNames));
    if hasRef
        res.iv_ref = chain.(ref);
        res.diff = res.iv_matlab - res.iv_ref;
        d = abs(res.diff(isfinite(res.diff)));
        if isempty(d)
            fprintf('  no rows with both MATLAB and reference IV.\n');
        else
            fprintf('  |MATLAB - %s| over %d rows (raw volatility units):\n', ref, numel(d));
            fprintf('    median %.2e   95th pct %.2e   max %.2e\n', ...
                median(d), prctile(d, 95), max(d));
        end
    else
        fprintf('  (no "%s" column - skipping cross-validation)\n', ref);
    end

    if o.Plot, plot_results(res, hasRef); end
end

function plot_results(res, hasRef)
    ex = unique(res.expiry);
    figure('Name', 'Implied vol smiles', 'Color', 'w'); hold on
    for i = 1:numel(ex)
        m = res.expiry == ex(i) & isfinite(res.iv_matlab);
        [kk, ord] = sort(res.k(m));  v = res.iv_matlab(m);  v = v(ord);
        plot(kk, v, '-o', 'DisplayName', char(ex(i)));
    end
    xlabel('log-moneyness  ln(K/F)'); ylabel('implied volatility');
    title('MATLAB implied vol smile by expiry'); legend('Location', 'best'); grid on

    if hasRef
        figure('Name', 'MATLAB vs reference IV', 'Color', 'w');
        ok = isfinite(res.diff);
        scatter(res.k(ok), res.diff(ok), 18, 'filled');
        yline(0, 'k-');
        xlabel('log-moneyness  ln(K/F)'); ylabel('iv\_matlab - iv\_ref');
        title('Cross-validation residuals'); grid on
    end
end
