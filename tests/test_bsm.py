import pytest
import numpy as np
from bsm import (
    call_price,
    put_price,
    black_scholes,
    delta,
    gamma,
    vega,
    theta,
    rho,
    implied_volatility,
    analyze,
)

# Standard test inputs used across all tests
S = 200.0  # stock price
K = 210.0  # strike price
T = 0.25  # time to maturity (3 months)
r = 0.05  # risk-free rate
sigma = 0.30  # volatility
h = 1e-4  # finite difference step size


# --- Pricing ---


def test_call_price_known_value():
    # Validated against Drexel BSM calculator
    assert call_price(S, K, T, r, sigma) == pytest.approx(8.8362, rel=1e-3)


def test_put_price_known_value():
    assert put_price(S, K, T, r, sigma) == pytest.approx(16.2276, rel=1e-3)


def test_put_call_parity():
    # C - P = S - K*e^(-rT) must always hold
    C = call_price(S, K, T, r, sigma)
    P = put_price(S, K, T, r, sigma)
    assert C - P == pytest.approx(S - K * np.exp(-r * T), rel=1e-6)


def test_black_scholes_matches_individual():
    # black_scholes() should return same values as call_price/put_price
    call, put = black_scholes(S, K, T, r, sigma)
    assert call == pytest.approx(call_price(S, K, T, r, sigma), rel=1e-10)
    assert put == pytest.approx(put_price(S, K, T, r, sigma), rel=1e-10)


# --- Delta ---


def test_call_delta_known_value():
    assert delta(S, K, T, r, sigma, option_type="call") == pytest.approx(
        0.4337, rel=1e-3
    )


def test_put_delta_known_value():
    assert delta(S, K, T, r, sigma, option_type="put") == pytest.approx(
        -0.5662, rel=1e-3
    )


def test_call_delta_finite_difference():
    # Analytical delta should match numerical derivative of call price w.r.t. S
    analytical = delta(S, K, T, r, sigma, option_type="call")
    numerical = (
        call_price(S + h, K, T, r, sigma) - call_price(S - h, K, T, r, sigma)
    ) / (2 * h)
    assert analytical == pytest.approx(numerical, rel=1e-4)


def test_put_delta_finite_difference():
    analytical = delta(S, K, T, r, sigma, option_type="put")
    numerical = (
        put_price(S + h, K, T, r, sigma) - put_price(S - h, K, T, r, sigma)
    ) / (2 * h)
    assert analytical == pytest.approx(numerical, rel=1e-4)


def test_call_put_delta_relationship():
    # Call delta - put delta must always equal 1
    call_d = delta(S, K, T, r, sigma, option_type="call")
    put_d = delta(S, K, T, r, sigma, option_type="put")
    assert call_d - put_d == pytest.approx(1.0, rel=1e-6)


# --- Gamma ---


def test_gamma_finite_difference():
    # Gamma is the second derivative of price w.r.t. S
    analytical = gamma(S, K, T, r, sigma)
    numerical = (
        call_price(S + h, K, T, r, sigma)
        - 2 * call_price(S, K, T, r, sigma)
        + call_price(S - h, K, T, r, sigma)
    ) / (h**2)
    assert analytical == pytest.approx(numerical, rel=1e-3)


def test_call_put_gamma_equal():
    # Gamma is identical for calls and puts with same inputs
    assert gamma(S, K, T, r, sigma) == pytest.approx(
        (
            put_price(S + h, K, T, r, sigma)
            - 2 * put_price(S, K, T, r, sigma)
            + put_price(S - h, K, T, r, sigma)
        )
        / (h**2),
        rel=1e-3,
    )


# --- Vega ---


def test_vega_finite_difference():
    # Vega is the derivative of price w.r.t. sigma
    analytical = vega(S, K, T, r, sigma)
    numerical = (
        call_price(S, K, T, r, sigma + h) - call_price(S, K, T, r, sigma - h)
    ) / (2 * h)
    assert analytical == pytest.approx(numerical, rel=1e-4)


