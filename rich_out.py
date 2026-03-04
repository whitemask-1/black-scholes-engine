from rich.table import Table
from rich.console import Console


def display_chain(df, symbol):
    console = Console()

    table = Table(title=f" {symbol} Options Chain")
    for col in df.columns:
        table.add_column(col, justify="right")
    for _, row in df.iterrows():
        table.add_row(*[f"{v:.4f}" if isinstance(v, float) else str(v) for v in row])
    console.print(table)
