import numpy as np
from scipy.stats import norm


# first component of the closed form solution for the Black-Scholes equation
def compute_d1(S, K, T, r, sigma):
    return (np.log(S / K) + (r + 0.5 * sigma**2) * T) / (sigma * np.sqrt(T))


# second component of the closed form solution for the Black-Scholes equation found by abstracting the difference between the d1 and d2
def compute_d2(d1, sigma, T):
    return d1 - sigma * np.sqrt(T)


# Call price closed solution
def call_price(S, K, T, r, d1, d2):
    return (norm.cdf(d1) * S) - (norm.cdf(d2) * K * np.exp(-r * T))


# Put price closed solution
def put_price(S, K, T, r, d1, d2):
    return (norm.cdf(-d2) * K * np.exp(-r * T)) - (norm.cdf(-d1) * S)


# Outputs the call and put options as they are described by the Black-Scholes Equation for European stock options (can only use the option at the expiry date)
def black_scholes(S, K, T, r, sigma):
    d1 = compute_d1(S, K, T, r, sigma)
    d2 = compute_d2(d1, sigma, T)

    call = call_price(S, K, T, r, d1, d2)
    put = put_price(S, K, T, r, d1, d2)

    return call, put


# GREEKS:


# delta: value the option gains per dollar increase of the underlying asset
def delta(d1, option_type="call"):
    if option_type == "call":
        return norm.cdf(d1)
    return norm.cdf(d1) - 1


# The rate at which delta is changing
def gamma(S, T, sigma, d1):
    return norm.pdf(d1) / (S * sigma * np.sqrt(T))


# How much the price changes if the volatility spikes
def vega(S, d1, T):
    return S * norm.pdf(d1) * np.sqrt(T)


# Value lost per year/day just from time passing
def theta(S, d1, d2, sigma, T, K, r, option_type="call", time_unit="year"):
    term1 = -(S * norm.pdf(d1) * sigma) / (2 * np.sqrt(T))
    term2 = r * K * np.exp(-r * T) * norm.cdf(d2)
    term2b = r * K * np.exp(-r * T) * norm.cdf(-d2)

    if option_type == "call":
        result = -(term1 - term2)
    else:
        result = -(term1 + term2b)

    return result if time_unit == "year" else result / 365


def analyze(S, K, T, r, sigma):
    d1 = compute_d1(S, K, T, r, sigma)
    d2 = compute_d2(d1, sigma, T)

    return {
        "call": call_price(S, K, T, r, d1, d2),
        "put": put_price(S, K, T, r, d1, d2),
        "call delta": delta(d1),
        "put delta": delta(d1, option_type="put"),
        "gamma": gamma(S, T, sigma, d1),
        "vega": vega(S, d1, T),
        "call theta (yearly)": theta(S, d1, d2, sigma, T, K, r),
        "call theta (daily)": theta(S, d1, d2, sigma, T, K, r, time_unit="day"),
        "put theta (yearly)": theta(S, d1, d2, sigma, T, K, r, option_type="put"),
        "put theta (daily)": theta(
            S, d1, d2, sigma, T, K, r, option_type="put", time_unit="day"
        ),
    }


print(analyze(200, 210, 0.25, 0.05, 0.30))
