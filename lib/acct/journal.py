#!/usr/bin/env python3
"""Parse and persist E*TRADE account transactions into a local journal.

This is the analytics core of the `acct` command. The bash side owns the
network and credentials; it fetches the raw transactions response and pipes it
to `journal.py ingest`, which parses each record and appends it to an
append-only JSONL journal under the account's data directory.

Design notes:
- Money is parsed with Decimal (json parse_float=Decimal) and stored as strings
  so exact values survive round-trips -- never as binary floats.
- Each record keeps the full original E*TRADE transaction under "raw" so no
  information is ever lost, even for fields this parser does not yet interpret.
- Ingest is idempotent: records already present (by transaction_id) are skipped,
  so overlapping/repeated syncs never create duplicates.
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from decimal import Decimal

from model import Transaction


def parse_transaction(txn):
    """Parse one E*TRADE transaction into a journal record (raw kept intact).

    The schema lives in `model.Transaction`; this is just the persistence-side
    convenience that parses and immediately serializes to the on-disk record.
    """
    return Transaction.from_etrade(txn).to_record()


def _transactions(response):
    return (response.get("TransactionListResponse") or {}).get("Transaction") or []


def _read_existing_ids(jsonl_path):
    ids = set()
    if not os.path.exists(jsonl_path):
        return ids
    with open(jsonl_path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                ids.add(json.loads(line)["transaction_id"])
    return ids


def ingest(account_id_key, data_dir, response, fetched_at):
    """Append new transactions to the account journal; return (added, total)."""
    transactions_dir = os.path.join(data_dir, "transactions")
    os.makedirs(transactions_dir, exist_ok=True)
    jsonl_path = os.path.join(transactions_dir, f"{account_id_key}.jsonl")
    meta_path = os.path.join(transactions_dir, f"{account_id_key}.meta.json")

    seen_ids = _read_existing_ids(jsonl_path)
    added = 0
    with open(jsonl_path, "a", encoding="utf-8") as handle:
        for txn in _transactions(response):
            record = parse_transaction(txn)
            if record["transaction_id"] in seen_ids:
                continue
            handle.write(json.dumps(record, default=str) + "\n")
            seen_ids.add(record["transaction_id"])
            added += 1

    dates = []
    with open(jsonl_path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                date = json.loads(line).get("date")
                if date:
                    dates.append(date)

    meta = {
        "account_id_key": account_id_key,
        "last_fetched_at": fetched_at,
        "record_count": len(seen_ids),
        "oldest_seen_date": min(dates) if dates else None,
        "newest_seen_date": max(dates) if dates else None,
    }
    with open(meta_path, "w", encoding="utf-8") as handle:
        json.dump(meta, handle, indent=2)

    return added, len(seen_ids)


def _cmd_ingest(args):
    raw = sys.stdin.read()
    if not raw.strip():
        print("error: no input on stdin", file=sys.stderr)
        return 1
    response = json.loads(raw, parse_float=Decimal)
    fetched_at = args.fetched_at or datetime.now(timezone.utc).isoformat(
        timespec="seconds"
    )
    added, total = ingest(args.account, args.data_dir, response, fetched_at)
    print(f"Ingested {added} new transaction(s); {total} stored for {args.account}.")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(prog="journal.py", description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    ingest_parser = sub.add_parser(
        "ingest", help="parse a transactions response (stdin) into the journal"
    )
    ingest_parser.add_argument("--account", required=True, help="accountIdKey")
    ingest_parser.add_argument("--data-dir", required=True, help="data directory root")
    ingest_parser.add_argument(
        "--fetched-at", help="ISO timestamp to record (defaults to now, UTC)"
    )
    ingest_parser.set_defaults(func=_cmd_ingest)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
