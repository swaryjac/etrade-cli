"""Tests for lib/acct/report.py (slice 1: put premium income + positions).

Stdlib unittest only. Run with:  python3 -m unittest tests.test_report
"""

import json
import sys
import tempfile
import unittest
from datetime import date
from decimal import Decimal
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "lib" / "acct"))

import report  # noqa: E402
from model import Instrument, Option, Transaction  # noqa: E402

_SEQ = [0]


def txn(action, *, symbol=None, call_put=None, strike=None, expiry=None,
        on=None, amount=None, qty=1, itype=None):
    """Build a Transaction for tests. Defaults to an OPTION when call_put given."""
    _SEQ[0] += 1
    option = None
    if call_put is not None:
        option = Option(call_put=call_put,
                        strike=None if strike is None else Decimal(str(strike)),
                        expiry=expiry)
    inst_type = itype or ("OPTION" if option else "CASH")
    return Transaction(
        transaction_id=str(_SEQ[0]),
        date=on,
        action=action,
        instrument=Instrument(type=inst_type, symbol=symbol, option=option),
        qty=None if qty is None else Decimal(str(qty)),
        price=None,
        fee=None,
        amount=None if amount is None else Decimal(str(amount)),
        transaction_type=None,
        description=None,
        raw={},
    )


def put(symbol, strike, expiry, on, amount, action="SELL_TO_OPEN", qty=-1):
    return txn(action, symbol=symbol, call_put="PUT", strike=strike,
              expiry=expiry, on=on, amount=amount, qty=qty)


WK1 = date(2026, 5, 4)   # Monday -> week ending Fri 2026-05-08
WK2 = date(2026, 5, 11)  # Monday -> week ending Fri 2026-05-15


class WeeklyPremiumTests(unittest.TestCase):
    def test_groups_by_friday_with_running_total(self):
        txns = [
            put("FIGR", 33.5, date(2026, 5, 8), WK1, "44.48"),
            put("NNE", 21.5, date(2026, 5, 8), WK1, "39.48"),
            put("USAR", 23.0, date(2026, 5, 8), WK1, "30.48"),
            put("OKLO", 65.0, date(2026, 5, 15), WK2, "74.48"),
        ]
        rows = report.weekly_put_premium(txns)
        self.assertEqual(len(rows), 2)

        self.assertEqual(rows[0].week_ending, date(2026, 5, 8))
        self.assertEqual(rows[0].contracts, Decimal(3))  # qty sign ignored
        self.assertEqual(rows[0].premium, Decimal("114.44"))
        self.assertEqual(rows[0].cumulative, Decimal("114.44"))

        self.assertEqual(rows[1].week_ending, date(2026, 5, 15))
        self.assertEqual(rows[1].premium, Decimal("74.48"))
        self.assertEqual(rows[1].cumulative, Decimal("188.92"))

    def test_ignores_calls_stock_and_cash(self):
        txns = [
            put("FIGR", 33.5, date(2026, 5, 8), WK1, "44.48"),
            txn("SELL_TO_OPEN", symbol="OKLO", call_put="CALL", strike=76,
                expiry=date(2026, 5, 8), on=WK1, amount="100.00"),  # covered call
            txn("SELL", symbol="QQX", on=WK1, amount="1899.94", itype="STOCK"),
            txn("INTEREST", on=WK1, amount="0.12"),
        ]
        rows = report.weekly_put_premium(txns)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0].premium, Decimal("44.48"))
        self.assertEqual(rows[0].contracts, Decimal(1))


class PositionBookTests(unittest.TestCase):
    def test_expired_put(self):
        exp = date(2026, 5, 8)
        book = report.build_positions([
            put("FIGR", 33.5, exp, WK1, "44.48"),
            put("FIGR", 33.5, exp, exp, None, action="EXPIRE", qty=1),
        ])
        (lot,) = list(book.lots())
        self.assertEqual(lot.outcome(), "EXPIRED")
        self.assertEqual(lot.remaining, Decimal(0))
        self.assertEqual(book.outcome_counts()["EXPIRED"], 1)
        self.assertEqual(book.orphans, [])

    def test_assigned_put(self):
        exp = date(2026, 5, 15)
        book = report.build_positions([
            put("OKLO", 65.0, exp, WK2, "74.48"),
            put("OKLO", 65.0, exp, exp, None, action="ASSIGN", qty=1),
        ])
        (lot,) = list(book.lots())
        self.assertEqual(lot.outcome(), "ASSIGNED")

    def test_still_open_put(self):
        book = report.build_positions([put("NNE", 21.5, date(2026, 6, 19), WK2, "20")])
        (lot,) = list(book.lots())
        self.assertEqual(lot.outcome(), "OPEN")
        self.assertEqual(lot.remaining, Decimal(1))

    def test_orphan_close_when_open_predates_window(self):
        exp = date(2026, 5, 1)
        book = report.build_positions([
            put("NVTS", 14.0, exp, date(2026, 5, 4), None, action="EXPIRE", qty=1),
        ])
        self.assertEqual(list(book.lots()), [])
        self.assertEqual(len(book.orphans), 1)
        self.assertEqual(book.orphans[0].unmatched, Decimal(1))

    def test_matches_regardless_of_storage_order(self):
        # The journal is stored newest-first; the close must still match its
        # earlier open once build_positions re-orders chronologically.
        exp = date(2026, 5, 8)
        open_txn = put("FIGR", 33.5, exp, WK1, "44.48")
        close_txn = put("FIGR", 33.5, exp, exp, None, action="EXPIRE", qty=1)
        book = report.build_positions([close_txn, open_txn])  # close listed first
        (lot,) = list(book.lots())
        self.assertEqual(lot.outcome(), "EXPIRED")
        self.assertEqual(book.orphans, [])

    def test_partial_close_consumes_fifo(self):
        exp = date(2026, 5, 8)
        book = report.build_positions([
            put("FIGR", 33.5, exp, WK1, "88.96", qty=-2),  # opened 2 contracts
            put("FIGR", 33.5, exp, exp, None, action="EXPIRE", qty=1),  # 1 expires
        ])
        (lot,) = list(book.lots())
        self.assertEqual(lot.opened, Decimal(2))
        self.assertEqual(lot.remaining, Decimal(1))
        self.assertEqual(lot.outcome(), "PARTIAL")


class JournalIntegrationTests(unittest.TestCase):
    def test_load_journal_round_trip_then_report(self):
        records = [
            put("FIGR", 33.5, date(2026, 5, 8), WK1, "44.48").to_record(),
            put("OKLO", 65.0, date(2026, 5, 15), WK2, "74.48").to_record(),
        ]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "transactions" / "ACCT.jsonl"
            path.parent.mkdir(parents=True)
            path.write_text("".join(json.dumps(r, default=str) + "\n" for r in records))

            loaded = report.load_journal(str(path))
            rows = report.weekly_put_premium(loaded)
            self.assertEqual([r.premium for r in rows],
                             [Decimal("44.48"), Decimal("74.48")])
            self.assertEqual(rows[-1].cumulative, Decimal("118.96"))


if __name__ == "__main__":
    unittest.main()
