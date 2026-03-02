# Black-Scholes Options Pricing Engine

A from-scratch implementation of the Black-Scholes-Merton (BSM) pricing model built to understand quantitative finance through the lens of Calculus 3 and applied mathematics. This project is the foundation of a larger quant data engineering toolchain.

---

## Why This Project Exists

Options pricing is one of the most direct applications of multivariable calculus in the real world. The Greeks are partial derivatives. The model is a PDE solution. Finite differences are numerical approximations of those derivatives. This project exists to make that math tangible in code.

The end goal is a quant data engineering pipeline — market data ingestion, options analysis at scale, and portfolio optimization. This calculator is the mathematical core of that system.

---

## The Math Story

### What Problem BSM Solves

An options contract gives you the _right_ (not obligation) to buy or sell a stock at a fixed **strike price** on a future date. The market charges a **premium** for this contract today. BSM answers: **what is the fair premium?**

Given that Apple trades at $200 and you want the right to buy at $210 in 3 months, BSM tells you that contract should cost ~$8.50 today. If Apple hits $230 at expiration you net $20 minus the $8.50 premium = $11.50 profit. If it stays below $210 you lose the $8.50 and walk away.

### The Derivation Chain

```
Assumptions
    → Geometric Brownian Motion (stock price SDE)
        → Ito's Lemma (stochastic chain rule)
            → BSM PDE (eliminate randomness via hedging)
                → Closed Form Solution
                    → Greeks (partial derivatives of the solution)
```

**Key assumptions BSM makes (and where it breaks down):**

- Volatility is constant — it isn't
- Log-normal returns — fat tails exist
- Continuous trading, no transaction costs — not realistic
- No dividends — requires adjustment for dividend-paying stocks

Knowing where the model lies to you is the actual skill.

### The Closed Form Solution

```
d1 = [ln(S/K) + (r + σ²/2)T] / σ√T
d2 = d1 - σ√T

Call = S·N(d1) - K·e^(-rT)·N(d2)
Put  = K·e^(-rT)·N(-d2) - S·N(-d1)
```

Where `N()` is the cumulative standard normal distribution.

**d2 is derived from d1** — not computed independently — because the only difference between their expanded forms is `+σ²/2` vs `-σ²/2` in the numerator, which simplifies to exactly `σ√T`.

---

## Inputs

| Variable         | Symbol | Meaning                                                          |
| ---------------- | ------ | ---------------------------------------------------------------- |
| Stock price      | `S`    | Current market price of the underlying                           |
| Strike price     | `K`    | Price at which you can buy/sell, fixed in the contract           |
| Time to maturity | `T`    | Time remaining until expiration, in years (e.g. 3 months = 0.25) |
| Risk-free rate   | `r`    | Treasury yield — return you'd get risk-free                      |
| Volatility       | `σ`    | Implied volatility — market's estimate of future price movement  |

`T` is a **duration**, not a timestamp. You compute it from dates:

```python
from datetime import date

def time_to_maturity(expiration: date) -> float:
    return (expiration - date.today()).days / 365
```

---

## Output

### Prices

- **Call price** — fair premium for the right to _buy_ at strike K
- **Put price** — fair premium for the right to _sell_ at strike K

### The Greeks (Risk Dimensions)

| Greek | Derivative | Meaning                                                |
| ----- | ---------- | ------------------------------------------------------ |
| Delta | ∂C/∂S      | How much the price changes per $1 move in stock        |
| Gamma | ∂²C/∂S²    | How fast delta itself is changing                      |
| Theta | ∂C/∂t      | Value lost per day from time passing (always negative) |
| Vega  | ∂C/∂σ      | Sensitivity to a change in volatility                  |
| Rho   | ∂C/∂r      | Sensitivity to a change in interest rate               |

Traders use Greeks for **risk management**, not just pricing. A market maker selling thousands of contracts needs to know total exposure if the market moves 2% tomorrow — that's delta. Greeks quantify each risk dimension independently.

---

## Project Structure

