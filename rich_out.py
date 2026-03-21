from rich.table import Table
from rich.console import Console
from market import find_ticker_stock_price

def display_manual_chain(df, symbol="Manual"):
    console = Console()

    table = Table(title=f" {symbol} Options Chain")
    for col in df.columns:
        table.add_column(col, justify="right")
    for _, row in df.iterrows():
        table.add_row(*[f"{v:.4f}" if isinstance(v, float) else str(v) for v in row])
    console.print(table)

def display_live_chain(df, symbol, expiration_date, option_type):
    console = Console()

    current_stock_price = find_ticker_stock_price(symbol)
    table = Table(title=f" {symbol} {option_type.upper()} Options Chain - {expiration_date} - (Current Stock Price = {current_stock_price})")
    for col in df.columns:
        table.add_column(col, justify="right")
    for _, row in df.iterrows():
        table.add_row(*[f"{v:.4f}" if isinstance(v, float) else str(v) for v in row])
    console.print(table)
