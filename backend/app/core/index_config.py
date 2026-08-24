"""Indian index constants — scanner, options, predictions."""

INDEX_SYMBOLS: tuple[str, ...] = ("NIFTY", "BANKNIFTY", "FINNIFTY", "SENSEX")

LOT_SIZES: dict[str, int] = {
    "NIFTY": 25,
    "BANKNIFTY": 15,
    "FINNIFTY": 40,
    "SENSEX": 10,
}

# Typical intraday swing targets (points on the index)
MOVE_POINT_TARGETS: dict[str, int] = {
    "NIFTY": 100,
    "FINNIFTY": 100,
    "BANKNIFTY": 300,
    "SENSEX": 350,
}

STRIKE_STEPS: dict[str, int] = {
    "NIFTY": 50,
    "FINNIFTY": 50,
    "BANKNIFTY": 100,
    "SENSEX": 100,
}

INDEX_DISPLAY: dict[str, str] = {
    "NIFTY": "Nifty 50",
    "BANKNIFTY": "Bank Nifty",
    "FINNIFTY": "Fin Nifty",
    "SENSEX": "Sensex",
}
