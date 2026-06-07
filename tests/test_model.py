"""Tests for lib/acct/model.py (typed Transaction domain model).

Stdlib unittest only, to match the project's no-extra-dependencies ethos.
Run with:  python3 -m unittest tests.test_model
"""

import json
import sys
import unittest
from datetime import date
from decimal import Decimal
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "lib" / "acct"))

from model import Instrument, Option, Transaction  # noqa: E402

FIXTURE = REPO_ROOT / "tests" / "fixtures" / "acct" / "transactions_response.json"


def load_txns():
    with open(FIXTURE, encoding="utf-8") as handle:
        response = json.load(handle, parse_float=Decimal)
    return response["TransactionListResponse"]["Transaction"]


def by_id():
    return {t["transactionId"]: Transaction.from_etrade(t) for t in load_txns()}


class FromEtradeTests(unittest.TestCase):
    def setUp(self):
        self.txns = by_id()

    def test_option_fields_are_typed(self):
        txn = self.txns["90000000000001"]
        self.assertEqual(txn.action, "SELL_TO_OPEN")
        self.assertEqual(txn.date, date(2026, 5, 18))
        self.assertEqual(txn.instrument.type, "OPTION")
        self.assertEqual(txn.instrument.symbol, "ZZZ")
        self.assertEqual(
            txn.instrument.option,
            Option(call_put="PUT", strike=Decimal("12.50"), expiry=date(2026, 5, 22)),
        )

    def test_money_is_decimal_and_lossless(self):
        txn = self.txns["90000000000004"]
        self.assertEqual(txn.action, "SELL")
        self.assertEqual(txn.instrument.type, "STOCK")
        self.assertIsNone(txn.instrument.option)
        self.assertEqual(txn.qty, Decimal("-100"))
        self.assertEqual(txn.price, Decimal("19"))
        self.assertEqual(txn.amount, Decimal("1899.94"))
        self.assertIsInstance(txn.amount, Decimal)

    def test_cash_instrument_has_no_symbol_or_option(self):
        txn = self.txns["90000000000007"]  # ACH withdrawal, seconds epoch
        self.assertEqual(txn.action, "TRANSFER")
        self.assertEqual(txn.date, date(2026, 4, 15))
        self.assertEqual(txn.instrument, Instrument(type="CASH", symbol=None))


class RoundTripTests(unittest.TestCase):
    """The unify guarantee: from_etrade -> to_record -> from_record is stable,
    and to_record reproduces the exact on-disk schema the journal already uses.
    """

    def test_to_record_matches_legacy_schema(self):
        rec = Transaction.from_etrade(by_id_raw("90000000000001")).to_record()
        self.assertEqual(
            rec,
            {
                "transaction_id": "90000000000001",
                "date": "2026-05-18",
                "action": "SELL_TO_OPEN",
                "instrument": {
                    "type": "OPTION",
                    "symbol": "ZZZ",
                    "option": {
                        "callPut": "PUT",
                        "strike": "12.50",
                        "expiry": "2026-05-22",
                    },
                },
                "qty": "1",
                "price": "0.49",
                "fee": "0.66",
                "amount": "48.34",
                "transaction_type": "Sold Short",
                "description": "PUT ZZZ 05/22/26 12.500",
                "raw": rec["raw"],
            },
        )

    def test_record_round_trip_is_identity(self):
        for txn in by_id().values():
            again = Transaction.from_record(txn.to_record())
            self.assertEqual(again, txn)

    def test_journal_line_round_trips(self):
        # Exactly how journal.ingest writes a line. The parsed top-level fields
        # are authoritative and must survive verbatim; the raw blob is provenance
        # only (json default=str renders its Decimals as strings), so it is not
        # part of this identity check.
        for txn in by_id().values():
            record = txn.to_record()
            line = json.dumps(record, default=str)
            reloaded = Transaction.from_record(json.loads(line))
            self.assertEqual(reloaded.to_record()["instrument"], record["instrument"])
            self.assertEqual(
                (
                    reloaded.transaction_id,
                    reloaded.date,
                    reloaded.action,
                    reloaded.qty,
                    reloaded.price,
                    reloaded.fee,
                    reloaded.amount,
                ),
                (
                    txn.transaction_id,
                    txn.date,
                    txn.action,
                    txn.qty,
                    txn.price,
                    txn.fee,
                    txn.amount,
                ),
            )


def by_id_raw(transaction_id):
    for t in load_txns():
        if t["transactionId"] == transaction_id:
            return t
    raise KeyError(transaction_id)


if __name__ == "__main__":
    unittest.main()
