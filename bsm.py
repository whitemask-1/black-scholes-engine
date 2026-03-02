import numpy as np
from scipy.stats import norm


# first component of the closed form solution for the Black-Scholes equation
def compute_d1(S, K, T, r, sigma):
    return (np.log(S / K) + (r + 0.5 * sigma**2) * T) / (sigma * np.sqrt(T))


# second component of the closed form solution for the Black-Scholes equation found by abstracting the difference between the d1 and d2
def compute_d2(d1, sigma, T):
    return d1 - sigma * np.sqrt(T)


# internal function for computing d1 and d2 within other functions to stop callers from managing intermediates
def _compute_intermediates(S, K, T, r, sigma):
    d1 = compute_d1(S, K, T, r, sigma)
    d2 = compute_d2(d1, sigma, T)
    return d1, d2


# Call price closed solution
def call_price(S, K, T, r, sigma):
    d1, d2 = _compute_intermediates(S, K, T, r, sigma)
    return (norm.cdf(d1) * S) - (norm.cdf(d2) * K * np.exp(-r * T))


# Put price closed solution
def put_price(S, K, T, r, sigma):
    d1, d2 = _compute_intermediates(S, K, T, r, sigma)
    return (norm.cdf(-d2) * K * np.exp(-r * T)) - (norm.cdf(-d1) * S)


# Outputs the call and put options as they are described by the Black-Scholes Equation for European stock options (can only use the option at the expiry date)
def black_scholes(S, K, T, r, sigma):
    call = call_price(S, K, T, r, sigma)
    put = put_price(S, K, T, r, sigma)

    return call, put


# GREEKS:


# delta: value the option gains per dollar increase of the underlying asset
def delta(S, K, T, r, sigma, option_type="call"):
    d1, _ = _compute_intermediates(S, K, T, r, sigma)
    if option_type == "call":
        return norm.cdf(d1)
    return norm.cdf(d1) - 1


# The rate at which delta is changing
def gamma(S, K, T, r, sigma):
    d1, _ = _compute_intermediates(S, K, T, r, sigma)
    return norm.pdf(d1) / (S * sigma * np.sqrt(T))


# How much the price changes if the volatility spikes
def vega(S, K, T, r, sigma):
    d1, _ = _compute_intermediates(S, K, T, r, sigma)
    return S * norm.pdf(d1) * np.sqrt(T)


# Value lost per year/day just from time passing
def theta(S, K, T, r, sigma, option_type="call", time_unit="year"):
    d1, d2 = _compute_intermediates(S, K, T, r, sigma)
    term1 = -(S * norm.pdf(d1) * sigma) / (2 * np.sqrt(T))
    term2 = r * K * np.exp(-r * T) * norm.cdf(d2)
    term2b = r * K * np.exp(-r * T) * norm.cdf(-d2)

    if option_type == "call":
        result = -(term1 - term2)
    else:
        result = -(term1 + term2b)

    if time_unit == "year":
        return result
    elif time_unit == "day":
        return result / 365

    return None


# Backsolve for implied volatility using the Newton Raphson Method
def implied_volatility(
    market_price, S, K, T, r, option_type="call", tol=1e-6, max_iter=100
):
    sigma = 0.2  # initial volatility guess
    for _ in range(max_iter):
        call, put = black_scholes(S, K, T, r, sigma)
        price = call if option_type == "call" else put
        v = vega(S, K, T, r, sigma)

        if v < 1e-10:  # avoid division by zero near expiry/deep OTM
            return None

        sigma -= (price - market_price) / v

        if abs(price - market_price) < tol:
            return sigma

    return None


def analyze(S, K, T, r, sigma):
    return {
        "call": call_price(S, K, T, r, sigma),
        "put": put_price(S, K, T, r, sigma),
        "call delta": delta(S, K, T, r, sigma, option_type="call"),
        "put delta": delta(S, K, T, r, sigma, option_type="put"),
        "gamma": gamma(S, K, T, r, sigma),
        "vega": vega(S, K, T, r, sigma),
        "call theta (yearly)": theta(
            S, K, T, r, sigma, option_type="call", time_unit="year"
        ),
        "call theta (daily)": theta(
            S, K, T, r, sigma, option_type="call", time_unit="day"
        ),
        "put theta (yearly)": theta(
            S, K, T, r, sigma, option_type="put", time_unit="year"
        ),
        "put theta (daily)": theta(
            S, K, T, r, sigma, option_type="put", time_unit="day"
        ),
    }


print(analyze(200, 210, 0.25, 0.05, 0.30))
