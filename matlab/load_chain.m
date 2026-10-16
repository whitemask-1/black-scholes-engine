function chain = load_chain(csvPath)
%LOAD_CHAIN Read and validate an options-chain CSV (any snapshot, any ticker).
%   chain = load_chain(csvPath)
%
%   Required columns (case-insensitive): spot, expiry, T, r, type, strike,
%   and either mid OR both bid and ask.
%   Optional: q (dividend yield, default 0), symbol, iv_ocaml (reference IV).
%
%   Output table has lower-case names; T is renamed to 'tau' (years),
%   type is "call"/"put", expiry is a string, mid is always present.
%   Rows with missing/invalid required values are dropped with a warning.

    arguments
        csvPath (1,1) string
    end
    if ~isfile(csvPath)
        error('load_chain:noFile', 'File not found: %s', csvPath);
    end

    chain = readtable(csvPath, 'VariableNamingRule', 'preserve');
    chain.Properties.VariableNames = lower(chain.Properties.VariableNames);

    % T -> tau so it can't be confused with a variable named T elsewhere
    if ismember('t', chain.Properties.VariableNames)
        chain = renamevars(chain, 't', 'tau');
    end

    % ---- required columns -------------------------------------------------
    have = string(chain.Properties.VariableNames);
    required = ["spot" "expiry" "tau" "r" "type" "strike"];
    missing = required(~ismember(required, have));
    hasMid = ismember("mid", have);
    hasBidAsk = all(ismember(["bid" "ask"], have));
    if ~hasMid && ~hasBidAsk
        missing(end+1) = "mid (or bid+ask)"; %#ok<AGROW>
    end
    if ~isempty(missing)
        error('load_chain:missingColumns', ...
            'CSV is missing required column(s): %s\nFound: %s', ...
            strjoin(missing, ', '), strjoin(have, ', '));
    end

    if ~hasMid
        chain.mid = (chain.bid + chain.ask) / 2;
    end
    if ~ismember("q", have)
        chain.q = zeros(height(chain), 1);
    end

    % ---- normalise types --------------------------------------------------
    chain.expiry = string(chain.expiry);
    t = lower(strtrim(string(chain.type)));
    t(t == "c") = "call";
    t(t == "p") = "put";
    if any(~ismember(t, ["call" "put"]))
        bad = unique(t(~ismember(t, ["call" "put"])));
        error('load_chain:badType', 'Unrecognised option type(s): %s', strjoin(bad, ', '));
    end
    chain.type = t;

    % ---- drop unusable rows ----------------------------------------------
    num = [chain.spot chain.tau chain.r chain.strike chain.mid chain.q];
    ok = all(isfinite(num), 2) & chain.strike > 0 & chain.tau > 0 ...
        & chain.mid > 0 & chain.spot > 0;
    if any(~ok)
        warning('load_chain:droppedRows', ...
            'Dropped %d of %d rows with missing/invalid values.', nnz(~ok), height(chain));
    end
    chain = chain(ok, :);
    if isempty(chain)
        error('load_chain:empty', 'No usable rows left after validation.');
    end
end
