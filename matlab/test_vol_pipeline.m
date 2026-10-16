function test_vol_pipeline()
%TEST_VOL_PIPELINE Self-contained checks - no market data or network needed.
%   Run from the matlab/ folder:  test_vol_pipeline
%   Builds synthetic chains with KNOWN volatilities, so every result can be
%   checked exactly, then also exercises input validation.

    fns = bs_symbolic();
    assert(fns.check.pde_numeric_maxabs    < 1e-8, 'BS PDE residual too large');
    assert(fns.check.parity_numeric_maxabs < 1e-8, 'Put-call parity residual too large');
    fprintf('[ok] symbolic PDE + parity checks (symbolic proof: pde=%d parity=%d)\n', ...
        fns.check.pde_symbolic, fns.check.parity_symbolic);

    % ---- 1. IV round trip on a grid ---------------------------------------
    S = 100; r = 0.04; q = 0.01; worst = 0; nTested = 0; nSkipped = 0;
    for T = [0.05 0.25 1 2]
        for K = [70 90 100 110 130]
            for sg = [0.08 0.2 0.5 1.2]
                for isCall = [true false]
                    if isCall, px = fns.call(S,K,T,r,q,sg); else, px = fns.put(S,K,T,r,q,sg); end
                    % Skip cases where the price barely depends on sigma (deep ITM / far OTM
                    % short-dated): there IV is not identifiable from the price, so a
                    % round trip can't recover it. Error is roughly price_tol / vega.
                    if fns.vega(S,K,T,r,q,sg) < 1e-2, nSkipped = nSkipped + 1; continue, end
                    iv = implied_vol(px, S, K, T, r, q, isCall, fns);
                    worst = max(worst, abs(iv - sg));  nTested = nTested + 1;
                end
            end
        end
    end
    assert(worst < 1e-5, 'IV round trip error %.2e', worst);
    fprintf('[ok] IV round trip: %d cases (%d skipped, vega ~ 0), worst error %.2e\n', nTested, nSkipped, worst);

    % ---- 2. no-arbitrage violation returns NaN ----------------------------
    assert(isnan(implied_vol(0.01, 100, 70, 1, 0.04, 0, true, fns)), 'below intrinsic should be NaN');
    assert(isnan(implied_vol(500,  100, 100, 1, 0.04, 0, true, fns)), 'above spot should be NaN');
    fprintf('[ok] arbitrage-violating prices return NaN\n');

    % ---- 3. end to end on a synthetic CSV, different ticker/spot ----------
    csv = [tempname '.csv'];
    cleanup = onCleanup(@() delete(csv));
    writeSyntheticChain(csv, fns, 237.5, 0.045);
    res = run_vol_checks(csv, 'Plot', false);
    d = abs(res.diff(isfinite(res.diff)));
    assert(~isempty(d) && max(d) < 1e-5, 'end-to-end IV mismatch %.2e', max(d));
    fprintf('[ok] end-to-end on synthetic CSV: %d rows, max diff %.2e\n', numel(d), max(d));

    % ---- 4. validation errors ---------------------------------------------
    bad = [tempname '.csv'];  c2 = onCleanup(@() delete(bad));
    writetable(table(1, "2030-01-01", 'VariableNames', {'spot','expiry'}), bad);
    try
        load_chain(bad);  error('test:noError', 'expected load_chain to reject the file');
    catch err
        assert(strcmp(err.identifier, 'load_chain:missingColumns'), 'wrong error: %s', err.identifier);
    end
    fprintf('[ok] missing-column CSV rejected with a clear error\n');

    fprintf('\nAll checks passed.\n');
end

function writeSyntheticChain(path, fns, S, r)
    rows = {};
    for T = [30 60 120] / 365.25
        ks = round(S * (0.85:0.025:1.15));
        for K = ks
            sg = 0.25 + 0.6*(log(K/S))^2 - 0.15*log(K/S);     % a smile with skew
            cp = fns.call(S, K, T, r, 0, sg);  pp = fns.put(S, K, T, r, 0, sg);
            exp_ = string(datetime('2030-01-01') + days(round(T*365.25)));
            rows(end+1,:) = {"SYN", S, exp_, T, r, 0, "call", K, cp, sg}; %#ok<AGROW>
            rows(end+1,:) = {"SYN", S, exp_, T, r, 0, "put",  K, pp, sg}; %#ok<AGROW>
        end
    end
    tbl = cell2table(rows, 'VariableNames', ...
        {'symbol','spot','expiry','T','r','q','type','strike','mid','iv_ocaml'});
    writetable(tbl, path);
end
