from dataclasses import dataclass

from datetime import date, datetime, time, timedelta

from zoneinfo import ZoneInfo



from sqlalchemy import func, select

from sqlalchemy.orm import Session



from app.data.instruments import INTERVAL_MINUTES, get_instrument

from app.data.models import Candle



IST = ZoneInfo("Asia/Kolkata")

MARKET_OPEN = time(9, 15)

MARKET_CLOSE = time(15, 30)





@dataclass

class GapInfo:

    start: datetime

    end: datetime

    missing_bars: int





def _is_trading_day(d: date) -> bool:

    return d.weekday() < 5





def _expected_timestamps(interval: str, start: date, end: date) -> list[datetime]:

    minutes = INTERVAL_MINUTES.get(interval)

    if not minutes:

        raise ValueError(f"Gap check unsupported for interval: {interval}")



    expected: list[datetime] = []

    cursor = start

    while cursor <= end:

        if _is_trading_day(cursor):

            if interval == "1d":

                expected.append(datetime.combine(cursor, MARKET_OPEN, tzinfo=IST))

            else:

                bar = datetime.combine(cursor, MARKET_OPEN, tzinfo=IST)

                close_dt = datetime.combine(cursor, MARKET_CLOSE, tzinfo=IST)

                while bar <= close_dt:

                    expected.append(bar)

                    bar += timedelta(minutes=minutes)

        cursor += timedelta(days=1)

    return expected





def check_gaps(

    session: Session,

    instrument_symbol: str,

    interval: str,

    from_date: date,

    to_date: date,

    segment: str = "spot",

    max_gaps: int = 50,

) -> dict:

    instrument = get_instrument(instrument_symbol, segment=segment)

    interval_key = interval.lower()



    start_dt = datetime.combine(from_date, MARKET_OPEN, tzinfo=IST)

    end_dt = datetime.combine(to_date, MARKET_CLOSE, tzinfo=IST)



    stmt = (

        select(Candle.timestamp)

        .where(

            Candle.instrument == instrument.symbol,

            Candle.segment == instrument.segment,

            Candle.interval == interval_key,

            Candle.timestamp >= start_dt,

            Candle.timestamp <= end_dt,

        )

        .order_by(Candle.timestamp)

    )

    rows = session.execute(stmt).scalars().all()

    actual = {ts.astimezone(IST).replace(second=0, microsecond=0) for ts in rows}



    expected = _expected_timestamps(interval_key, from_date, to_date)

    missing = [ts for ts in expected if ts not in actual]



    gaps: list[GapInfo] = []

    if missing:

        gap_start = missing[0]

        prev = missing[0]

        for ts in missing[1:]:

            step = timedelta(minutes=INTERVAL_MINUTES[interval_key])

            if ts - prev > step:

                gaps.append(

                    GapInfo(

                        start=gap_start,

                        end=prev,

                        missing_bars=int((prev - gap_start) / step) + 1,

                    )

                )

                gap_start = ts

            prev = ts

        step = timedelta(minutes=INTERVAL_MINUTES[interval_key])

        gaps.append(

            GapInfo(

                start=gap_start,

                end=prev,

                missing_bars=int((prev - gap_start) / step) + 1,

            )

        )



    count_stmt = select(func.count()).select_from(Candle).where(

        Candle.instrument == instrument.symbol,

        Candle.segment == instrument.segment,

        Candle.interval == interval_key,

        Candle.timestamp >= start_dt,

        Candle.timestamp <= end_dt,

    )

    stored_count = session.execute(count_stmt).scalar() or 0



    return {

        "instrument": instrument.key,

        "symbol": instrument.symbol,

        "segment": instrument.segment,

        "interval": interval_key,

        "from_date": from_date.isoformat(),

        "to_date": to_date.isoformat(),

        "expected_bars": len(expected),

        "stored_bars": stored_count,

        "missing_bars": len(missing),

        "coverage_pct": round((stored_count / len(expected) * 100) if expected else 0, 2),

        "gaps": [

            {

                "start": g.start.isoformat(),

                "end": g.end.isoformat(),

                "missing_bars": g.missing_bars,

            }

            for g in gaps[:max_gaps]

        ],

        "has_gaps": len(missing) > 0,

    }

