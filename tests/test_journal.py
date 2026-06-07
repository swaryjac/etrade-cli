"""Tests for lib/acct/journal.py (transaction parsing + journal persistence).

Stdlib unittest only, to match the project's no-extra-dependencies ethos.
Run with:  python3 -m unittest tests.test_journal
"""

import json
import sys
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "lib" / "acct"))

import journal  # noqa: E402

FIXTURE = REPO_ROOT / "tests" / "fixtures" / "acct" / "transactions_response.json"


def load_fixture():
    with open(FIXTURE, encoding="utf-8") as handle:
        return json.load(handle, parse_float=Decimal)


def records_by_id():
    txns = load_fixture()["TransactionListResponse"]["Transaction"]
    return {t["transactionId"]: journal.parse_transaction(t) for t in txns}


class ParseTransactionTests(unittest.TestCase):
    def setUp(self):
        self.recs = records_by_id()

    def test_sell_to_open_option_record(self):
        rec = self.recs["90000000000001"]
        self.assertEqual(rec["action"], "SELL_TO_OPEN")
        self.assertEqual(rec["date"], "2026-05-18")
        self.assertEqual(rec["instrument"]["type"], "OPTION")
        self.assertEqual(rec["instrument"]["symbol"], "ZZZ")
        self.assertEqual(
            rec["instrument"]["option"],
            {"callPut": "PUT", "strike": "12.50", "expiry": "2026-05-22"},
        )

    def test_money_values_are_lossless_strings(self):
        rec = self.recs["90000000000004"]
        self.assertEqual(rec["action"], "SELL")
        self.assertEqual(rec["instrument"]["type"], "STOCK")
        self.assertEqual(rec["qty"], "-100")  # API sign convention preserved
        self.assertEqual(rec["price"], "19")
        # API amount trusted verbatim, not recomputed as 100 * 19 = 1900
        self.assertEqual(rec["amount"], "1899.94")

    def test_seconds_epoch_normalizes_like_milliseconds(self):
        rec = self.recs["90000000000007"]
        self.assertEqual(rec["date"], "2026-04-15")
        self.assertEqual(rec["action"], "TRANSFER")
        self.assertEqual(rec["instrument"]["type"], "CASH")
        self.assertIsNone(rec["instrument"]["symbol"])

    def test_action_classification_table(self):
        self.assertEqual(self.recs["90000000000002"]["action"], "EXPIRE")
        self.assertEqual(self.recs["90000000000003"]["action"], "ASSIGN")
        self.assertEqual(self.recs["90000000000005"]["action"], "INTEREST")
        self.assertEqual(self.recs["90000000000006"]["action"], "DIVIDEND")

    def test_raw_blob_is_preserved(self):
        rec = self.recs["90000000000001"]
        self.assertEqual(rec["raw"]["transactionType"], "Sold Short")
        self.assertEqual(rec["raw"]["brokerage"]["product"]["symbol"], "ZZZ")


class IngestTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.data_dir = self._tmp.name
        self.addCleanup(self._tmp.cleanup)

    def _jsonl_lines(self, account="ACCT"):
        path = Path(self.data_dir) / "transactions" / f"{account}.jsonl"
        return [l for l in path.read_text().splitlines() if l.strip()]

    def _meta(self, account="ACCT"):
        path = Path(self.data_dir) / "transactions" / f"{account}.meta.json"
        return json.loads(path.read_text())

    def test_ingest_writes_journal_and_meta(self):
        added, total = journal.ingest(
            "ACCT", self.data_dir, load_fixture(), "2026-05-31T00:00:00+00:00"
        )
        self.assertEqual((added, total), (7, 7))
        self.assertEqual(len(self._jsonl_lines()), 7)

        meta = self._meta()
        self.assertEqual(meta["record_count"], 7)
        self.assertEqual(meta["oldest_seen_date"], "2026-04-15")
        self.assertEqual(meta["newest_seen_date"], "2026-05-22")
        self.assertEqual(meta["last_fetched_at"], "2026-05-31T00:00:00+00:00")

    def test_ingest_is_idempotent(self):
        journal.ingest("ACCT", self.data_dir, load_fixture(), "t1")
        added, total = journal.ingest("ACCT", self.data_dir, load_fixture(), "t2")
        self.assertEqual((added, total), (0, 7))
        self.assertEqual(len(self._jsonl_lines()), 7)  # no duplicates appended

    def test_ingest_appends_only_new_records(self):
        response = load_fixture()
        partial = {"TransactionListResponse": {
            "Transaction": response["TransactionListResponse"]["Transaction"][:3]}}
        journal.ingest("ACCT", self.data_dir, partial, "t1")

        added, total = journal.ingest("ACCT", self.data_dir, response, "t2")
        self.assertEqual((added, total), (4, 7))


if __name__ == "__main__":
    unittest.main()
