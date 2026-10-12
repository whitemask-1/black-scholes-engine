"""Export a full single-stock options-chain snapshot for the MATLAB vol surface.

Pulls every (filtered) expiry for a ticker in one consistent snapshot, runs the
OCaml engine to get a reference implied vol per contract, and writes a tidy
long-format CSV plus a small meta JSON that MATLAB can load with readtable().

CLI:
    python surface_export.py AAPL --max-expiries 8

From MATLAB (python env must have yfinance/pandas/numpy installed):
    if count(py.sys.path, pwd) == 0, insert(py.sys.path, int32(0), pwd); end
    csv_path = string(py.surface_export.export_snapshot("AAPL"));
    T = readtable(csv_path);

CSV columns (one row per contract):
    symbol, asof, spot, expiry, T, r, q, type, strike, bid, ask, mid,
    spread_pct, volume, open_interest, iv_ocaml, iv_yahoo

Notes:
  * T uses bsm.time_till_exp (days / 365.25) so it matches the engine exactly.
  * q (dividend yield) is written as 0.0 because the engine has no dividend
    term. MATLAB should infer the forward from put-call parity instead.
  * Both calls and puts are exported; choose OTM-only in MATLAB.
"""

import argparse
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
import yfinance as yf

import ocaml_bridge
from bsm import time_till_exp
from market import get_risk_free_rate

COLUMNS = [
    "symbol", "asof", "spot", "expiry", "T", "r", "q", "type", "strike",
    "bid", "ask", "mid", "spread_pct", "volume", "open_interest",
    "iv_ocaml", "iv_yahoo",
]

IV_MIN, IV_MAX = 0.01, 5.0  # reject solver output outside this range


def _rate_bucket(T):
    """Mirror market.get_risk_free_rate's tenor buckets so rates can be cached."""
    return 0 if T <= 0.25 else (1 if T <= 1 else 2)


def clean_quotes(df, S, T, r, option_type, max_spread_pct=0.5, min_open_interest=1):
    """Keep only live, two-sided, non-arbitrageable quotes.

    Drops: zero/crossed bids, wide spreads, no open interest, and mids at or
    below intrinsic value (the IV solver cannot invert those).
    """
    df = df.copy()
    for col in ("bid", "ask", "openInterest", "volume", "impliedVolatility"):
        if col not in df.columns:
            df[col] = np.nan

    df["mid"] = (df["bid"] + df["ask"]) / 2
    df["spread_pct"] = (df["ask"] - df["bid"]) / df["mid"]

    disc_k = df["strike"] * np.exp(-r * T)
    if option_type == "call":
        intrinsic = np.maximum(S - disc_k, 0.0)
    else:
        intrinsic = np.maximum(disc_k - S, 0.0)

    keep = (
        (df["bid"] > 0)
        & (df["ask"] >= df["bid"])
        & (df["spread_pct"] <= max_spread_pct)
        & (df["openInterest"].fillna(0) >= min_open_interest)
        & (df["mid"] > intrinsic)
    )
    return df[keep]


def ocaml_iv(S, K, T, r, price, option_type):
    """Reference IV from the OCaml engine; NaN if the solver fails or is out of range."""
    try:
        res = ocaml_bridge.analyze(S, K, T, r, price, option_type)
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return np.nan
    if res is None:
        return np.nan
    iv = res["iv"]
    return iv if IV_MIN < iv < IV_MAX else np.nan


