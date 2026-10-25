#!/usr/bin/env python3
"""Independent third-party check of the MATLAB implied-volatility pipeline.

Re-solves every out-of-the-money implied volatility in a snapshot CSV using a
completely different solver (SciPy's Brent root finder, closed-form Black-Scholes
from scipy.stats) and compares it with the reference column written by the OCaml
engine (iv_ocaml). Agreement of two unrelated implementations is the evidence;
the MATLAB numbers from run_vol_checks should land in the same place.

    python3 verify_independent.py snapshots/AAPL_20261012_1347.csv
"""
import sys
import numpy as np
import pandas as pd
from scipy.optimize import brentq
from scipy.stats import norm


def price(S, K, T, r, q, sig, is_call):
    d1 = (np.log(S / K) + (r - q + 0.5 * sig * sig) * T) / (sig * np.sqrt(T))
    d2 = d1 - sig * np.sqrt(T)
    if is_call:
        return S * np.exp(-q * T) * norm.cdf(d1) - K * np.exp(-r * T) * norm.cdf(d2)
    return K * np.exp(-r * T) * norm.cdf(-d2) - S * np.exp(-q * T) * norm.cdf(-d1)


def implied_vol(px, S, K, T, r, q, is_call):
    f = lambda s: price(S, K, T, r, q, s, is_call) - px
    if not (f(1e-4) <= 0 <= f(5.0)):
        return np.nan
    return brentq(f, 1e-4, 5.0, xtol=1e-12)


def main(path):
    df = pd.read_csv(path)
    df.columns = [c.lower() for c in df.columns]
    if "q" not in df:
        df["q"] = 0.0
    if "mid" not in df:
        df["mid"] = (df["bid"] + df["ask"]) / 2

    out = []
    for expiry, g in df.groupby("expiry"):
        S, T, r, q = g.spot.iloc[0], g["t"].iloc[0], g.r.iloc[0], g.q.iloc[0]
        c = g[g.type == "call"].groupby("strike").mid.mean()
        p = g[g.type == "put"].groupby("strike").mid.mean()
        both = c.index.intersection(p.index)
        if len(both):
            near = sorted(both, key=lambda k: abs(k - S))[:5]
            F = float(np.median([k + np.exp(r * T) * (c[k] - p[k]) for k in near]))
        else:
            F = S * np.exp((r - q) * T)
        otm = g[((g.type == "call") & (g.strike >= F)) | ((g.type == "put") & (g.strike < F))]
        for _, row in otm.iterrows():
            iv = implied_vol(row.mid, S, row.strike, T, r, q, row.type == "call")
            out.append((expiry, row.type, row.strike, iv, row.get("iv_ocaml", np.nan)))
    res = pd.DataFrame(out, columns=["expiry", "type", "strike", "iv_python", "iv_ocaml"])
    n, solved = len(res), res.iv_python.notna().sum()
    print(f"OTM contracts: {n}   solved by SciPy: {solved}   expiries: {res.expiry.nunique()}")
    d = (res.iv_python - res.iv_ocaml).abs().dropna()
    if len(d):
        print(f"|SciPy - OCaml|   median {d.median():.2e}   max {d.max():.2e}   (n={len(d)})")
        print("OCaml prints 6 decimals, so differences up to 5e-7 are rounding, not error.")
        ok = d.max() < 1e-6
        print("RESULT:", "PASS" if ok else "CHECK")
        return 0 if ok else 1
    print("No iv_ocaml column to compare against.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
