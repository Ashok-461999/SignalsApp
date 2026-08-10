from dataclasses import dataclass
from datetime import date


@dataclass
class Instrument:
    symbol: str
    name: str
    exchange: str
    token: str
    segment: str  # spot | futures
    ws_token: str = ""
    ws_exchange_type: int = 1
    expiry: date | None = None
    enabled: bool = True
    availability_note: str = ""

    @property
    def key(self) -> str:
        if self.segment == "spot":
            return self.symbol
        return f"{self.symbol}_FUT"

    @property
    def storage_symbol(self) -> str:
        return self.key


# SmartAPI WebSocket exchange types
WS_NSE_CM = 1
WS_NSE_FO = 2
WS_BSE_CM = 3
WS_BSE_FO = 4


def _ws_token(rest_token: str) -> str:
    """Strip 999 prefix used by REST index tokens for WebSocket subscription."""
    if rest_token.startswith("999"):
        return rest_token[3:]
    return rest_token


SPOT_INSTRUMENTS: dict[str, Instrument] = {
    "NIFTY": Instrument(
        symbol="NIFTY",
        name="Nifty 50",
        exchange="NSE",
        token="99926000",
        segment="spot",
        ws_token="26000",
        ws_exchange_type=WS_NSE_CM,
    ),
    "BANKNIFTY": Instrument(
        symbol="BANKNIFTY",
        name="Nifty Bank",
        exchange="NSE",
        token="99926009",
        segment="spot",
        ws_token="26009",
        ws_exchange_type=WS_NSE_CM,
    ),
    "SENSEX": Instrument(
        symbol="SENSEX",
        name="SENSEX",
        exchange="BSE",
        token="99919000",
        segment="spot",
        ws_token="19000",
        ws_exchange_type=WS_BSE_CM,
    ),
}

# Mutable registry — futures entries added at startup by instrument_master
INSTRUMENTS: dict[str, Instrument] = dict(SPOT_INSTRUMENTS)

# Runtime flags set during BSE F&O verification
DATA_LAYER_STATUS: dict[str, object] = {
    "sensex_futures_available": None,
    "sensex_futures_note": "",
    "bse_fo_verified": False,
}

LIVE_INTERVALS = ("1m", "5m", "15m")
HISTORICAL_INTERVALS = ("1m", "5m", "15m", "1h", "1d")

INTERVALS = {
    "1m": "ONE_MINUTE",
    "5m": "FIVE_MINUTE",
    "15m": "FIFTEEN_MINUTE",
    "1h": "ONE_HOUR",
    "1d": "ONE_DAY",
}

INTERVAL_MINUTES = {
    "1m": 1,
    "5m": 5,
    "15m": 15,
    "1h": 60,
    "1d": 375,
}

INTERVAL_MAX_DAYS: dict[str, int] = {
    "1m": 30,
    "5m": 100,
    "15m": 200,
    "1h": 400,
    "1d": 2000,
}

BASE_SYMBOLS = ("NIFTY", "BANKNIFTY", "SENSEX")


def parse_interval(interval: str) -> str:
    key = interval.lower()
    if key not in INTERVALS:
        raise ValueError(f"Unsupported interval: {interval}. Use one of {list(INTERVALS)}")
    return INTERVALS[key]


def get_instrument(symbol: str, segment: str = "spot") -> Instrument:
    key = symbol.upper()
    if segment == "futures":
        key = f"{key}_FUT"
    if key not in INSTRUMENTS:
        raise ValueError(f"Unknown instrument: {symbol} (segment={segment})")
    inst = INSTRUMENTS[key]
    if not inst.enabled:
        raise ValueError(f"Instrument unavailable: {key}. {inst.availability_note}")
    return inst


def list_enabled_instruments() -> list[Instrument]:
    return [inst for inst in INSTRUMENTS.values() if inst.enabled]


def register_futures_instrument(inst: Instrument) -> None:
    INSTRUMENTS[inst.key] = inst


def set_sensex_futures_status(available: bool, note: str) -> None:
    DATA_LAYER_STATUS["sensex_futures_available"] = available
    DATA_LAYER_STATUS["sensex_futures_note"] = note
    DATA_LAYER_STATUS["bse_fo_verified"] = True
    if not available and "SENSEX_FUT" in INSTRUMENTS:
        fut = INSTRUMENTS["SENSEX_FUT"]
        INSTRUMENTS["SENSEX_FUT"] = Instrument(
            symbol=fut.symbol,
            name=fut.name,
            exchange=fut.exchange,
            token=fut.token,
            segment=fut.segment,
            ws_token=fut.ws_token,
            ws_exchange_type=fut.ws_exchange_type,
            expiry=fut.expiry,
            enabled=False,
            availability_note=note,
        )
