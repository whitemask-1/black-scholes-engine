import numpy as np
from chain import options_chain
from yahoo_integrate import analyze_batch
from rich_out import display_chain
import sys


def run_manual():
    K = 210
    T = 0.25
    r = 0.05
    sigma = 0.30
    S_range = np.linspace(150, 250, 100)
    df = options_chain(S_range, K, T, r, sigma)
    display_chain(df, "Manual")


def run_live():
    symbols = ["AAPL", "TSLA"]
    expiration_date = "2026-03-09"
    data = analyze_batch(symbols, expiration_date)
    for symbol, df in data.items():
        display_chain(df, symbol)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "manual"
    if mode == "manual":
        run_manual()
    elif mode == "live":
        run_live()
    else:
        print(f"Unknown mode: {mode}")


if __name__ == "__main__":
    main()