def build_snapshot(
    symbol,
    max_expiries=8,
    min_days=7,
    max_spread_pct=0.5,
    min_open_interest=1,
    iv_fn=ocaml_iv,
    ticker=None,
):
    """Build the snapshot DataFrame and meta dict for one ticker.

    iv_fn: callable(S, K, T, r, price, option_type) -> float, or None to skip
    the OCaml reference column (iv_ocaml will be NaN).
    ticker: optional yfinance-like object (injectable for tests).
    """
    symbol = symbol.upper()
    ticker = ticker or yf.Ticker(symbol)

    S = float(ticker.fast_info["last_price"])  # one spot for the whole surface
    asof = datetime.now(timezone.utc).replace(microsecond=0)

    expirations = ticker.options
    if not expirations:
        raise ValueError(f"No options available for {symbol}")

    rate_cache = {}
    frames, used_expiries, rates = [], [], {}

    for exp in expirations:
        if len(used_expiries) >= max_expiries:
            break
        T = time_till_exp(exp)
        if T * 365.25 < min_days:
            continue  # too close to expiry: vega ~ 0, T=0 divides by zero

        bucket = _rate_bucket(T)
        if bucket not in rate_cache:
            rate_cache[bucket] = get_risk_free_rate(T)
        r = rate_cache[bucket]

        chain = ticker.option_chain(exp)
        kept = 0
        for option_type, raw in (("call", chain.calls), ("put", chain.puts)):
            q = clean_quotes(raw, S, T, r, option_type, max_spread_pct, min_open_interest)
            if q.empty:
                continue
            q = q.assign(type=option_type, expiry=exp, T=T, r=r)
            if iv_fn is None:
                q["iv_ocaml"] = np.nan
            else:
                q["iv_ocaml"] = [
                    iv_fn(S, row.strike, T, r, row.mid, option_type)
                    for row in q.itertuples()
                ]
            frames.append(q)
            kept += len(q)

        if kept:
            used_expiries.append(exp)
            rates[exp] = r

    if not frames:
        raise RuntimeError(
            f"No quotes survived filtering for {symbol}. If the market is closed, "
            "bids/asks are often zero - rerun during trading hours."
        )

    df = pd.concat(frames, ignore_index=True)
    df["symbol"] = symbol
    df["asof"] = asof.isoformat()
    df["spot"] = S
    df["q"] = 0.0  # engine has no dividend term; MATLAB infers forward via parity
    df = df.rename(columns={"openInterest": "open_interest", "impliedVolatility": "iv_yahoo"})
    df = df[COLUMNS].sort_values(["expiry", "type", "strike"]).reset_index(drop=True)

    meta = {
        "symbol": symbol,
        "asof": asof.isoformat(),
        "spot": S,
        "expiries": used_expiries,
        "risk_free_rate_by_expiry": rates,
        "rows": int(len(df)),
        "filters": {
            "min_days": min_days,
            "max_spread_pct": max_spread_pct,
            "min_open_interest": min_open_interest,
            "max_expiries": max_expiries,
        },
        "notes": "q=0 (no dividend term in engine); T = days/365.25; mid=(bid+ask)/2",
    }
    return df, meta


def export_snapshot(symbol, out_dir="snapshots", use_ocaml=True, **kwargs):
    """Write <SYMBOL>_<timestamp>.csv, <SYMBOL>_latest.csv and a meta JSON.

    Returns the path of the timestamped CSV as a string (handy from MATLAB).
    """
    if use_ocaml and not ocaml_bridge.BINARY.exists():
        raise FileNotFoundError(
            f"OCaml binary not found at {ocaml_bridge.BINARY}. "
            "Run `dune build` in bsm_engine/ or pass use_ocaml=False / --no-ocaml."
        )

    df, meta = build_snapshot(
        symbol, iv_fn=ocaml_iv if use_ocaml else None, **kwargs
    )

    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    stamp = datetime.fromisoformat(meta["asof"]).strftime("%Y%m%d_%H%M")
    csv_path = out / f"{meta['symbol']}_{stamp}.csv"

    df.to_csv(csv_path, index=False)
    df.to_csv(out / f"{meta['symbol']}_latest.csv", index=False)
    csv_path.with_suffix(".json").write_text(json.dumps(meta, indent=2))
    return str(csv_path)


def main():
    p = argparse.ArgumentParser(description="Export an options-chain snapshot for MATLAB.")
    p.add_argument("symbol")
    p.add_argument("--out", default="snapshots")
    p.add_argument("--max-expiries", type=int, default=8)
    p.add_argument("--min-days", type=int, default=7)
    p.add_argument("--max-spread-pct", type=float, default=0.5)
    p.add_argument("--min-open-interest", type=int, default=1)
    p.add_argument("--no-ocaml", action="store_true", help="skip the OCaml reference IV column")
    a = p.parse_args()

    path = export_snapshot(
        a.symbol,
        out_dir=a.out,
        use_ocaml=not a.no_ocaml,
        max_expiries=a.max_expiries,
        min_days=a.min_days,
        max_spread_pct=a.max_spread_pct,
        min_open_interest=a.min_open_interest,
    )
    print(path)


if __name__ == "__main__":
    main()
