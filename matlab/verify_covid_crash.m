function out = verify_covid_crash(opts)
%VERIFY_COVID_CRASH Visual verification on the March 2020 volatility panic.
%   verify_covid_crash
%   out = verify_covid_crash("SavePng", "docs/images/covid_verification.png")
%
%   WHAT IT DOES
%   Plants a stylized surface for two days (calm 19 Feb 2020, panic 16 Mar 2020),
%   turns it into option prices with the Black-Scholes formula, feeds those prices
%   through the SAME pipeline used for live tickers (run_vol_checks -> build_surface)
%   and shows that the tool recovers the planted surface, including at strikes and
%   maturities it was never given. Because the true answer is known, any gap is the
%   tool's own error. The figure then reads the recovered surface as a story.
%
%   WHY THIS DAY
%   16 Mar 2020: the S&P 500 fell about 12% in one session (approx.) and the VIX
%   closed at 82.69, its record closing high. Fear about the next month was
%   extreme while the one-year outlook stayed far calmer, so the term structure
%   turned upside down and puts became much more expensive than calls.
%
%   HONESTY NOTE
%   Free historical option chains do not exist, so this is a STYLIZED reconstruction.
%   One number is documented (VIX close 82.69); the long-run level, skew and
%   curvature are illustrative choices that reproduce the known shape. It is a test
%   of the tool, not market data. With a real historical chain (e.g. OptionMetrics),
%   run_vol_checks and build_surface accept it unchanged.
%
%   Output struct: results (pass/fail table), allPassed, metrics, figure.

    arguments
        opts.SavePng (1,1) string = ""
    end

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    fns = bs_symbolic();

    cases = [calmCase(), panicCase()];
    nC = numel(cases);
    R = struct('res', cell(1, nC), 's', [], 'rec', [], 'truth', [], 'm', [], 'eQuote', [], 'nQuote', []);
    T30 = 30 / 365.25;
    T350 = 350 / 365.25;

    for i = 1:nC
        c = cases(i);
        fprintf('\n--- %s ---\n', c.label);
        csv = [tempname '.csv'];
        cleanup = onCleanup(@() deleteIfExists(csv)); %#ok<NASGU>
        writeChain(csv, fns, c);

        res = run_vol_checks(csv, 'Plot', false, 'Verbose', false);
        s = build_surface(res);

        % ---- unseen points: inside every expiry's strike range, between expiries ----
        [g, ~] = findgroups(res.expiry);
        kLo = max(splitapply(@min, res.k, g));
        kHi = min(splitapply(@max, res.k, g));
        rng(1);
        kq = kLo + 0.01 + (kHi - kLo - 0.02) * rand(600, 1);
        tq = (16 + 344 * rand(600, 1)) / 365.25;
        truth = truthVol(c, kq, tq);
        rec = s.F(kq, tq);

        % ---- what the recovered surface says (the story numbers) ----
        m.atm30 = s.F(0, T30);
        m.atm350 = s.F(0, T350);
        m.inversion = m.atm30 / m.atm350;
        m.skew = s.F(-0.05, T30) - s.F(0.05, T30);          % 5% below vs 5% above
        m.move = m.atm30 * sqrt(T30);                       % one-sigma one-month move

        R(i).res = res;  R(i).s = s;  R(i).rec = rec;  R(i).truth = truth;  R(i).m = m;
        R(i).eQuote = max(abs(res.diff(isfinite(res.diff))));
        R(i).nQuote = height(res);
    end

    % ---- verification table -------------------------------------------------
    rows = cell(0, 4);
    for i = 1:nC
        c = cases(i);  r = R(i);
        e = abs(r.rec - r.truth);
        rows = addRow(rows, c.short + ": recovers every quoted price", r.eQuote < 1e-5, ...
            sprintf('%d contracts, worst miss %.1e', r.nQuote, r.eQuote), "< 1e-5");
        rows = addRow(rows, c.short + ": accurate at 600 unseen points", all(isfinite(e)) && max(e) < 0.02, ...
            sprintf('worst miss %.2f vol points, typical %.2f', 100*max(e), 100*median(e)), "< 2 vol points");
    end
    rows = addRow(rows, "Calm: curve slopes UP (normal times)", R(1).m.inversion < 1, ...
        sprintf('1-month / 1-year = %.2f', R(1).m.inversion), "< 1");
    rows = addRow(rows, "Panic: curve flips DOWN (inverted)", R(2).m.inversion > 1, ...
        sprintf('1-month / 1-year = %.2f', R(2).m.inversion), "> 1");
    rows = addRow(rows, "Puts dearer than calls in both", R(1).m.skew > 0 && R(2).m.skew > 0, ...
        sprintf('gap %.0f (calm), %.0f (panic) vol points', 100*R(1).m.skew, 100*R(2).m.skew), "> 0");

    results = cell2table(rows, 'VariableNames', {'Check', 'Passed', 'Measured', 'Requirement'});
    allPassed = all(results.Passed);
    fprintf('\n=========== HISTORICAL VERIFICATION REPORT ===========\n');
    for i = 1:height(results)
        tag = "FAIL";  if results.Passed(i), tag = "PASS"; end
        fprintf('[%s] %-40s %s   (need %s)\n', tag, results.Check(i), results.Measured(i), results.Requirement(i));
    end
    fprintf('------------------------------------------------------\n');
    if allPassed, fprintf('ALL %d CHECKS PASSED\n\n', height(results));
    else, fprintf('%d of %d CHECKS FAILED\n\n', nnz(~results.Passed), height(results)); end

    % ---- figure -----------------------------------------------------------------
    col = [0.10 0.40 0.80; 0.85 0.15 0.10];                 % calm blue, panic red
    zmax = 10 * ceil(10 * max(arrayfun(@(r) max(r.s.ivGrid, [], 'all', 'omitnan'), R)));

    fig = figure('Name', 'Verification: March 2020 volatility panic', 'Color', 'w', ...
        'Position', [40 40 1500 880]);
    tl = tiledlayout(fig, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, {'The tool, tested on the March 2020 volatility panic', ...
        'Same axes and colour scale on both surfaces so they can be compared honestly'}, 'FontWeight', 'bold');

    for i = 1:nC
        ax = nexttile(tl, i);
        s = R(i).s;  res = R(i).res;
        surf(ax, s.kGrid, s.tauGrid * 365.25, 100 * s.ivGrid, 'EdgeAlpha', 0.15);
        hold(ax, 'on');
        scatter3(ax, res.k, res.tau * 365.25, 100 * res.iv_matlab, 10, 'k', 'filled');
        hold(ax, 'off');
        zlim(ax, [0 zmax]);  setColorLimits(ax, [0 zmax]);  view(ax, [-40 28]);  grid(ax, 'on');
        xlabel(ax, 'strike vs forward  ln(K/F)'); ylabel(ax, 'days to expiry');
        zlabel(ax, 'implied volatility (%)');
        title(ax, cases(i).label, 'Color', col(i, :));
    end
    colorbar(ax);

    % story panel
    ax = nexttile(tl, 3);  axis(ax, 'off');
    story = {
        "THE STORY IN FOUR LINES"
        ""
        "16 Mar 2020: the S&P 500 fell about 12% in one day (approx.) and the VIX closed at 82.69, a record."
        ""
        sprintf('1. FEAR NOW. One-month volatility of %.0f%% means the market priced a typical move of about +/-%.0f%% in a month. In calm February it priced +/-%.0f%%.', ...
            100*R(2).m.atm30, 100*R(2).m.move, 100*R(1).m.move)
        ""
        sprintf('2. CALM LATER. One-year volatility was only %.0f%%, so one month cost %.1fx as much as one year. In calm times it was %.1fx. The curve flipped upside down.', ...
            100*R(2).m.atm350, R(2).m.inversion, R(1).m.inversion)
        ""
        sprintf('3. INSURANCE COSTS EXTRA. Puts 5%% below the forward priced %.0f volatility points above calls 5%% above (calm: %.0f).', ...
            100*R(2).m.skew, 100*R(1).m.skew)
        ""
        "4. HOW TO READ IT. Height is how stormy the market expects each strike and date to be. Panic is a tall, tilted wall at the front."
        };
    lines = {};
    for j = 1:numel(story)
        if strlength(story{j}) == 0, lines{end+1} = ''; %#ok<AGROW>
        else, lines = [lines, wrapText(story{j}, 60)]; end %#ok<AGROW>
    end
    text(ax, 0, 1, lines, 'Units', 'normalized', 'VerticalAlignment', 'top', 'FontSize', 10.5);
    text(ax, 0, 0.0, wrapText(['Stylized reconstruction. Only the VIX close (82.69) is documented; ' ...
        'the long-run level, skew and curvature are illustrative. A test of the tool, not market data.'], 66), ...
        'Units', 'normalized', 'VerticalAlignment', 'bottom', 'FontSize', 9, 'Color', [0.4 0.4 0.4]);

    % 30-day smile, planted vs recovered
    ax = nexttile(tl, 4);  hold(ax, 'on');
    hs = gobjects(1, 2 * nC);
    for i = 1:nC
        res = R(i).res;  s = R(i).s;
        sel = abs(res.tau - T30) < 1e-9;
        kk = linspace(min(res.k(sel)), max(res.k(sel)), 80)';
        hs(2*i-1) = plot(ax, kk, 100 * truthVol(cases(i), kk, T30), '-', 'Color', col(i, :), 'LineWidth', 2.5);
        hs(2*i) = plot(ax, kk, 100 * s.F(kk, T30 * ones(size(kk))), 'k--', 'LineWidth', 1.2);
        scatter(ax, res.k(sel), 100 * res.iv_matlab(sel), 22, col(i, :), 'filled');
    end
    hold(ax, 'off');  grid(ax, 'on');
    xlabel(ax, 'strike vs forward  ln(K/F)  (left = puts, right = calls)'); ylabel(ax, 'implied volatility (%)');
    title(ax, '30-day smile: planted truth vs what the tool recovered');
    legend(ax, hs([1 3 2]), {'calm: planted', 'panic: planted', 'recovered by the tool'}, 'Location', 'north');

    % term structure
    ax = nexttile(tl, 5);  hold(ax, 'on');
    for i = 1:nC
        ts = term_structure_slice(R(i).s, 0);
        plot(ax, ts.days, 100 * truthVol(cases(i), 0, ts.tau), '-', 'Color', col(i, :), 'LineWidth', 2.5);
        plot(ax, ts.days, 100 * ts.iv, 'k--', 'LineWidth', 1.2);
    end
    hold(ax, 'off');  grid(ax, 'on');  xline(ax, 30, ':', '30 days');
    xlabel(ax, 'days to expiry'); ylabel(ax, 'at-the-forward volatility (%)');
    title(ax, 'Term structure: calm slopes up, panic slopes down');

    % verification scatter
    ax = nexttile(tl, 6);  hold(ax, 'on');
    lim = 0;
    for i = 1:nC
        plot(ax, 100 * R(i).truth, 100 * R(i).rec, '.', 'Color', col(i, :), 'MarkerSize', 9);
        lim = max(lim, 100 * max(R(i).truth));
    end
    lim = 10 * ceil(lim / 10);
    plot(ax, [0 lim], [0 lim], 'k:');  hold(ax, 'off');
    axis(ax, 'square');  xlim(ax, [0 lim]);  ylim(ax, [0 lim]);  grid(ax, 'on');
    xlabel(ax, 'planted (true) volatility, %'); ylabel(ax, 'recovered by the tool, %');
    title(ax, sprintf('Verification: 1200 points the tool never saw (worst miss %.1f vol pts)', ...
        100 * max(arrayfun(@(r) max(abs(r.rec - r.truth)), R))));

    if opts.SavePng ~= ""
        drawnow;
        exportgraphics(fig, opts.SavePng, 'Resolution', 200);
        fprintf('Saved figure to %s\n', opts.SavePng);
    end

    out = struct('results', results, 'allPassed', allPassed, ...
                 'metrics', [R.m], 'figure', fig);
