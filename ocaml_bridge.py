import subprocess
from pathlib import Path
import json

BINARY = Path(__file__).parent / "bsm_engine/_build/default/bin/main.exe"

def analyze(s, k, t, r, market_price, option_type="call") -> dict | None:
    result = subprocess.run(
        [str(BINARY), str(s), str(k), str(t), str(r), str(market_price), option_type],
        capture_output=True, text=True, check=True
    )
    data = json.loads(result.stdout)
    return None if "error" in data else data
