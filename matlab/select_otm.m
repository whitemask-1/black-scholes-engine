function otm = select_otm(chain)
%SELECT_OTM Logical mask of out-of-the-money rows (puts below F, calls at/above F).
%   Requires the F column from forward_from_parity. OTM quotes carry the most
%   reliable implied vols: ITM options are mostly intrinsic value, so small
%   price errors (early exercise, dividends, stale quotes) become large IV errors.
    otm = (chain.type == "call" & chain.strike >= chain.F) | ...
          (chain.type == "put"  & chain.strike <  chain.F);
end