end

% =============================== cases ======================================

function c = calmCase()
% 19 Feb 2020, the pre-crash peak: calm, upward-sloping term structure.
    c = struct('label', 'Calm: 19 Feb 2020 (stylized)', 'short', "Calm", ...
        'S', 100, 'r', 0.015, 'q', 0.02, ...
        'atm30', 0.14, 'longVol', 0.19, 'tau', 0.30, 'skew30', -1.1, 'curv', 2.0);
end

function c = panicCase()
% 16 Mar 2020: 1-month at-the-forward volatility anchored to the VIX close of 82.69%.
    c = struct('label', 'Panic: 16 Mar 2020 (stylized)', 'short', "Panic", ...
        'S', 100, 'r', 0.0025, 'q', 0.02, ...
        'atm30', 0.827, 'longVol', 0.40, 'tau', 0.30, 'skew30', -0.9, 'curv', 1.2);
end

function v = truthVol(c, k, T)
% The planted surface: at-the-forward level decays from short-dated to long-run
% level; the skew (tilt) is steepest at short maturities and fades with time.
    T30 = 30 / 365.25;
    b = c.longVol + (c.atm30 - c.longVol) / exp(-T30 / c.tau);
    atm = c.longVol + (b - c.longVol) .* exp(-T ./ c.tau);
    v = atm + c.skew30 * (T30 ./ T).^0.4 .* k + c.curv * k.^2;
