#!/usr/bin/env python3
"""Reporting layer over the transaction journal -- slice 1: put premium income.

The strategy is the "wheel": sell weekly cash-secured puts and collect the
premium. This slice reports that core income leg only.

Scope (deliberately narrow -- see acct_direction memory for the roadmap):
- Income = the premium on each SELL_TO_OPEN *put*, recognized on the SELL date
  (the date the premium is collected, not when the option later resolves). The
  E*TRADE `amount` is already net of fees, so it IS the premium gain.
- A PositionBook matches each put's close (EXPIRE or ASSIGN) back to its open so
  outcomes can be reported. Assignment is merely *recognized* here -- the
  resulting stock leg, covered calls, and realized P&L are later slices.
- Calls and every non-put transaction are ignored (they never enter the book).

This module only reads the journal; it never touches the network.
"""

import argparse
import csv
import json
import os
import sys
from dataclasses import dataclass, field
from datetime import date, timedelta
from decimal import Decimal

from model import Transaction

_CLOSE_ACTIONS = ("EXPIRE", "ASSIGN")


def load_journal(jsonl_path):
    """Read a journal file into a list of Transactions, ordered as stored."""
    transactions = []
    if not os.path.exists(jsonl_path):
        return transactions
    with open(jsonl_path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                transactions.append(Transaction.from_record(json.loads(line)))
    return transactions


def is_put(txn):
    opt = txn.instrument.option
    return opt is not None and opt.call_put == "PUT"


def _contracts(txn):
    """Contract count as a positive magnitude (the qty sign is unreliable)."""
    return abs(txn.qty) if txn.qty is not None else Decimal(0)


def _option_key(txn):
    opt = txn.instrument.option
    return (txn.instrument.symbol, opt.call_put, opt.strike, opt.expiry)


def week_ending(day):
    """The Friday of the trade date's week (the journal/spreadsheet week anchor)."""
    return day + timedelta(days=(4 - day.weekday()))


# --- Put premium income -----------------------------------------------------


@dataclass
class WeekRow:
    week_ending: date
    contracts: Decimal
    premium: Decimal
    cumulative: Decimal


def weekly_put_premium(transactions):
    """Weekly premium collected from sold puts, recognized on the SELL date."""
    by_week = {}
    for txn in transactions:
        if txn.action != "SELL_TO_OPEN" or not is_put(txn) or txn.date is None:
            continue
        bucket = by_week.setdefault(week_ending(txn.date), [Decimal(0), Decimal(0)])
        bucket[0] += _contracts(txn)
        bucket[1] += txn.amount or Decimal(0)

    rows = []
    cumulative = Decimal(0)
    for friday in sorted(by_week):
        contracts, premium = by_week[friday]
        cumulative += premium
        rows.append(WeekRow(friday, contracts, premium, cumulative))
    return rows


# --- Position outcomes (foundation for later slices) ------------------------


@dataclass
class OpenLot:
    open_txn: Transaction
    opened: Decimal
    remaining: Decimal
    closes: list = field(default_factory=list)  # (close_txn, qty_consumed)

    def outcome(self):
        if not self.closes:
            return "OPEN"
        if any(c.action == "ASSIGN" for c, _ in self.closes):
            return "ASSIGNED"
        if self.remaining > 0:
            return "PARTIAL"
        return "EXPIRED"


@dataclass
class OrphanClose:
    close_txn: Transaction
    unmatched: Decimal


class PositionBook:
    """Match put closes (EXPIRE/ASSIGN) to their opens, FIFO within a contract key.

    A close with no surviving open lot is an orphan -- expected near the start of
    any bounded window, where the opening sell predates the journal's history.
    """

    def __init__(self):
        self._lots = {}  # option key -> [OpenLot] (FIFO)
        self.orphans = []

    def apply(self, txn):
        if not is_put(txn):
            return  # slice 1 tracks puts only
        if txn.action == "SELL_TO_OPEN":
            qty = _contracts(txn)
            self._lots.setdefault(_option_key(txn), []).append(
                OpenLot(open_txn=txn, opened=qty, remaining=qty)
            )
        elif txn.action in _CLOSE_ACTIONS:
            self._close(txn)

    def _close(self, txn):
        to_close = _contracts(txn)
        for lot in self._lots.get(_option_key(txn), []):
            if to_close <= 0:
                break
            if lot.remaining <= 0:
                continue
            consumed = min(lot.remaining, to_close)
            lot.remaining -= consumed
            lot.closes.append((txn, consumed))
            to_close -= consumed
        if to_close > 0:
            self.orphans.append(OrphanClose(close_txn=txn, unmatched=to_close))

    def lots(self):
        for lots in self._lots.values():
            yield from lots

    def outcome_counts(self):
        counts = {"OPEN": 0, "EXPIRED": 0, "ASSIGNED": 0, "PARTIAL": 0}
        for lot in self.lots():
            counts[lot.outcome()] += 1
        return counts


def build_positions(transactions):
    # The journal is stored newest-first (sync pages dates descending), but a
    # close can only match an open that already exists, so feed the book in
    # chronological order. On a tie, opens go before closes so a same-day
    # sell-then-resolve still matches.
    book = PositionBook()
    ordered = sorted(
        transactions,
        key=lambda t: (t.date or date.min, t.action in _CLOSE_ACTIONS),
    )
    for txn in ordered:
        book.apply(txn)
    return book


# --- CLI ---------------------------------------------------------------------


def _write_weekly_csv(rows, out):
    writer = csv.writer(out)
    writer.writerow(["week_ending", "contracts", "premium", "cumulative_premium"])
    for row in rows:
        writer.writerow(
            [row.week_ending.isoformat(), row.contracts, row.premium, row.cumulative]
        )


def _print_summary(rows, book, account, err):
    counts = book.outcome_counts()
    total = rows[-1].cumulative if rows else Decimal(0)
    print(f"Put premium income for {account}:", file=err)
    print(f"  weeks with sales : {len(rows)}", file=err)
    print(f"  total premium    : {total}", file=err)
    print("  put positions    : "
          f"{sum(counts.values())} "
          f"(expired {counts['EXPIRED']}, assigned {counts['ASSIGNED']}, "
          f"open {counts['OPEN']}, partial {counts['PARTIAL']})", file=err)
    if book.orphans:
        print(f"  orphan closes    : {len(book.orphans)} "
              "(opening sale predates this journal window)", file=err)


def _cmd_weekly(args):
    jsonl_path = os.path.join(
        args.data_dir, "transactions", f"{args.account}.jsonl"
    )
    transactions = load_journal(jsonl_path)
    if not transactions:
        print(f"error: no journal at {jsonl_path}", file=sys.stderr)
        return 1
    rows = weekly_put_premium(transactions)
    book = build_positions(transactions)
    _write_weekly_csv(rows, sys.stdout)
    _print_summary(rows, book, args.account, sys.stderr)
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(prog="report.py", description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    weekly = sub.add_parser(
        "weekly", help="weekly put premium income (CSV on stdout)"
    )
    weekly.add_argument("--account", required=True, help="accountIdKey")
    weekly.add_argument("--data-dir", required=True, help="data directory root")
    weekly.set_defaults(func=_cmd_weekly)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
