function out = vol_surface(ticker, opts)
%VOL_SURFACE One call from a ticker to the full volatility-surface figure.
%   vol_surface("AAPL")
%   out = vol_surface("MSFT", "MaxExpiries", 6, "Expiry", "2026-11-20")
%   vol_surface("AAPL", "Refresh", false)       % reuse snapshots/AAPL_latest.csv
%
%   Pipeline:
%     1. runs surface_export.py (live Yahoo Finance chain -> snapshots/*.csv)
%     2. load_chain -> bs_symbolic -> forward_from_parity -> select_otm ->
%        implied_vol on every OTM contract (cross-checked vs the OCaml IV)
%     3. build_surface (interpolated surface) and the two slices
%     4. one figure: 3-D surface | smile for one expiry | ATM term structure
%
%   Options (name-value)
%     Refresh      true   fetch live data; false = use the cached *_latest.csv.
%                         If the live fetch fails and a cache exists, the cache
%                         is used with a warning.
%     UseOCaml     true   add the OCaml reference IV (needs the built binary);
%                         false skips it (and the cross-validation).
%     Python       ""     path to a Python that has yfinance/pandas/numpy/scipy.
%                         Default: tries <repo>/.venv, MATLAB's pyenv, python3.
%     MaxExpiries  8      number of expiries to pull.
%     MinDays      7      skip expiries closer than this many days.
%     Expiry       ""     expiry shown in the smile panel, e.g. "2026-11-20".
%                         Default: the expiry with the most quotes.
%
%   Returns (optional) a struct: csv, chain, res, surface, smile, term, figure.

    arguments
        ticker (1,1) string
        opts.Refresh (1,1) logical = true
        opts.UseOCaml (1,1) logical = true
        opts.Python (1,1) string = ""
        opts.MaxExpiries (1,1) double {mustBeInteger, mustBePositive} = 8
        opts.MinDays (1,1) double {mustBeNonnegative} = 7
        opts.Expiry (1,1) string = ""
    end

    here = fileparts(mfilename('fullpath'));     % .../black-scholes/matlab
    root = fileparts(here);                      % .../black-scholes
    addpath(here);

    ticker = upper(strtrim(ticker));
    % The ticker is passed to a shell command, so accept only plain symbols.
    if isempty(regexp(ticker, '^[A-Z0-9.\-]{1,10}$', 'once'))
        error('vol_surface:badTicker', ...
            'Ticker "%s" is not a plain symbol (letters, digits, "." or "-", max 10 chars).', ticker);
    end

    % ---- 1. get a snapshot -------------------------------------------------
    cached = string(fullfile(root, 'snapshots', ticker + "_latest.csv"));
    csv = "";
    if opts.Refresh
        try
            py  = findPython(opts.Python, root);
            csv = runExporter(py, root, ticker, opts);
        catch err
            if isfile(cached)
                warning('vol_surface:usingCache', ...
                    'Live export failed:\n%s\n--> using cached snapshot %s', err.message, cached);
            else
                rethrow(err);
            end
        end
    end
    if csv == ""
        if ~isfile(cached)
            error('vol_surface:noSnapshot', ...
                'No cached snapshot at %s. Run once with "Refresh", true during market hours.', cached);
        end
        csv = cached;
    end
    fprintf('\n=== %s ===\nSnapshot: %s\n', ticker, csv);

    % ---- 2./3. solve, interpolate -----------------------------------------
    chain = load_chain(csv);
    res   = run_vol_checks(csv, 'Plot', false, 'Verbose', false);
    nEx = numel(unique(res.expiry));
    if height(res) < 10 || nEx < 2
        error('vol_surface:thinSnapshot', ...
            ['Snapshot %s has only %d usable out-of-the-money quote(s) across %d expiry(ies); ' ...
             'a surface needs several expiries. Outside market hours (9:30-16:00 ET) most ' ...
             'bids/asks are zero. Rerun when the market is open, or pass "Refresh", false ' ...
             'to use an older snapshot.'], csv, height(res), nEx);
    end
    s     = build_surface(res);

    expiry = opts.Expiry;
    if expiry == ""
        [g, ex] = findgroups(res.expiry);        % expiry with the most quotes
        [~, i] = max(accumarray(g, 1));
        expiry = ex(i);
    end
    sl = smile_slice(s, res, expiry);
    ts = term_structure_slice(s, 0);

    % ---- 4. one figure ------------------------------------------------------
    spot = chain.spot(1);
    asof = "";
    if ismember('asof', chain.Properties.VariableNames), asof = string(chain.asof(1)); end

    fig = figure('Name', "Volatility surface - " + ticker, 'Color', 'w', ...
        'Position', [80 80 1300 650]);
    tl = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, sprintf('%s   spot %.2f   snapshot %s', ticker, spot, asof));

    ax1 = nexttile(tl, 1, [2 1]);
    plot_surface(s, res, ax1);

    ax2 = nexttile(tl, 2);
    plot(ax2, sl.k, sl.iv, '-', 'LineWidth', 1.5); hold(ax2, 'on');
    scatter(ax2, sl.kMarket, sl.ivMarket, 28, 'filled'); hold(ax2, 'off');
    xline(ax2, 0, ':');
    xlabel(ax2, 'log-moneyness  ln(K/F)'); ylabel(ax2, 'implied volatility');
    title(ax2, sprintf('Smile: %s (%d days)', sl.expiry, round(sl.tau * 365.25)));
    legend(ax2, {'surface', 'market quotes'}, 'Location', 'best'); grid(ax2, 'on');

    ax3 = nexttile(tl, 4);
    plot(ax3, ts.days, ts.iv, '-', 'LineWidth', 1.5);
    xlabel(ax3, 'days to expiry'); ylabel(ax3, 'implied volatility');
    title(ax3, 'Term structure at the forward (k = 0)'); grid(ax3, 'on');

    if nargout > 0
        out = struct('csv', csv, 'chain', chain, 'res', res, 'surface', s, ...
                     'smile', sl, 'term', ts, 'figure', fig);
    end
end

% =============================== helpers ====================================

function py = findPython(userPy, root)
% Return a Python executable that can import everything surface_export.py needs.
    if ispc, nul = 'NUL'; else, nul = '/dev/null'; end
    probe = @(p) system(sprintf('"%s" -c "import yfinance, pandas, numpy, scipy" > %s 2>&1', p, nul)) == 0;

    if userPy ~= ""
        if ~probe(userPy)
            error('vol_surface:badPython', ...
                '"%s" cannot import yfinance, pandas, numpy and scipy.', userPy);
        end
        py = userPy;  return
    end

    cand = strings(0, 1);
    if ispc, venvPy = fullfile(root, '.venv', 'Scripts', 'python.exe');
    else,    venvPy = fullfile(root, '.venv', 'bin', 'python'); end
    if isfile(venvPy), cand(end+1, 1) = string(venvPy); end
    try
        pe = pyenv;
        if strlength(pe.Executable) > 0, cand(end+1, 1) = string(pe.Executable); end
    catch
    end
    cand = [cand; "python3"; "python"];
    cand = unique(cand, 'stable');

    for i = 1:numel(cand)
        if probe(cand(i)), py = cand(i); return, end
    end
    error('vol_surface:noPython', ...
        ['No Python with yfinance, pandas, numpy and scipy was found. Tried:\n  %s\n' ...
         'Pass one explicitly: vol_surface("AAPL", "Python", "/path/to/venv/bin/python")'], ...
        strjoin(cand, newline + "  "));
end

function csv = runExporter(py, root, ticker, opts)
% Run surface_export.py from the repo root; it prints the CSV path as its last line.
    oldDir = pwd;  restore = onCleanup(@() cd(oldDir));
    cd(root);

    args = sprintf('--out snapshots --max-expiries %d --min-days %d', ...
        opts.MaxExpiries, opts.MinDays);
    if ~opts.UseOCaml, args = [args ' --no-ocaml']; end
    cmd = sprintf('"%s" surface_export.py %s %s 2>&1', py, ticker, args);

    fprintf('Fetching %s option chain (typically 10-60 s)...\n', ticker);
    [status, txt] = system(cmd);
    lines = splitlines(strtrim(string(txt)));
    last  = strtrim(lines(end));
    if status ~= 0 || ~isfile(last)
        error('vol_surface:exportFailed', 'Python exporter failed (exit code %d):\n%s', status, txt);
    end
    csv = string(fullfile(root, last));
end
