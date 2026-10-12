# BSM TUI Design

Date: 2026-03-21

## Overview

A Textual-based TUI for the Black-Scholes model that replaces the current CLI prompt flow with a reactive single-page interface. Users can explore live options chains by entering a ticker symbol, selecting an expiration date, and choosing call or put — with the chain rendering automatically on each change.

## Layout

```
┌─────────────────────────────────────────────────────────────────┐
│ Ticker: [AAPL____]  Expiration: [2025-06-20 ▼]  Type: [call ▼] │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  strike  bid   ask   market_price  iv    delta  gamma  theta   │
│  ------  ----  ----  ------------  ----  -----  -----  -----   │
│  ...                                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
│ Status: Loading AAPL...                                         │
└─────────────────────────────────────────────────────────────────┘
```

Single-page reactive app with an inline header bar and a full-width DataTable below.

## Components

- **Header bar** (`Horizontal` layout): `Input` for ticker, `Select` for expiration date, `Select` for option type (call/put).
- **DataTable**: Full-width scrollable table showing all columns returned by `analyze_live()` — `strike`, `bid`, `ask`, `market_price`, `iv`, `delta`, `gamma`, `theta`, `vega`, `hv`, `iv_hv_spread`.
- **Status bar**: Footer label showing current state (idle, loading, error message).

## Data Flow

1. User types in ticker `Input`.
2. After a 500ms debounce, the app calls `yf.Ticker(symbol).options` in a background worker.
3. If valid dates returned → populate expiration `Select`, enable it. If error or empty → disable `Select`, clear the table.
4. User selects an expiration date or changes option type → triggers `analyze_live(symbol, expiration, option_type)` in a background worker.
5. Worker result posts back to the main thread → `DataTable` is cleared and repopulated.
6. Status bar reflects loading/idle/error state throughout.

## Behavior Rules

- Expiration `Select` is disabled until a valid ticker is confirmed.
- Any change to expiration or option type triggers a full chain reload.
- Invalid ticker (no options, network error) clears the table and disables expiration select.
- Option type defaults to `call`.
- All network/compute work runs in Textual workers to avoid blocking the UI.

## Files Changed

- `bsm_tui.py` — full implementation (currently empty).
- No changes to `market.py`, `chain.py`, `rich_out.py`, or `main.py`.
