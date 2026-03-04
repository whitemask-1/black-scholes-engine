from bsm import analyze
import pandas as pd


def options_chain(S_range, K, T, r, sigma):
    results = [analyze(S, K, T, r, sigma) for S in S_range]
    df = pd.DataFrame(results)
    df.insert(0, "stock_price", S_range)
    return df