def test_call_put_vega_equal():
    # Vega is identical for calls and puts
    numerical_put = (
        put_price(S, K, T, r, sigma + h) - put_price(S, K, T, r, sigma - h)
    ) / (2 * h)
    assert vega(S, K, T, r, sigma) == pytest.approx(numerical_put, rel=1e-4)


# --- Theta ---


def test_call_theta_positive():
    # Theta is always negative — options lose value as time passes
    assert theta(S, K, T, r, sigma, option_type="call", time_unit="year") > 0  # type: ignore


def test_put_theta_positive():
    assert theta(S, K, T, r, sigma, option_type="put", time_unit="year") > 0  # type: ignore


def test_theta_daily_is_yearly_divided_by_365():
    yearly = theta(S, K, T, r, sigma, option_type="call", time_unit="year")
    daily = theta(S, K, T, r, sigma, option_type="call", time_unit="day")
    assert daily == pytest.approx(yearly / 365, rel=1e-10)  # type: ignore


def test_call_theta_finite_difference():
    # Theta is the derivative of price w.r.t. T (negative — less time = less value)
    analytical = theta(S, K, T, r, sigma, option_type="call", time_unit="year")
    numerical = (
        call_price(S, K, T + h, r, sigma) - call_price(S, K, T - h, r, sigma)
    ) / (2 * h)
    assert analytical == pytest.approx(numerical, rel=1e-3)


# --- Rho ---


def test_call_rho_positive():
    # Call rho is always positive — calls benefit from rising rates
    assert rho(S, K, T, r, sigma, option_type="call") > 0


def test_put_rho_negative():
    # Put rho is always negative — puts lose value when rates rise
    assert rho(S, K, T, r, sigma, option_type="put") < 0


def test_call_rho_finite_difference():
    analytical = rho(S, K, T, r, sigma, option_type="call")
    numerical = (
        call_price(S, K, T, r + h, sigma) - call_price(S, K, T, r - h, sigma)
    ) / (2 * h)
    assert analytical == pytest.approx(numerical, rel=1e-3)


def test_put_rho_finite_difference():
    analytical = rho(S, K, T, r, sigma, option_type="put")
    numerical = (
        put_price(S, K, T, r + h, sigma) - put_price(S, K, T, r - h, sigma)
    ) / (2 * h)
    assert analytical == pytest.approx(numerical, rel=1e-3)


# --- Implied Volatility ---


def test_implied_volatility_roundtrip():
    # IV should recover the original sigma when given a BSM-generated price
    market_price = call_price(S, K, T, r, sigma)
    recovered_sigma = implied_volatility(market_price, S, K, T, r, option_type="call")
    assert recovered_sigma == pytest.approx(sigma, rel=1e-4)


def test_implied_volatility_put_roundtrip():
    market_price = put_price(S, K, T, r, sigma)
    recovered_sigma = implied_volatility(market_price, S, K, T, r, option_type="put")
    assert recovered_sigma == pytest.approx(sigma, rel=1e-4)


# --- Analyze ---


def test_analyze_returns_all_keys():
    expected_keys = {
        "call",
        "put",
        "call_delta",
        "put_delta",
        "gamma",
        "vega",
        "call_theta_yearly",
        "call_theta_daily",
        "put_theta_yearly",
        "put_theta_daily",
        "call_rho",
        "put_rho",
    }
    result = analyze(S, K, T, r, sigma)
    assert set(result.keys()) == expected_keys


def test_analyze_values_match_individual_functions():
    result = analyze(S, K, T, r, sigma)
    assert result["call"] == pytest.approx(call_price(S, K, T, r, sigma), rel=1e-10)
    assert result["call_delta"] == pytest.approx(
        delta(S, K, T, r, sigma, option_type="call"), rel=1e-10
    )
    assert result["gamma"] == pytest.approx(gamma(S, K, T, r, sigma), rel=1e-10)
