import numpy as np
from chain import options_chain
from market import analyze_live, pick_expiration
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
    symbol = input("Ticker Symbol: ").upper()
    expiration_date = pick_expiration(symbol)
    df = analyze_live(symbol, expiration_date)
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
