# Black-Scholes Options Pricing Engine

A from-scratch implementation of the Black-Scholes-Merton (BSM) pricing model built to understand quantitative finance through the lens of applied mathematics — specifically how multivariable calculus and PDEs map directly to real financial instruments. Connects to live market data to back-solve implied volatility and surface potential mispricings against historical volatility.

---

## The Math Story

### Origins

In 1900, Louis Bachelier published his doctoral thesis _Théorie de la Spéculation_ —
the first mathematical treatment of random walk applied to financial markets. He
modeled price movements as a stochastic process five years before Einstein's paper
on Brownian motion. The work was largely ignored for six decades until Paul Samuelson
rediscovered it in the 1950s and formalized it as geometric Brownian motion — the
foundation BSM is built on.

Black, Scholes, and Merton published the pricing model in 1973. Merton and Scholes
were awarded the Nobel Prize in Economics in 1997.

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

In live mode, `S`, `r`, and `T` are fetched automatically. `r` is pulled from the appropriate Treasury yield based on time to expiration — 3-month T-bill for short-dated contracts, 5-year for medium, 10-year for long.

---

## Output

### Prices

- **Call price** — fair premium for the right to _buy_ at strike K
- **Put price** — fair premium for the right to _sell_ at strike K

All prices are quoted per share. Market convention is 100 shares per contract.

### The Greeks (Risk Dimensions)

| Greek | Derivative | Meaning                                         |
| ----- | ---------- | ----------------------------------------------- |
| Delta | ∂C/∂S      | How much the price changes per $1 move in stock |
| Gamma | ∂²C/∂S²    | How fast delta itself is changing               |
| Theta | ∂C/∂t      | Value lost per day from time passing            |
| Vega  | ∂C/∂σ      | Sensitivity to a change in volatility           |
| Rho   | ∂C/∂r      | Sensitivity to a change in interest rate        |

Traders use Greeks for **risk management**, not just pricing. A market maker selling thousands of contracts needs to know total exposure if the market moves 2% tomorrow — that's delta. Greeks quantify each risk dimension independently.

---

## Project Structure

```
bsm/
├── bsm.py          # All math functions — knows nothing about dataframes or market data
├── chain.py        # Options chain construction — knows nothing about math internals
├── market.py       # Live market data fetching, IV back-solving, HV computation
├── rich_out.py     # Terminal table rendering via rich
├── tests/
│   └── test_bsm.py # pytest validation against known values and finite difference verification
└── main.py         # Entry point — manual mode and live mode
```

Each file has one job. `bsm.py` computes math. `chain.py` organizes manual results. `market.py` handles everything external. `main.py` orchestrates both modes.

---

## Modes

```bash
python main.py manual   # run BSM across a synthetic price range with fixed inputs
python main.py live     # pull live market data and analyze real options chains
```

---

## OCaml Compute Backend

All pricing, Greeks, and IV solving are handled by the native OCaml binary. Python handles market data fetching, wrangling, and display while OCaml handles the math.

### Why OCaml

BSM math is computationally pure meaning there is no I/O or side effects, only floating point arithmetic over the options chain. OCaml compiles to native code and reuns the calculations much faster than CPython by reducing the operations that need to be done by the computer and avoiding the issues that come with arithmetic in garbage collected languages like Python.

The integration uses a subprocess bridge, Python spwans OCaml binary once per row, passes inputs, and reads back a JSON object

## Implementation Decisions

**Why `option_type` is a parameter, not two separate functions**

Delta for calls is `N(d1)`. For puts it's `N(d1) - 1`. They share 90% of their logic. One function with a parameter is cleaner than two parallel functions that diverge by one line — especially when running these across thousands of contracts in a loop.

**Why d2 takes d1 as input**

It's not a shortcut — that's the actual mathematical relationship. Expressing it this way makes the dependency explicit in code and avoids recomputing the expensive log/sqrt terms.

**Why helpers are extracted into small functions**

`black_scholes()` should read like a sentence. Extracting `compute_d1()`, `compute_d2()`, `call_price()`, `put_price()` means the top-level function communicates _what_ is happening without requiring the reader to parse _how_.

**Theta time unit parameter**

Theta from BSM is in per-year units. Traders think in per-day. A `time_unit` parameter handles both without duplicating logic. Named `time_unit` rather than `filter` — `filter` is a Python builtin and shadowing builtins causes subtle bugs.

**Why bid/ask midpoint is preferred over lastPrice**

`lastPrice` reflects the most recent trade, which can be hours old for illiquid contracts. The bid/ask midpoint is a live estimate of fair value. The spread between bid and ask also signals liquidity — a wide spread means the contract trades infrequently and pricing is less reliable.

**Why IV is back-solved rather than taken from the data provider**

Using our own Newton-Raphson implementation against the actual BSM model guarantees consistency — the IV we compute is exactly the sigma that makes our model reprice the contract correctly. Provider-supplied IV may use different models or conventions.

**Why OCaml uses typed float operators**

OCaml has no implicit numeric casting. + is integer addition, +. is float addition — mixing them is a compile error. For financial math this is a feature: a misplaced integer operation that silently truncates a float is caught at build time, not at runtime with wrong numbers.

---

## Finite Difference Verification

The Greeks are derived analytically (closed form). They are verified numerically using finite differences — the computational approximation of a derivative:

```
f'(x) ≈ [f(x+h) - f(x-h)] / 2h
```

For example, numerical delta:

```python
numerical_delta = (call_price(S+h) - call_price(S-h)) / (2*h)
```

This matches `N(d1)` within floating point tolerance, confirming the implementation is correct. Each Greek was verified this way before moving to the next. These checks are encoded in the test suite and run with `pytest tests/ -v`.

---

## Implied Volatility

`σ` is back-solved from live market prices using Newton-Raphson, with vega as the derivative:

```
σ_new = σ_old - (BSM_price(σ_old) - market_price) / vega(σ_old)
```

This inverts the model: instead of computing a price from volatility, it extracts the volatility the market is pricing in. The solver guards against division by zero near expiry and deep out-of-the-money contracts where vega approaches zero.

---

## IV vs Historical Volatility

Implied volatility reflects what the market _expects_ future movement to be. Historical volatility reflects what the stock _actually_ moved over the past 90 days, annualized:

```python
returns = np.log(hist["Close"] / hist["Close"].shift(1)).dropna()
hv = returns.std() * np.sqrt(252)
```

The spread between IV and HV is the primary signal. When IV significantly exceeds HV, the market is pricing in more uncertainty than history suggests — the option is expensive relative to realized volatility. When IV is below HV, options are cheap.

---

## Resources

- **Paul Wilmott on Quantitative Finance** — rigorous BSM derivation from PDEs
- **Python for Finance** by Yves Hilpisch — practical numpy/scipy implementation patterns
- **MIT 18.S096** (OpenCourseWare) — bridges Calc 3 level math to derivatives pricing
