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
import sys
from datetime import datetime, time as dtime, timedelta, timezone
from zoneinfo import ZoneInfo
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

ET = ZoneInfo("America/New_York")
SESSION_OPEN, SESSION_CLOSE = dtime(9, 30), dtime(16, 0)


def market_is_open(now_et):
    """True during regular US trading hours (holidays are not modelled)."""
    return now_et.weekday() < 5 and SESSION_OPEN <= now_et.time() < SESSION_CLOSE


def last_completed_session(ticker, now_et):
    """(date, close) of the most recent finished regular session."""
    hist = ticker.history(period="10d", interval="1d")
    closes = hist["Close"].dropna() if hist is not None and len(hist) else []
    if len(closes) == 0:
        raise RuntimeError("No recent daily price history available to find the prior session.")
    finished = [
        i for i, ts in enumerate(closes.index)
        if ts.date() < now_et.date()
        or (ts.date() == now_et.date() and now_et.time() >= dtime(16, 15))
    ]
    if not finished:
        raise RuntimeError("Could not identify a completed trading session in the price history.")
    i = finished[-1]
    return closes.index[i].date(), float(closes.iloc[i])


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


def clean_last_trades(df, S, T, r, option_type, session_date, window_start, min_open_interest=1, stats=None):
    """Prior-session mode: keep contracts whose LAST TRADE was in the final window of
    `session_date` and use that last price as the mid.

    Bid/ask are meaningless before the open, so there is no spread filter. Requiring the
    trade to fall in the closing window keeps the option price roughly synchronous with
    the closing spot price used as S (older trades are priced against a different spot).

    stats: optional dict; "active" counts contracts that traded on/after session_date and
    "after" those whose last trade is newer than the session's close, i.e. whose last
    price has since been overwritten by today's trading.
    """
    df = df.copy()
    for col in ("lastPrice", "openInterest", "volume", "impliedVolatility", "bid", "ask", "lastTradeDate"):
        if col not in df.columns:
            df[col] = np.nan

    traded = pd.to_datetime(df["lastTradeDate"], utc=True, errors="coerce").dt.tz_convert(ET)
    df["mid"] = df["lastPrice"]
    df["spread_pct"] = np.nan

    if stats is not None:
        session_close = datetime.combine(session_date, SESSION_CLOSE, tzinfo=ET)
        day_start = datetime.combine(session_date, dtime(0, 0), tzinfo=ET)
        priced = df["lastPrice"] > 0
        stats["active"] += int((priced & (traded >= day_start)).sum())
        stats["after"] += int((priced & (traded > session_close + timedelta(minutes=15))).sum())

    disc_k = df["strike"] * np.exp(-r * T)
    if option_type == "call":
        intrinsic = np.maximum(S - disc_k, 0.0)
    else:
        intrinsic = np.maximum(disc_k - S, 0.0)

    keep = (
        (df["lastPrice"] > 0)
        & (traded.dt.date == session_date)
        & (traded >= window_start)
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
    min_rows=20,
    min_expiries=2,
    session="live",
    prior_window_min=60,
    max_overwritten=0.2,
    iv_fn=ocaml_iv,
    ticker=None,
    now=None,
):
    """Build the snapshot DataFrame and meta dict for one ticker.

    iv_fn: callable(S, K, T, r, price, option_type) -> float, or None to skip
    the OCaml reference column (iv_ocaml will be NaN).
    ticker: optional yfinance-like object (injectable for tests).

    session: "live" (default) prices from the current bid/ask midpoint. "prior" is for
    use BEFORE the market opens: Yahoo only serves the current chain, so the prior
    session is rebuilt from each contract's last trade (kept only if it traded in the
    final `prior_window_min` minutes of that session) against that session's close.
    While the market is open it still works as long as few contracts have traded today:
    the share whose last price is already today's is measured, and the snapshot is refused
    if it exceeds `max_overwritten` (liquid ATM contracts trade first, so a high share
    means the sample is biased toward illiquid strikes). now: injectable clock for tests.
    """
    if session not in ("live", "prior"):
        raise ValueError('session must be "live" or "prior"')
    symbol = symbol.upper()
    ticker = ticker or yf.Ticker(symbol)

    asof_date = None
    if session == "prior":
        now_et = (now or datetime.now(ET)).astimezone(ET)
        asof_date, S = last_completed_session(ticker, now_et)
        asof = datetime.combine(asof_date, SESSION_CLOSE, tzinfo=ET)
        window_start = asof - timedelta(minutes=prior_window_min)
    else:
        S = float(ticker.fast_info["last_price"])  # one spot for the whole surface
        asof = datetime.now(timezone.utc).replace(microsecond=0)

    expirations = ticker.options
    if not expirations:
        raise ValueError(f"No options available for {symbol}")

    rate_cache = {}
    stats = {"active": 0, "after": 0}
    frames, used_expiries, rates = [], [], {}

    for exp in expirations:
        if len(used_expiries) >= max_expiries:
            break
        if session == "prior":   # measure maturity from the prior session, not from today
            T = (datetime.strptime(exp, "%Y-%m-%d").date() - asof_date).days / 365.25
        else:
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
            if session == "prior":
                q = clean_last_trades(raw, S, T, r, option_type, asof_date, window_start,
                                      min_open_interest, stats)
            else:
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

    overwritten = stats["after"] / stats["active"] if stats["active"] else 0.0
    if session == "prior":
        if overwritten > max_overwritten:
            raise RuntimeError(
                f"{overwritten:.0%} of {symbol} contracts have already traded since the prior session "
                f"closed, so their last prices are no longer yesterday's (limit {max_overwritten:.0%}). "
                "A prior-session surface would be biased toward illiquid strikes. "
                "Use session=\"live\" now, or run prior mode before the open. Nothing was written."
            )
        if overwritten > 0:
            print(f"note: {overwritten:.0%} of contracts have already traded today and were excluded.",
                  file=sys.stderr)
    if session == "prior":
        why = (f"In prior mode only contracts whose last trade fell in the final {prior_window_min} "
               "minutes of the session are kept; widen it with --prior-window-min.")
    else:
        why = ("The market is probably closed or just opening: bids/asks are mostly zero outside "
               "regular hours (9:30-16:00 ET), and the first minutes after the open are thin. "
               "Before the open, try session=\"prior\" (--session prior).")
    if not frames:
        raise RuntimeError(f"No quotes survived filtering for {symbol}. {why}")

    df = pd.concat(frames, ignore_index=True)
    if len(df) < min_rows or len(used_expiries) < min_expiries:
        raise RuntimeError(
            f"Only {len(df)} usable quote(s) across {len(used_expiries)} expiry(ies) for {symbol} "
            f"(need >= {min_rows} quotes and >= {min_expiries} expiries for a surface). "
            f"{why} Nothing was written."
        )
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
        "session": session,
        "overwritten_fraction": round(overwritten, 4) if session == "prior" else None,
        "price_source": (
            "bid/ask midpoint"
            if session == "live"
            else f"last trade, final {prior_window_min} min of {asof_date} (spot = that day's close)"
        ),
        "notes": "q=0 (no dividend term in engine); T = days/365.25 from the as-of date",
    }
    return df, meta


