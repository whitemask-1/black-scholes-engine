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

    def on_mount(self) -> None:
        self._ticker_timer = None
        self._chain_generation = 0

    def on_unmount(self) -> None:
        if self._ticker_timer is not None:
            self._ticker_timer.stop()

    def on_input_changed(self, event: Input.Changed) -> None:
        if event.input.id != "ticker":
            return
        if self._ticker_timer is not None:
            self._ticker_timer.stop()
        self._ticker_timer = self.set_timer(
            0.5, lambda: self._fetch_expirations(event.value.strip().upper())
        )

    @work(thread=True)
    def _fetch_expirations(self, symbol: str) -> None:
        if not symbol:
            self.call_from_thread(self._clear_all)
            return
        try:
            expirations = yf.Ticker(symbol).options
        except Exception as e:
            self.call_from_thread(self._set_status, f"Error fetching {symbol}: {e}")
            self.call_from_thread(self._clear_all)
            return
        if expirations:
            self.call_from_thread(self._set_expirations, symbol, expirations)
        else:
            self.call_from_thread(self._clear_all)

    def _set_expirations(self, symbol: str, expirations: tuple[str, ...]) -> None:
        current = self.query_one("#ticker", Input).value.strip().upper()
        if current != symbol:
            self._set_status("")
            return
        select = self.query_one("#expiration", Select)
        select.set_options([(e, e) for e in expirations])
        select.disabled = False
        self._set_status(f"{symbol}: {len(expirations)} expiration dates available")

    def _clear_all(self) -> None:
        select = self.query_one("#expiration", Select)
        select.set_options([])
        select.disabled = True
        self.query_one("#chain", DataTable).clear(columns=True)
        self._set_status("")

    def _set_status(self, msg: str) -> None:
        self.query_one("#status", Label).update(msg)

    def on_select_changed(self, event: Select.Changed) -> None:
        if event.select.id not in ("expiration", "option-type"):
            return
        expiration = self.query_one("#expiration", Select).value
        if expiration is Select.BLANK or expiration is None:
            return
        symbol = self.query_one("#ticker", Input).value.strip().upper()
        option_type = self.query_one("#option-type", Select).value
        if option_type is Select.BLANK or option_type is None:
            return
        self._chain_generation += 1
        self._fetch_chain(symbol, expiration, option_type, self._chain_generation)  # type: ignore[call-arg]

    @work(thread=True)
    def _fetch_chain(self, symbol: str, expiration: str, option_type: str, generation: int) -> None:
        if not symbol:
            return
        self.call_from_thread(
            self._set_status,
            f"Loading {symbol} {option_type} chain for {expiration}...",
        )
        try:
            df = analyze_live(symbol, expiration, option_type)
            self.call_from_thread(self._populate_table, df, generation)
        except Exception as e:
            self.call_from_thread(self._set_status, f"Error: {e}")

    def _populate_table(self, df, generation: int) -> None:
        if generation != self._chain_generation:
            return
        if df is None or df.empty:
            self._set_status("No data returned")
            return
        table = self.query_one("#chain", DataTable)
        table.clear(columns=True)
        for col in df.columns:
            table.add_column(col.upper(), key=col)
        for _, row in df.iterrows():
            table.add_row(
                *[f"{v:.4f}" if isinstance(v, float) else str(v) for v in row]
            )
        self._set_status(f"{len(df)} rows loaded")


if __name__ == "__main__":
    BSMApp().run()
