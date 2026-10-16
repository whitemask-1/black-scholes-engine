function fns = bs_symbolic(verbose)
%BS_SYMBOLIC Derive Black-Scholes price/Greeks symbolically and compile them.
%   fns = bs_symbolic()        returns numeric function handles, all with the
%   argument order (S, K, T, r, q, sig) and fully vectorised:
%       fns.call, fns.put, fns.vega, fns.delta_call, fns.gamma
%   Requires the Symbolic Math Toolbox.
%
%   The model has a continuous dividend yield q. With q = 0 it is exactly the
%   model used by the Python/OCaml engine.
%
%   Also verifies (symbolically if simplify can reduce it, always numerically):
%     * the Black-Scholes PDE:  -dC/dT + (r-q) S C_S + 1/2 sig^2 S^2 C_SS - r C = 0
%     * put-call parity:        C - P = S e^{-qT} - K e^{-rT}

    if nargin < 1, verbose = false; end

    syms S K T r q sig positive
    Phi = @(x) (1 + erf(x ./ sqrt(sym(2)))) / 2;      % standard normal CDF

    d1 = (log(S/K) + (r - q + sig^2/2) * T) / (sig * sqrt(T));
    d2 = d1 - sig * sqrt(T);

    C = S*exp(-q*T)*Phi(d1)  - K*exp(-r*T)*Phi(d2);
    P = K*exp(-r*T)*Phi(-d2) - S*exp(-q*T)*Phi(-d1);

    vega  = diff(C, sig);
    delta = diff(C, S);
    gamma = diff(C, S, 2);

    vars = [S K T r q sig];
    fns.call       = matlabFunction(C,     'Vars', vars);
    fns.put        = matlabFunction(P,     'Vars', vars);
    fns.vega       = matlabFunction(vega,  'Vars', vars);
    fns.delta_call = matlabFunction(delta, 'Vars', vars);
    fns.gamma      = matlabFunction(gamma, 'Vars', vars);
    fns.sym = struct('C', C, 'P', P, 'vega', vega, 'delta', delta, 'gamma', gamma);

    % ---- verification ------------------------------------------------------
    pdeRes    = -diff(C, T) + (r - q)*S*diff(C, S) + sig^2/2*S^2*diff(C, S, 2) - r*C;
    parityRes = C - P - (S*exp(-q*T) - K*exp(-r*T));

    fns.check.pde_symbolic    = tryZero(pdeRes);
    fns.check.parity_symbolic = tryZero(parityRes);

    rng(0);                                              % reproducible sample points
    n = 50;
    pt = {100*(0.7+0.6*rand(n,1)), 100*(0.7+0.6*rand(n,1)), 0.05+2*rand(n,1), ...
          0.06*rand(n,1), 0.04*rand(n,1), 0.1+0.6*rand(n,1)};
    pdeNum    = matlabFunction(pdeRes,    'Vars', vars);
    parityNum = matlabFunction(parityRes, 'Vars', vars);
    fns.check.pde_numeric_maxabs    = max(abs(pdeNum(pt{:})));
    fns.check.parity_numeric_maxabs = max(abs(parityNum(pt{:})));

    if verbose
        fprintf('Symbolic vega:\n'); disp(simplify(vega));
        fprintf('BS PDE residual   symbolic==0: %d, numeric max|res| = %.2e\n', ...
            fns.check.pde_symbolic, fns.check.pde_numeric_maxabs);
        fprintf('Put-call parity   symbolic==0: %d, numeric max|res| = %.2e\n', ...
            fns.check.parity_symbolic, fns.check.parity_numeric_maxabs);
    end
end

function ok = tryZero(expr)
    % true only if simplify proves the expression is identically zero
    try
        ok = logical(isAlways(simplify(expr, 'Steps', 30) == 0));
    catch
        ok = false;
    end
end
