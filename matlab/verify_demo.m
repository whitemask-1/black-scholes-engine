function [results, allPassed] = verify_demo(snapshot, opts)
%VERIFY_DEMO One-command verification report: does the pipeline give the right answers?
%   verify_demo                          offline checks only (no data needed)
%   verify_demo("snapshots/AAPL_20261012_1347.csv")   also check a real snapshot
%                                         against the OCaml engine's volatilities
%   [results, ok] = verify_demo(...)     results table and overall pass/fail
%
%   Every check compares the code with an answer known in advance:
%     1  textbook prices      a worked example whose answer is fixed by the formula
%     2  symbolic identities  Black-Scholes PDE and put-call parity hold exactly
%     3  round trip           price -> implied vol recovers the volatility put in
%     4  impossible prices    prices that break no-arbitrage give NaN, not nonsense
%     5  planted smile        a chain built from a KNOWN smile is recovered by the pipeline
%     6  surface accuracy     the interpolated surface matches the truth at points it never saw
%     7  real snapshot        (optional) agreement with the independent OCaml engine
%
%   The reference numbers in check 1 were computed independently with SciPy.
%   Option "Plot" (default true) draws the planted smile against the recovered one.

    arguments
        snapshot (1,1) string = ""
        opts.Plot (1,1) logical = true
    end

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    rows = cell(0, 4);                      % check, pass, measured, requirement
    fns = bs_symbolic();

    % ---- 1. textbook prices ------------------------------------------------
    % S = K = 100, T = 1 year, r = 5%, no dividends, volatility 20%.
    ref = struct('call', 10.450584, 'put', 5.573526, 'vega', 37.524035);
    got = [fns.call(100,100,1,0.05,0,0.2), fns.put(100,100,1,0.05,0,0.2), fns.vega(100,100,1,0.05,0,0.2)];
    err = max(abs(got - [ref.call ref.put ref.vega]));
    rows = addRow(rows, "Textbook call, put and vega", err < 1e-5, ...
        sprintf('call %.6f, put %.6f, vega %.6f (worst miss %.1e)', got, err), "miss < 1e-5");

    % ---- 2. symbolic identities --------------------------------------------
    rows = addRow(rows, "Black-Scholes PDE holds", fns.check.pde_numeric_maxabs < 1e-8, ...
        sprintf('largest residual %.1e', fns.check.pde_numeric_maxabs), "< 1e-8");
    rows = addRow(rows, "Put-call parity holds", fns.check.parity_numeric_maxabs < 1e-8, ...
        sprintf('largest residual %.1e', fns.check.parity_numeric_maxabs), "< 1e-8");

    % ---- 3. round trip -------------------------------------------------------
    worst = 0;  n = 0;
    for sg = [0.1 0.2 0.35 0.6]
        for K = [90 100 110]
            for isCall = [true false]
                if isCall, px = fns.call(100,K,0.5,0.04,0.01,sg); else, px = fns.put(100,K,0.5,0.04,0.01,sg); end
                iv = implied_vol(px, 100, K, 0.5, 0.04, 0.01, isCall, fns);
                worst = max(worst, abs(iv - sg));  n = n + 1;
            end
        end
    end
    rows = addRow(rows, "Price to volatility round trip", worst < 1e-6, ...
        sprintf('%d cases, worst error %.1e', n, worst), "< 1e-6");

    % ---- 4. impossible prices ------------------------------------------------
    below = implied_vol(0.01, 100, 70, 1, 0.04, 0, true, fns);     % call worth less than intrinsic
    above = implied_vol(500,  100, 100, 1, 0.04, 0, true, fns);    % call worth more than the stock
    rows = addRow(rows, "Impossible prices return NaN", isnan(below) && isnan(above), ...
        "both rejected", "NaN for both");

    % ---- 5./6. planted smile -------------------------------------------------
    S0 = 237.5;  r0 = 0.045;
    smileTrue = @(x) 0.25 + 0.6*x.^2 - 0.15*x;          % x = ln(K/S), the truth we plant
    csv = [tempname '.csv'];
    cleanup = onCleanup(@() deleteIfExists(csv));
    writePlantedChain(csv, fns, S0, r0, smileTrue);
    res = run_vol_checks(csv, 'Plot', false, 'Verbose', false);
    d = abs(res.diff(isfinite(res.diff)));
    rows = addRow(rows, "Planted smile recovered at quoted strikes", ~isempty(d) && max(d) < 1e-5, ...
        sprintf('%d contracts, worst error %.1e', numel(d), max(d)), "< 1e-5");

    s = build_surface(res);
    rng(1);
    kq = -0.12 + 0.24 * rand(400, 1);                    % never-quoted strikes ...
    tq = (30 + 90 * rand(400, 1)) / 365.25;              % ... and never-quoted maturities
    truth = smileTrue(kq + r0 * tq);                     % k = ln(K/F) = ln(K/S) - r*T here
    e = abs(s.F(kq, tq) - truth);
    rows = addRow(rows, "Surface accurate at points it never saw", all(isfinite(e)) && max(e) < 5e-3, ...
        sprintf('400 points, worst error %.1e (%.2f vol points)', max(e), 100*max(e)), "< 5e-3");

    % ---- 7. optional real snapshot --------------------------------------------
    if snapshot ~= ""
        snap = run_vol_checks(snapshot, 'Plot', false, 'Verbose', false);
        if ismember('diff', snap.Properties.VariableNames)
            dd = abs(snap.diff(isfinite(snap.diff)));
            frac = nnz(isfinite(snap.iv_matlab)) / height(snap);
            rows = addRow(rows, "Real snapshot vs OCaml engine", max(dd) < 1e-6 && frac > 0.99, ...
                sprintf('%d contracts, median %.1e, max %.1e, solved %.0f%%', numel(dd), median(dd), max(dd), 100*frac), ...
                "max < 1e-6 (OCaml prints 6 decimals)");
        else
            rows = addRow(rows, "Real snapshot vs OCaml engine", false, "no iv_ocaml column in the file", "needs a reference column");
        end
    end

    % ---- report -------------------------------------------------------------
    results = cell2table(rows, 'VariableNames', {'Check', 'Passed', 'Measured', 'Requirement'});
    allPassed = all(results.Passed);
    fprintf('\n=========== VERIFICATION REPORT ===========\n');
    for i = 1:height(results)
        tag = "FAIL";  if results.Passed(i), tag = "PASS"; end
        fprintf('[%s] %-42s %s   (need %s)\n', tag, results.Check(i), results.Measured(i), results.Requirement(i));
    end
    fprintf('-------------------------------------------\n');
    if allPassed
        fprintf('ALL %d CHECKS PASSED\n\n', height(results));
    else
        fprintf('%d of %d CHECKS FAILED\n\n', nnz(~results.Passed), height(results));
    end

    if opts.Plot
        t90 = 90 / 365.25;
        kk = linspace(-0.12, 0.12, 80)';
        fig = figure('Name', 'Verification: planted vs recovered smile', 'Color', 'w', 'Position', [100 100 900 420]);
        tl = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact');
        ax = nexttile(tl);
        plot(ax, kk, smileTrue(kk + r0*t90), 'k-', 'LineWidth', 2); hold(ax, 'on');
        plot(ax, kk, s.F(kk, t90 * ones(size(kk))), 'r--', 'LineWidth', 1.5); hold(ax, 'off');
        xlabel(ax, 'log-moneyness  ln(K/F)'); ylabel(ax, 'implied volatility'); grid(ax, 'on');
        legend(ax, {'planted truth', 'recovered by the tool'}, 'Location', 'north');
        title(ax, '90-day smile (a maturity that was never quoted)');
        ax = nexttile(tl);
        plot(ax, kk, 1e4 * (s.F(kk, t90 * ones(size(kk))) - smileTrue(kk + r0*t90)), 'LineWidth', 1.5);
        yline(ax, 0, ':'); grid(ax, 'on');
        xlabel(ax, 'log-moneyness  ln(K/F)'); ylabel(ax, 'error (basis points of volatility)');
        title(ax, 'Recovery error');
    end
end

% =============================== helpers ====================================

function rows = addRow(rows, name, pass, measured, requirement)
    rows(end+1, :) = {string(name), logical(pass), string(measured), string(requirement)};
end

function deleteIfExists(p)
    if isfile(p), delete(p); end
end

function writePlantedChain(path, fns, S, r, smileTrue)
% A chain whose volatilities are known exactly: prices come from the planted smile.
    rows = {};
    for T = [30 60 120] / 365.25
        for K = round(S * (0.85:0.025:1.15))
            sg = smileTrue(log(K / S));
            cp = fns.call(S, K, T, r, 0, sg);  pp = fns.put(S, K, T, r, 0, sg);
            ex = string(datetime('2030-01-01') + days(round(T * 365.25)));
            rows(end+1, :) = {"SYN", S, ex, T, r, 0, "call", K, cp, sg}; %#ok<AGROW>
            rows(end+1, :) = {"SYN", S, ex, T, r, 0, "put",  K, pp, sg}; %#ok<AGROW>
        end
    end
    tbl = cell2table(rows, 'VariableNames', ...
        {'symbol', 'spot', 'expiry', 'T', 'r', 'q', 'type', 'strike', 'mid', 'iv_ocaml'});
    writetable(tbl, path);
end
