import yfinance as yf
from bsm import analyze, time_till_exp, implied_volatility
import numpy as np
import pandas as pd
import ocaml_bridge


def get_risk_free_rate(T):
    if T <= 0.25:
        treasury = "^IRX"
    elif T <= 1:
        treasury = "^FVX"
    else:
        treasury = "^TNX"

    return yf.Ticker(treasury).info["regularMarketPrice"] / 100

def find_ticker_stock_price(symbol: str) -> float:
    stock = yf.Ticker(symbol)
    return stock.fast_info["last_price"]

def pick_expiration(ticker_symbol):
    ticker = yf.Ticker(ticker_symbol)
    expirations = ticker.options

    if not expirations:
        raise ValueError(f"No options available for {ticker_symbol}")

    print(f"\nAvailable expirations for {ticker_symbol}:")
    for i, exp in enumerate(expirations, 1):
        print(f" {i}. {exp}")

    while True:
        try:
            choice = int(input("\nSelect expiration (number): "))
            if 1 <= choice <= len(expirations):
                return expirations[choice -1]
            print(f"Enter 1-{len(expirations)}")
        except ValueError:
            print("Enter a number")

def historical_volatility(ticker_symbol, period="90d"):
    hist = yf.Ticker(ticker_symbol).history(period=period)
    returns = np.log(hist["Close"] / hist["Close"].shift(1)).dropna()
    return returns.std() * np.sqrt(252)


def analyze_live(ticker_symbol, expiration_date, option_type="call"):
    ticker = yf.Ticker(ticker_symbol)
    S = ticker.info["currentPrice"]
    T = time_till_exp(expiration_date)
    r = get_risk_free_rate(T)
    hv = historical_volatility(ticker_symbol)
    chain = ticker.option_chain(expiration_date)
    
    options = chain.calls if option_type == "call" else chain.puts
    options = options[["strike", "lastPrice", "bid", "ask"]].copy()
    options["market_price"] = np.where(
        options["bid"] > 0, (options["bid"] + options["ask"]) / 2, options["lastPrice"]
    )

    def compute_row(row):
        result = ocaml_bridge.analyze(S, row["strike"], T, r, row["market_price"], option_type)
        if result is None:
            return None
        result["hv"] = hv
        result["iv_hv_spread"] = result["iv"] - hv
        return result

    results = [r for r in options.apply(compute_row, axis=1) if r is not None]
    return pd.DataFrame(results)


def analyze_batch(symbols, expiration_date):
    results = {}
    for symbol in symbols:
        try:
            results[symbol] = analyze_live(symbol, expiration_date)
        except Exception as e:
            print(f"{symbol} failed: {e}")
            continue
    return results
