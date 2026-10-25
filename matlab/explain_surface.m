function fig = explain_surface(out)
%EXPLAIN_SURFACE Second figure: a plain-English guide to reading the volatility surface.
%   explain_surface(out)        out = the struct returned by vol_surface
%   vol_surface("AAPL")         opens this automatically (turn off with "Explain", false)
%
%   Six panels, each a question, a picture drawn from THIS ticker's data, and a short
%   caption. No prior knowledge of options is assumed:
%     1 What is an option?          2 What is volatility?      3 What is implied volatility?
%     4 What is the smile?          5 What is the term structure?   6 The whole surface from above

    arguments
        out (1,1) struct
    end

    S0 = out.chain.spot(1);
    r  = out.chain.r(1);
    q  = 0;
    if ismember('q', out.chain.Properties.VariableNames), q = out.chain.q(1); end
    sl = out.smile;  ts = out.term;  s = out.surface;
    T  = sl.tau;                                   % years, for the highlighted expiry

    ivAt  = @(k) smileAt(sl, k);
    atm   = ivAt(0);
    if ~isfinite(atm), atm = median(sl.ivMarket, 'omitnan'); end
    prem  = bsCall(S0, S0, T, r, q, atm);          % price of an at-the-money call

    fig = figure('Name', "How to read the surface - " + out.ticker, 'Color', 'w', ...
        'Position', [60 40 1400 980]);
    tl = tiledlayout(fig, 8, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

    lo = ivAt(-0.1);  hi = ivAt(0.1);
    line2 = sprintf('For the %s expiry the market prices %s at about %.0f%% volatility at today''s price', ...
        sl.expiry, out.ticker, 100 * atm);
    if isfinite(lo) && isfinite(hi)
        line2 = sprintf('%s, %.0f%% for strikes about 10%% below, and %.0f%% for strikes about 10%% above.', ...
            line2, 100 * lo, 100 * hi);
    else
        line2 = line2 + ".";
    end
    title(tl, {sprintf('How to read the %s volatility surface   (stock price $%.2f)', out.ticker, S0), line2}, ...
        'FontWeight', 'bold');

    % ---- 1. what is an option ------------------------------------------------
    ax = nexttile(tl, 1, [3 1]);
    ST = linspace(0.8 * S0, 1.2 * S0, 200);
    pay = max(ST - S0, 0) - prem;
    fill(ax, [ST fliplr(ST)], [max(pay, 0) zeros(size(ST))], [0.7 0.9 0.7], 'EdgeColor', 'none'); hold(ax, 'on');
    fill(ax, [ST fliplr(ST)], [min(pay, 0) zeros(size(ST))], [0.95 0.75 0.75], 'EdgeColor', 'none');
    plot(ax, ST, pay, 'k', 'LineWidth', 2);
    xline(ax, S0, ':'); yline(ax, 0, '-', 'Color', [0.5 0.5 0.5]); hold(ax, 'off');
    xlabel(ax, 'stock price on the expiry day ($)'); ylabel(ax, 'your profit per share ($)');
    title(ax, '1. What is an option?'); grid(ax, 'on');
    text(ax, 0.05, 0.12, 'lose the fee', 'Units', 'normalized', 'Color', [0.7 0.2 0.2]);
    text(ax, 0.72, 0.92, 'profit', 'Units', 'normalized', 'Color', [0.2 0.5 0.2]);
    caption(tl, 10, ['A call option is a ticket to buy the stock at a fixed price (the strike, here $' ...
        sprintf('%.0f', S0) ') on a set future date. You pay a fee up front. If the stock ends below the ' ...
        'strike the ticket is worthless and you lose the fee; above it, you profit. The surface is built from ' ...
        'the market prices of thousands of these tickets.']);

    % ---- 2. what is volatility -----------------------------------------------
    ax = nexttile(tl, 2, [3 1]);
    t = linspace(0, T, 60);  d = t * 365.25;
    wild = 2 * atm;
    fill(ax, [d fliplr(d)], [S0 * exp(wild * sqrt(t)) fliplr(S0 * exp(-wild * sqrt(t)))], ...
        [1 0.8 0.5], 'EdgeColor', 'none'); hold(ax, 'on');
    fill(ax, [d fliplr(d)], [S0 * exp(atm * sqrt(t)) fliplr(S0 * exp(-atm * sqrt(t)))], ...
        [0.6 0.75 1], 'EdgeColor', 'none');
    yline(ax, S0, 'k:'); hold(ax, 'off');
    xlabel(ax, 'days from today'); ylabel(ax, 'plausible stock price ($)');
    title(ax, '2. What is volatility?'); grid(ax, 'on');
    legend(ax, {sprintf('wilder stock (%.0f%%)', 100 * wild), sprintf('this stock (%.0f%%)', 100 * atm)}, ...
        'Location', 'northwest');
    caption(tl, 11, ['Volatility measures how widely a stock''s price tends to swing. A volatility of 30% ' ...
        'means a typical year moves the price by roughly plus or minus 30%. The shaded cone is the likely range ' ...
        'of future prices: a calm stock (blue) stays narrow, a wild one (orange) spreads out. A wider cone ' ...
        'means a bigger chance the ticket pays off, so a higher price.']);

    % ---- 3. implied volatility -----------------------------------------------
    ax = nexttile(tl, 3, [3 1]);
    sg = linspace(0.02, max(0.8, 2.5 * atm), 200);
    plot(ax, 100 * sg, bsCall(S0, S0, T, r, q, sg), 'LineWidth', 2); hold(ax, 'on');
    plot(ax, [0 100 * atm 100 * atm], [prem prem 0], 'k:');
    plot(ax, 100 * atm, prem, 'ro', 'MarkerFaceColor', 'r'); hold(ax, 'off');
    xlabel(ax, 'volatility (%)'); ylabel(ax, 'price of the call ($)');
    title(ax, '3. What is IMPLIED volatility?'); grid(ax, 'on');
    text(ax, 100 * atm, prem, sprintf('  price $%.2f\n  -> %.0f%%', prem, 100 * atm), ...
        'VerticalAlignment', 'top', 'Color', 'r');
    caption(tl, 12, ['Nobody observes volatility directly, but option prices are posted on screen. ' ...
        'Implied volatility works backward: it is the volatility that makes the Black-Scholes formula ' ...
        'return that exact market price. Price rises steadily with volatility, so each price gives one answer. ' ...
        'Read it as the market''s forecast of how bumpy the stock will be.']);

    % ---- 4. the smile --------------------------------------------------------
    ax = nexttile(tl, 13, [3 1]);
    plot(ax, sl.k, 100 * sl.iv, 'LineWidth', 2); hold(ax, 'on');
    scatter(ax, sl.kMarket, 100 * sl.ivMarket, 28, 'k', 'filled');
    yline(ax, 100 * atm, ':'); hold(ax, 'off');
    pctTicks(ax);
    xlabel(ax, 'strike compared with today''s price'); ylabel(ax, 'implied volatility (%)');
    title(ax, sprintf('4. The smile (%s expiry)', sl.expiry)); grid(ax, 'on');
    legend(ax, {'fitted surface', 'market quotes', 'at-the-money level'}, 'Location', 'best');
    caption(tl, 22, ['If the Black-Scholes model were exactly right, every strike would show the same ' ...
        'volatility (a flat line). Real markets curve: traders pay extra for strikes far from today''s price, ' ...
        'and usually most on the downside, because those protect against a crash. This curve is called the ' ...
        'smile (or skew). Dots are real quotes.']);

    % ---- 5. term structure ---------------------------------------------------
    ax = nexttile(tl, 14, [3 1]);
    plot(ax, ts.days, 100 * ts.iv, 'LineWidth', 2);
    xlabel(ax, 'days until the option expires'); ylabel(ax, 'implied volatility (%)');
    title(ax, '5. The term structure'); grid(ax, 'on');
    caption(tl, 23, ['The same idea across time instead of strikes: how volatile the market expects the ' ...
        'stock to be over short versus long horizons, always at today''s price. An upward slope means calm ' ...
        'now, more turbulence expected later. A downward slope or a bump means traders expect a specific event ' ...
        'soon, such as an earnings report.']);

    % ---- 6. the whole surface from above -------------------------------------
    ax = nexttile(tl, 15, [3 1]);
    contourf(ax, s.kGrid, s.tauGrid * 365.25, 100 * s.ivGrid, 20, 'LineStyle', 'none'); hold(ax, 'on');
    xline(ax, 0, 'w--', 'LineWidth', 1.5);
    yline(ax, T * 365.25, 'w--', 'LineWidth', 1.5);
    text(ax, 0, max(s.tauGrid) * 365.25, ' 5 ', 'Color', 'w', 'FontWeight', 'bold', ...
        'VerticalAlignment', 'top', 'BackgroundColor', [0.25 0.25 0.25]);
    text(ax, min(s.kGrid), T * 365.25, ' 4 ', 'Color', 'w', 'FontWeight', 'bold', ...
        'VerticalAlignment', 'bottom', 'BackgroundColor', [0.25 0.25 0.25]);
    hold(ax, 'off');
    cb = colorbar(ax); cb.Label.String = 'implied volatility (%)';
    pctTicks(ax);
    xlabel(ax, 'strike compared with today''s price'); ylabel(ax, 'days until expiry');
    title(ax, '6. The whole surface, seen from above');
    caption(tl, 24, ['This is the 3-D surface viewed from above, with height shown as color: brighter ' ...
        'means the market expects bigger swings. The smile (4) is one horizontal slice, the term structure (5) ' ...
        'is one vertical slice. Blank areas have no reliable quotes, so nothing is drawn there.']);
end

% =============================== helpers ====================================

function caption(tl, tile, str)
% Wrapped plain text in its own tile, directly under a panel.
    ax = nexttile(tl, tile);
    axis(ax, 'off');
    text(ax, 0, 1, wrapText(str, 62), 'Units', 'normalized', ...
        'VerticalAlignment', 'top', 'FontSize', 10);
end

function lines = wrapText(str, width)
    words = strsplit(char(str), ' ');
    lines = {};  cur = '';
    for i = 1:numel(words)
        if isempty(cur)
            cand = words{i};
        else
            cand = [cur ' ' words{i}];
        end
        if numel(cand) > width && ~isempty(cur)
            lines{end+1} = cur;            %#ok<AGROW>
            cur = words{i};
        else
            cur = cand;
        end
    end
    if ~isempty(cur), lines{end+1} = cur; end
end

function pctTicks(ax)
% Relabel a log-moneyness axis as "% above/below today's price".
    xt = xticks(ax);
    xticks(ax, xt);
    xticklabels(ax, arrayfun(@(k) sprintf('%+.0f%%', 100 * (exp(k) - 1)), xt, 'UniformOutput', false));
end

function v = smileAt(sl, k)
% Fitted smile value at log-moneyness k; NaN when k is outside the quoted range.
    ok = isfinite(sl.k) & isfinite(sl.iv);
    if nnz(ok) < 2 || k < min(sl.k(ok)) || k > max(sl.k(ok))
        v = NaN;
    else
        v = interp1(sl.k(ok), sl.iv(ok), k, 'linear');
    end
end

function c = bsCall(S, K, T, r, q, sig)
% Black-Scholes-Merton call price (vectorised in sig; no toolbox needed).
    Phi = @(x) 0.5 * erfc(-x / sqrt(2));
    d1 = (log(S ./ K) + (r - q + 0.5 * sig.^2) * T) ./ (sig * sqrt(T));
    d2 = d1 - sig * sqrt(T);
    c  = S * exp(-q * T) * Phi(d1) - K * exp(-r * T) * Phi(d2);
end