end

function writeChain(path, fns, c)
% Option prices generated from the planted surface, in the standard snapshot format.
    rows = {};
    for d = [14 30 45 60 91 120 182 273 365]
        T = d / 365.25;
        F = c.S * exp((c.r - c.q) * T);
        m = 3.5 * truthVol(c, 0, T) * sqrt(T);               % about 3.5 standard deviations wide
        ks = linspace(-min(0.45, m), min(0.25, 0.7 * m), 15);
        ex = string(datetime('2030-01-01') + days(round(T * 365.25)));
        for K = unique(round(F * exp(ks) * 2) / 2)
            sg = truthVol(c, log(K / F), T);
            cp = fns.call(c.S, K, T, c.r, c.q, sg);
            pp = fns.put(c.S, K, T, c.r, c.q, sg);
            rows(end+1, :) = {"SYN", c.S, ex, T, c.r, c.q, "call", K, cp, sg}; %#ok<AGROW>
            rows(end+1, :) = {"SYN", c.S, ex, T, c.r, c.q, "put",  K, pp, sg}; %#ok<AGROW>
        end
    end
    tbl = cell2table(rows, 'VariableNames', ...
        {'symbol', 'spot', 'expiry', 'T', 'r', 'q', 'type', 'strike', 'mid', 'iv_ocaml'});
    writetable(tbl, path);
end

% =============================== helpers ====================================

function rows = addRow(rows, name, pass, measured, requirement)
    rows(end+1, :) = {string(name), logical(pass), string(measured), string(requirement)};
end

function deleteIfExists(p)
    if isfile(p), delete(p); end
end

function setColorLimits(ax, lims)
    if exist('clim', 'file') == 2 || exist('clim', 'builtin') == 5
        clim(ax, lims);
    else
        caxis(ax, lims); %#ok<CAXIS>
    end
end

function lines = wrapText(str, width)
    words = strsplit(char(str), ' ');
    lines = {};  cur = '';
    for i = 1:numel(words)
        if isempty(cur), cand = words{i}; else, cand = [cur ' ' words{i}]; end
        if numel(cand) > width && ~isempty(cur)
            lines{end+1} = cur;  cur = words{i}; %#ok<AGROW>
        else
            cur = cand;
        end
    end
    if ~isempty(cur), lines{end+1} = cur; end
end
