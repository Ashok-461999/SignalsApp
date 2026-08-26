"""Print today's TAKE signal P&L summary (IST)."""
import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sqlalchemy import select

from app.data.models import SignalLog
from app.db.session import SyncSessionLocal
from app.services.signal_outcomes import enrich_history_row

IST = timezone(timedelta(hours=5, minutes=30))
today = datetime.now(IST).date()
start_ist = datetime.combine(today, datetime.min.time()).replace(tzinfo=IST)
end_ist = start_ist + timedelta(days=1)
start_utc = start_ist.astimezone(timezone.utc)
end_utc = end_ist.astimezone(timezone.utc)

session = SyncSessionLocal()
rows = list(
    session.execute(
        select(SignalLog).where(
            SignalLog.created_at >= start_utc,
            SignalLog.created_at < end_utc,
        ).order_by(SignalLog.created_at.asc())
    ).scalars()
)

opt_pnl = 0.0
fut_pnl = 0.0
wins = fails = open_n = 0
take_count = 0
all_count = 0
details = []
all_details = []

for row in rows:
    try:
        payload = json.loads(row.payload)
    except json.JSONDecodeError:
        continue
    all_count += 1
    enriched = enrich_history_row(session, row, payload)
    opt = enriched.get("options_result") or {}
    fut = enriched.get("futures_result") or {}
    ov = enriched.get("options_verdict") or ""
    op = opt.get("pnl_value")
    fp = fut.get("pnl_value")
    td = payload.get("trade_decision", "")
    is_take = bool(payload.get("can_take") or td == "TAKE")
    strike = payload.get("suggested_strike", "")
    otype = payload.get("option_type", "")
    entry = {
        "time_ist": row.created_at.astimezone(IST).strftime("%H:%M"),
        "setup": payload.get("setup_name"),
        "instrument": payload.get("instrument"),
        "decision": td,
        "option": f"{strike} {otype}".strip(),
        "verdict": ov,
        "options_pnl_inr": op,
        "futures_pnl_pts": fp,
    }
    all_details.append(entry)
    if not is_take:
        continue
    take_count += 1
    if op is not None:
        opt_pnl += float(op)
    if fp is not None:
        fut_pnl += float(fp)
    if ov == "WIN":
        wins += 1
    elif ov == "FAIL":
        fails += 1
    elif ov == "OPEN":
        open_n += 1
    details.append(entry)

session.commit()
session.close()

print(
    json.dumps(
        {
            "date_ist": str(today),
            "logged_signals": all_count,
            "take_signals": take_count,
            "wins": wins,
            "fails": fails,
            "open": open_n,
            "win_rate_pct": round(wins / (wins + fails) * 100, 1) if (wins + fails) else 0,
            "options_pnl_inr": round(opt_pnl, 2),
            "futures_pnl_pts": round(fut_pnl, 2),
            "trades": details,
            "all_evaluations": all_details,
        },
        indent=2,
    )
)
