#!/usr/bin/env python3
"""Typed domain model for account transactions.

The persistence layer (journal.py) stores transactions as schema-light JSONL
dicts -- money as strings, dates as ISO strings, the full raw E*TRADE record
kept under "raw" -- so no information is ever lost. This module is the in-memory
view the analytics layer works with: a `Transaction` (with `Instrument` and
`Option`) whose money is `Decimal` and whose dates are `datetime.date`.

One schema, both directions:
- `Transaction.from_etrade(txn)` parses a raw E*TRADE transaction (used by ingest).
- `Transaction.to_record()` serializes to the JSONL dict (the on-disk format).
- `Transaction.from_record(d)` reads a JSONL dict back into a typed object.

`from_etrade(...).to_record()` IS the journal record, so the stored format is
defined here once and read back here once -- the two can never drift apart.
"""

from dataclasses import dataclass
from datetime import date, datetime
from decimal import Decimal
from zoneinfo import ZoneInfo

# E*TRADE transaction timestamps are in US Eastern; the date portion is what the
# journal keys on, so resolve epochs in that zone to match brokerage trade dates.
_MARKET_TZ = ZoneInfo("America/New_York")

# securityType -> instrument type
_INSTRUMENT_TYPE = {"OPTN": "OPTION", "EQ": "STOCK"}

# (transactionType) -> action, with Bought/Sold disambiguated by security type.
_ACTION_BY_TYPE = {
    "Option Assigned": "ASSIGN",
    "Option Expired": "EXPIRE",
    "Interest Income": "INTEREST",
    "Qualified Dividend": "DIVIDEND",
    "Dividend": "DIVIDEND",
    "Transfer": "TRANSFER",
    "Fee": "FEE",
}


def _dec(value):
    """Coerce a numeric/string value to Decimal losslessly, or pass None through.

    Inputs reach us either as Decimal/int (raw responses are parsed with
    json parse_float=Decimal) or as strings (when read back from the journal).
    Routing everything through str() avoids ever building a Decimal from a binary
    float, and preserves the exact text (e.g. "12.50", "-25.0", "1899.94").
    """
    return None if value is None else Decimal(str(value))


def _str(value):
    """Stringify a value losslessly for the journal, or pass None through."""
    return None if value is None else str(value)


def _to_date(epoch):
    """Normalize an E*TRADE epoch timestamp to a market-date `date`.

    Production uses milliseconds (13 digits); the sandbox uses seconds.
    """
    if not epoch:
        return None
    epoch = int(epoch)
    seconds = epoch / 1000 if epoch > 1_000_000_000_000 else epoch
    return datetime.fromtimestamp(seconds, _MARKET_TZ).date()


def _expiry(product):
    """Assemble a full expiry `date` from the two-digit year + month + day."""
    year, month, day = (
        product.get("expiryYear"),
        product.get("expiryMonth"),
        product.get("expiryDay"),
    )
    if not (year and month and day):
        return None
    if year < 100:
        year += 2000
    return date(int(year), int(month), int(day))


def _classify_action(transaction_type, security_type):
    if transaction_type in _ACTION_BY_TYPE:
        return _ACTION_BY_TYPE[transaction_type]
    if transaction_type == "Sold Short":
        return "SELL_TO_OPEN"
    if transaction_type == "Bought To Cover":
        return "BUY_TO_CLOSE"
    if transaction_type in ("Bought", "Sold"):
        opening = transaction_type == "Bought"
        if security_type == "OPTN":
            return "BUY_TO_OPEN" if opening else "SELL_TO_CLOSE"
        return "BUY" if opening else "SELL"
    # Preserve unknown types verbatim (uppercased) rather than dropping them;
    # the original is always available under "raw".
    return (transaction_type or "UNKNOWN").upper().replace(" ", "_")


@dataclass(frozen=True)
class Option:
    """The contract details of an option instrument."""

    call_put: str | None  # "CALL" | "PUT"
    strike: Decimal | None
    expiry: date | None


@dataclass(frozen=True)
class Instrument:
    """What a transaction is against: an option, a stock, or plain cash."""

    type: str  # "OPTION" | "STOCK" | "CASH"
    symbol: str | None
    option: Option | None = None


@dataclass
class Transaction:
    """One account transaction in typed form (money Decimal, dates date).

    `raw` keeps the full original E*TRADE record so no field is ever lost,
    even ones this model does not yet interpret.
    """

    transaction_id: str
    date: date | None
    action: str
    instrument: Instrument
    qty: Decimal | None
    price: Decimal | None
    fee: Decimal | None
    amount: Decimal | None
    transaction_type: str | None
    description: str | None
    raw: dict

    @classmethod
    def from_etrade(cls, txn):
        """Parse a raw E*TRADE transaction into a typed Transaction."""
        brokerage = txn.get("brokerage") or {}
        product = brokerage.get("product") or {}
        security_type = product.get("securityType")
        instrument_type = _INSTRUMENT_TYPE.get(security_type, "CASH")

        option = None
        if instrument_type == "OPTION":
            option = Option(
                call_put=product.get("callPut"),
                strike=_dec(product.get("strikePrice")),
                expiry=_expiry(product),
            )
        instrument = Instrument(
            type=instrument_type,
            symbol=product.get("symbol") or None,
            option=option,
        )

        description = (txn.get("description") or "").strip() or None

        return cls(
            transaction_id=str(txn.get("transactionId")),
            date=_to_date(txn.get("transactionDate")),
            action=_classify_action(txn.get("transactionType"), security_type),
            instrument=instrument,
            qty=_dec(brokerage.get("quantity")),
            price=_dec(brokerage.get("price")),
            fee=_dec(brokerage.get("fee")),
            amount=_dec(txn.get("amount")),
            transaction_type=txn.get("transactionType"),
            description=description,
            raw=txn,
        )

    @classmethod
    def from_record(cls, record):
        """Read a journal record dict (as written by `to_record`) into a Transaction."""
        instrument = record["instrument"]
        option = None
        opt = instrument.get("option")
        if opt is not None:
            option = Option(
                call_put=opt.get("callPut"),
                strike=_dec(opt.get("strike")),
                expiry=date.fromisoformat(opt["expiry"]) if opt.get("expiry") else None,
            )
        return cls(
            transaction_id=record["transaction_id"],
            date=date.fromisoformat(record["date"]) if record.get("date") else None,
            action=record["action"],
            instrument=Instrument(
                type=instrument["type"],
                symbol=instrument.get("symbol"),
                option=option,
            ),
            qty=_dec(record.get("qty")),
            price=_dec(record.get("price")),
            fee=_dec(record.get("fee")),
            amount=_dec(record.get("amount")),
            transaction_type=record.get("transaction_type"),
            description=record.get("description"),
            raw=record.get("raw") or {},
        )

    def to_record(self):
        """Serialize to the journal record dict (string money, ISO dates)."""
        instrument = {"type": self.instrument.type, "symbol": self.instrument.symbol}
        option = self.instrument.option
        if option is not None:
            instrument["option"] = {
                "callPut": option.call_put,
                "strike": _str(option.strike),
                "expiry": option.expiry.isoformat() if option.expiry else None,
            }
        return {
            "transaction_id": self.transaction_id,
            "date": self.date.isoformat() if self.date else None,
            "action": self.action,
            "instrument": instrument,
            "qty": _str(self.qty),
            "price": _str(self.price),
            "fee": _str(self.fee),
            "amount": _str(self.amount),
            "transaction_type": self.transaction_type,
            "description": self.description,
            "raw": self.raw,
        }
