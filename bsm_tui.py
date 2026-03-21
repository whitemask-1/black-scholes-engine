import yfinance as yf
from textual.app import App, ComposeResult
from textual.containers import Horizontal
from textual.widgets import DataTable, Input, Label, Select
from textual import work

from market import analyze_live


class BSMApp(App):
    CSS = """
    #header {
        height: 3;
        padding: 0 1;
        background: $panel;
        align: left middle;
    }
    #header Label {
        margin: 0 1 0 0;
        color: $text-muted;
    }
    #ticker {
        width: 12;
    }
    #expiration {
        width: 20;
    }
    #option-type {
        width: 10;
    }
    #chain {
        height: 1fr;
    }
    #status {
        height: 1;
        padding: 0 1;
        background: $panel;
        color: $text-muted;
    }
    """

    def compose(self) -> ComposeResult:
        with Horizontal(id="header"):
            yield Label("Ticker:")
            yield Input(placeholder="AAPL", id="ticker")
            yield Label("Expiration:")
            yield Select([], id="expiration", disabled=True, prompt="—")
            yield Label("Type:")
            yield Select(
                [("call", "call"), ("put", "put")],
                id="option-type",
                value="call",
            )
        yield DataTable(id="chain")
        yield Label("", id="status")


if __name__ == "__main__":
    BSMApp().run()
