"""Per-trade investment & P&L report (IST). Usage: python trade_pnl_report.py [YYYY-MM-DD]"""
import json
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sqlalchemy import select

from app.data.models import SignalLog
from app.db.session import SyncSessionLocal
from app.services.signal_outcomes import enrich_history_row

IST = timezone(timedelta(hours=5, minutes=30))


def _parse_day(arg: str | None) -> date:
    if not arg:
        return datetime.now(IST).date()
    return date.fromisoformat(arg)


def _day_bounds(day: date) -> tuple[datetime, datetime]:
    start = datetime.combine(day, datetime.min.time()).replace(tzinfo=IST)
    end = start + timedelta(days=1)
    return start.astimezone(timezone.utc), end.astimezone(timezone.utc)


def _investment_inr(payload: dict) -> float:
    prem = float(payload.get("premium_required_inr") or 0)
    if prem > 0:
        return prem
    entry_prem = float(payload.get("entry_premium_estimate") or 0)
    lots = int(payload.get("position_size") or 1)
    lot_sizes = {"NIFTY": 25, "BANKNIFTY": 15, "FINNIFTY": 40, "SENSEX": 10}
    lot = lot_sizes.get(str(payload.get("instrument", "")).upper(), 25)
    if entry_prem > 0:
        return round(entry_prem * lot * max(lots, 1), 2)
    return 0.0


def main() -> None:
    day = _parse_day(sys.argv[1] if len(sys.argv) > 1 else None)
    start_utc, end_utc = _day_bounds(day)

    session = SyncSessionLocal()
    rows = list(
        session.execute(
            select(SignalLog)
            .where(SignalLog.created_at >= start_utc, SignalLog.created_at < end_utc)
            .order_by(SignalLog.created_at.asc())
        ).scalars()
    )

    seen: set[tuple] = set()
    trades: list[dict] = []
    total_invest = 0.0
    total_pnl = 0.0
    total_fut_pts = 0.0
    wins = fails = 0

    for row in rows:
        try:
            payload = json.loads(row.payload)
        except json.JSONDecodeError:
            continue

        is_take = bool(payload.get("can_take") or payload.get("trade_decision") == "TAKE")
        if not is_take:
            continue

        strike = payload.get("suggested_strike", "")
        otype = payload.get("option_type", "")
        option = f"{strike:.0f} {otype}".strip() if strike else ""
        key = (row.created_at.astimezone(IST).strftime("%H:%M"), payload.get("instrument"), option)
        if key in seen:
            continue
        seen.add(key)

        enriched = enrich_history_row(session, row, payload)
        opt = enriched.get("options_result") or {}
        pnl = float(opt.get("pnl_value") or 0)
        invest = _investment_inr(payload)
        verdict = enriched.get("options_verdict") or "—"
        if verdict == "WIN":
            wins += 1
        elif verdict == "FAIL":
            fails += 1

        total_invest += invest
        total_pnl += pnl
        total_fut_pts += float((enriched.get("futures_result") or {}).get("pnl_value") or 0)

        trades.append(
            {
                "time": row.created_at.astimezone(IST).strftime("%H:%M"),
                "setup": payload.get("setup_name", ""),
                "instrument": payload.get("instrument", ""),
                "option": option,
                "direction": payload.get("direction", ""),
                "decision": payload.get("trade_decision", ""),
                "investment_inr": round(invest, 2),
                "pnl_inr": round(pnl, 2),
                "pnl_pct": round((pnl / invest * 100), 2) if invest > 0 else None,
                "futures_pnl_pts": round(
                    float((enriched.get("futures_result") or {}).get("pnl_value") or 0), 2
                ),
                "result": verdict,
                "exit": opt.get("label", ""),
            }
        )

    # If no TAKE trades, show deduped fired setups with simulated P&L for the day
    if not trades:
        seen2: set[tuple] = set()
        for row in rows:
            try:
                payload = json.loads(row.payload)
            except json.JSONDecodeError:
                continue
            if payload.get("trade_decision") == "SIT_OUT":
                continue
            if not float(payload.get("underlying_entry") or 0):
                continue
            strike = payload.get("suggested_strike", "")
            otype = payload.get("option_type", "")
            option = f"{strike:.0f} {otype}".strip() if strike else ""
            hour = row.created_at.astimezone(IST).strftime("%H")
            key = (hour, payload.get("instrument"), payload.get("setup_name"), option)
            if key in seen2:
                continue
            seen2.add(key)

            enriched = enrich_history_row(session, row, payload)
            opt = enriched.get("options_result") or {}
            pnl = float(opt.get("pnl_value") or 0)
            if opt.get("outcome") not in ("profit", "sl_hit", "time_exit"):
                continue
            invest = _investment_inr(payload)
            verdict = enriched.get("options_verdict") or "—"
            if verdict == "WIN":
                wins += 1
            elif verdict == "FAIL":
                fails += 1
            total_invest += invest
            total_pnl += pnl
            total_fut_pts += float((enriched.get("futures_result") or {}).get("pnl_value") or 0)
            trades.append(
                {
                    "time": row.created_at.astimezone(IST).strftime("%H:%M"),
                    "setup": payload.get("setup_name", ""),
                    "instrument": payload.get("instrument", ""),
                    "option": option,
                    "direction": payload.get("direction", ""),
                    "decision": payload.get("trade_decision", ""),
                    "investment_inr": round(invest, 2),
                    "pnl_inr": round(pnl, 2),
                    "pnl_pct": round((pnl / invest * 100), 2) if invest > 0 else None,
                    "futures_pnl_pts": round(
                        float((enriched.get("futures_result") or {}).get("pnl_value") or 0), 2
                    ),
                    "result": verdict,
                    "exit": opt.get("label", ""),
                    "note": "simulated — was NO_TRADE",
                }
            )

    session.commit()
    session.close()

    closed = wins + fails
    print(
        json.dumps(
            {
                "date_ist": str(day),
                "trade_count": len(trades),
                "wins": wins,
                "losses": fails,
                "win_rate_pct": round(wins / closed * 100, 1) if closed else 0,
                "total_investment_inr": round(total_invest, 2),
                "total_pnl_inr": round(total_pnl, 2),
                "net_return_pct": round(total_pnl / total_invest * 100, 2) if total_invest else 0,
                "total_futures_pnl_pts": round(total_fut_pts, 2),
                "trades": trades,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