```
bsm/
├── bsm.py          # All math functions — knows nothing about dataframes
├── chain.py        # Options chain construction — knows nothing about math internals
├── tests/
│   └── test_bsm.py # pytest validation against known values
└── main.py         # Entry point — orchestrates, displays results
```

Each file has one job. `bsm.py` computes math. `chain.py` organizes results. `main.py` calls both. This separation means adding Black-76 (futures pricing) later is just a new file, not a rewrite.

---

## Implementation Decisions

**Why `option_type` is a parameter, not two separate functions**

Delta for calls is `N(d1)`. For puts it's `N(d1) - 1`. They share 90% of their logic. One function with a parameter is cleaner than two parallel functions that diverge by one line — especially when you're running these across thousands of contracts in a loop.

**Why d2 takes d1 as input**

It's not a shortcut — that's the actual mathematical relationship. Expressing it this way makes the dependency explicit in code and avoids recomputing the expensive log/sqrt terms.

**Why helpers are extracted into small functions**

`black_scholes()` should read like a sentence. Extracting `compute_d1()`, `compute_d2()`, `call_price()`, `put_price()` means the top-level function communicates _what_ is happening without requiring the reader to parse _how_.

**Theta time unit parameter**

Theta from BSM is in per-year units. Traders think in per-day. `time_unit` parameter handles both without duplicating logic. Named `time_unit` rather than `filter` — `filter` is a Python builtin and shadowing builtins causes subtle bugs and confuses readers.

---

## Finite Difference Verification

The Greeks are derived analytically (closed form). They can be verified numerically using finite differences — the code approximation of a derivative from Calc 3:

```
f'(x) ≈ [f(x+h) - f(x-h)] / 2h
```

For example, numerical delta:

```python
numerical_delta = (call_price(S+h) - call_price(S-h)) / (2*h)
```

This should match `N(d1)` exactly within floating point tolerance. If it does, the implementation is correct. This is how each Greek was verified before moving to the next.

---

## Options Chain

The chain evaluates all Greeks across a **range of stock prices** at a fixed strike. Strike is fixed in the contract — what moves is the underlying stock. So the interesting question is: _as stock price drifts, how does my fixed contract's value and risk change?_

```python
S_range = np.linspace(150, 250, 100)
df = options_chain(S_range, K=210, T=0.25, r=0.05, sigma=0.30)
```

This produces a row per scenario — "if the stock were at this price, here's what everything looks like." A trader uses this as a **risk map** before entering a position.

Key observations in the output:

- Delta approaches 0.50 when stock price ≈ strike (at the money)
- Gamma peaks near the strike — delta is most unstable there
- Call price rises and put price falls as stock price increases

---

## Implied Volatility (Next)

Right now `σ` is an input. In practice you don't know the "true" volatility — the market gives you the contract price and you back-solve for the volatility it implies. There's no closed form for this, so it requires numerical root-finding (Newton-Raphson), using vega as the derivative:

```
σ_new = σ_old - (BSM_price(σ_old) - market_price) / vega(σ_old)
```

This is where the project becomes a real analytical tool: compare implied volatility (what the market expects) against historical volatility (what the stock has actually done) to identify potential mispricings.

---

## Roadmap

- [x] BSM pricing (call + put)
- [x] All 5 Greeks
- [x] Finite difference verification
- [x] Options chain across S range
- [ ] Implied volatility back-solving (Newton-Raphson)
- [ ] Live market data via `yfinance`
- [ ] Compare IV vs historical volatility
- [ ] Gradient descent portfolio optimizer (Markowitz mean-variance)
- [ ] Black-76 extension for commodities (oil, gold, silver)
- [ ] AWS data pipeline for running analysis at scale

---

## Resources

- **Paul Wilmott on Quantitative Finance** — rigorous BSM derivation from PDEs
- **Python for Finance** by Yves Hilpisch — practical numpy/scipy implementation patterns
- **MIT 18.S096** (OpenCourseWare) — bridges Calc 3 level math to derivatives pricing
- Drexel University BSM Calculator — used for output validation
