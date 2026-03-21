import numpy as np
from chain import options_chain
from market import analyze_live, pick_expiration
from rich_out import display_manual_chain, display_live_chain
import sys


def run_manual():
    K = 210
    T = 0.25
    r = 0.05
    sigma = 0.30
    S_range = np.linspace(150, 250, 100)
    df = options_chain(S_range, K, T, r, sigma)
    display_manual_chain(df)


def run_live():
    option_type = input("Call or Put Options: ").lower()
    symbol = input("Ticker Symbol: ").upper()
    expiration_date = pick_expiration(symbol)
    df = analyze_live(symbol, expiration_date, option_type)
    display_live_chain(df, symbol, expiration_date, option_type)


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
