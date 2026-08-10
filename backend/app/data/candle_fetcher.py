import logging
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.data.instruments import INTERVAL_MAX_DAYS, get_instrument, parse_interval
from app.data.models import Candle
from app.data.smartapi_client import smartapi_client
from app.db.upsert import dialect_insert, upsert_do_nothing

logger = logging.getLogger(__name__)
IST = ZoneInfo("Asia/Kolkata")


def _parse_candle_row(row: list) -> dict:
    """Parse SmartAPI candle row: [timestamp, O, H, L, C, volume]."""
    ts = datetime.fromisoformat(row[0].replace("Z", "+00:00"))
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    return {
        "timestamp": ts,
        "open": float(row[1]),
        "high": float(row[2]),
        "low": float(row[3]),
        "close": float(row[4]),
        "volume": float(row[5]) if len(row) > 5 and row[5] is not None else 0.0,
    }


def _chunk_date_range(
    start: datetime, end: datetime, interval_key: str
) -> list[tuple[datetime, datetime]]:
    max_days = INTERVAL_MAX_DAYS.get(interval_key, 30)
    chunks: list[tuple[datetime, datetime]] = []
    cursor = start
    while cursor < end:
        chunk_end = min(cursor + timedelta(days=max_days), end)
        chunks.append((cursor, chunk_end))
        cursor = chunk_end + timedelta(minutes=1)
    return chunks


class CandleFetcher:
    def fetch_and_store(
        self,
        session: Session,
        instrument_symbol: str,
        interval: str,
        from_date: datetime,
        to_date: datetime,
        segment: str = "spot",
    ) -> dict:
        instrument = get_instrument(instrument_symbol, segment=segment)
        interval_key = interval.lower()
        smart_interval = parse_interval(interval_key)

        if from_date.tzinfo is None:
            from_date = from_date.replace(tzinfo=timezone.utc)
        if to_date.tzinfo is None:
            to_date = to_date.replace(tzinfo=timezone.utc)

        total_fetched = 0
        total_inserted = 0
        chunks = _chunk_date_range(from_date, to_date, interval_key)

        for chunk_start, chunk_end in chunks:
            rows = smartapi_client.get_candle_data(
                exchange=instrument.exchange,
                symbol_token=instrument.token,
                interval=smart_interval,
                from_date=chunk_start,
                to_date=chunk_end,
            )
            total_fetched += len(rows)
            if not rows:
                continue

            records = []
            for row in rows:
                parsed = _parse_candle_row(row)
                records.append(
                    {
                        "instrument": instrument.symbol,
                        "exchange": instrument.exchange,
                        "segment": instrument.segment,
                        "interval": interval_key,
                        **parsed,
                    }
                )

            stmt = dialect_insert(Candle).values(records)
            stmt = upsert_do_nothing(
                stmt,
                constraint="uq_candle",
                index_elements=["instrument", "exchange", "segment", "interval", "timestamp"],
            )
            result = session.execute(stmt)
            session.commit()
            total_inserted += result.rowcount or 0

        return {
            "instrument": instrument.key,
            "symbol": instrument.symbol,
            "segment": instrument.segment,
            "interval": interval_key,
            "from_date": from_date.isoformat(),
            "to_date": to_date.isoformat(),
            "fetched": total_fetched,
            "inserted": total_inserted,
            "chunks": len(chunks),
        }

    def get_candles(
        self,
        session: Session,
        instrument_symbol: str,
        interval: str,
        from_date: datetime | None = None,
        to_date: datetime | None = None,
        limit: int = 500,
        segment: str = "spot",
    ) -> list[Candle]:
        instrument = get_instrument(instrument_symbol, segment=segment)
        interval_key = interval.lower()

        stmt = (
            select(Candle)
            .where(
                Candle.instrument == instrument.symbol,
                Candle.segment == instrument.segment,
                Candle.interval == interval_key,
            )
            .order_by(Candle.timestamp.desc())
            .limit(limit)
        )

        if from_date:
            stmt = stmt.where(Candle.timestamp >= from_date)
        if to_date:
            stmt = stmt.where(Candle.timestamp <= to_date)

        result = session.execute(stmt)
        candles = list(result.scalars().all())
        candles.reverse()
        return candles


candle_fetcher = CandleFetcher()