def export_snapshot(symbol, out_dir="snapshots", use_ocaml=True, **kwargs):
    """Write <SYMBOL>_<timestamp>.csv, <SYMBOL>_latest.csv and a meta JSON
    (prior session: <SYMBOL>_<timestamp>_prior.csv and <SYMBOL>_prior_latest.csv).

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
    # prior-session snapshots use their own names so they never overwrite a live *_latest.csv
    tag = "_prior" if meta["session"] == "prior" else ""
    csv_path = out / f"{meta['symbol']}_{stamp}{tag}.csv"

    df.to_csv(csv_path, index=False)
    df.to_csv(out / f"{meta['symbol']}{tag}_latest.csv", index=False)
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
    p.add_argument("--min-rows", type=int, default=20, help="refuse to write a snapshot with fewer usable quotes")
    p.add_argument("--session", choices=["live", "prior"], default="live",
                   help="prior = rebuild yesterday from last trades (use before the market opens)")
    p.add_argument("--prior-window-min", type=int, default=60,
                   help="prior mode: keep only trades in the final N minutes of the session")
    p.add_argument("--max-overwritten", type=float, default=0.2,
                   help="prior mode: refuse if more than this share of contracts already traded today")
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
        min_rows=a.min_rows,
        session=a.session,
        prior_window_min=a.prior_window_min,
        max_overwritten=a.max_overwritten,
    )
    print(path)


if __name__ == "__main__":
    main()
