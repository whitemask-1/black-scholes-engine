from bsm import compute_d1, compute_d2, black_scholes, delta, gamma, vega, theta
import pandas as pd


def options_chain(S_range, K, T, r, sigma):
    d1 = compute_d1(S_range, K, T, r, sigma)
    d2 = compute_d2(d1, sigma, T)

    (
        calls,
        puts,
    ) = black_scholes(S_range, K, T, r, sigma)

    return pd.DataFrame(
        {
            "stock_price": S_range,
            "call": calls,
            "put": puts,
            "delta_call": delta(d1, "call"),
            "delta_put": delta(d1, "put"),
            "gamma": gamma(S_range, T, sigma, d1),
            "vega": vega(S_range, d1, T),
            "theta": theta(S_range, d1, d2, sigma, T, K, r),
        }
    )
