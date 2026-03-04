import yfinance as yf
from bsm import analyze, time_till_exp, implied_volatility
import numpy as np
import pandas as pd


def get_risk_free_rate(T):
    if T <= 0.25:
        treasury = "^IRX"
    elif T <= 1:
        treasury = "^FVX"
    else:
        treasury = "^TNX"

    return yf.Ticker(treasury).info["regularMarketPrice"] / 100


def analyze_live(ticker_symbol, expiration_date):
    ticker = yf.Ticker(ticker_symbol)
    S = ticker.info["currentPrice"]
    T = time_till_exp(expiration_date)
    r = get_risk_free_rate(T)

    chain = ticker.option_chain(expiration_date)
    calls = chain.calls[["strike", "lastPrice", "bid", "ask"]].copy()

    calls["market_price"] = np.where(
        calls["bid"] > 0, (calls["bid"] + calls["ask"]) / 2, calls["lastPrice"]
    )

    def compute_row(row):
        iv = implied_volatility(row["market_price"], S, K=row["strike"], T=T, r=r)
        if iv is None:
            return None
        result = analyze(S, row["strike"], T, r, iv)
        result["iv"] = iv
        return result

    return pd.DataFrame([r for r in calls.apply(compute_row, axis=1) if r is not None])


def analyze_batch(symbols, expiration_date):
    results = {}
    for symbol in symbols:
        try:
            results[symbol] = analyze_live(symbol, expiration_date)
        except Exception as e:
            print(f"{symbol} failed: {e}")
            continue
    return results
