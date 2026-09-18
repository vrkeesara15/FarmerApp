"""Amounts in words, Indian numbering (ST-001: GST invoices print the total in words).

``amount_in_words(12345678)`` -> ``"Rupees One Lakh Twenty-Three Thousand Four Hundred
Fifty-Six and Seventy-Eight Paise Only"``. Groups: crore (10^7), lakh (10^5), thousand,
hundred; crores above 99 are themselves spelt in the Indian system ("One Hundred Crore").
"""

from __future__ import annotations

ONES = (
    "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten",
    "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen",
    "Eighteen", "Nineteen",
)  # fmt: skip
TENS = ("", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety")


def _below_hundred(n: int) -> str:
    if n < 20:
        return ONES[n]
    tens, ones = divmod(n, 10)
    return TENS[tens] + (f"-{ONES[ones]}" if ones else "")


def _below_thousand(n: int) -> str:
    hundreds, rest = divmod(n, 100)
    parts: list[str] = []
    if hundreds:
        parts.append(f"{ONES[hundreds]} Hundred")
    if rest:
        parts.append(_below_hundred(rest))
    return " ".join(parts)


def number_in_words(n: int) -> str:
    """A non-negative integer in words, Indian system."""
    if n < 0:
        raise ValueError("negative amounts have no words")
    if n == 0:
        return ONES[0]
    crore, rest = divmod(n, 10**7)
    lakh, rest = divmod(rest, 10**5)
    thousand, rest = divmod(rest, 1000)
    parts: list[str] = []
    if crore:
        parts.append(f"{number_in_words(crore)} Crore")
    if lakh:
        parts.append(f"{_below_hundred(lakh)} Lakh")
    if thousand:
        parts.append(f"{_below_hundred(thousand)} Thousand")
    if rest:
        parts.append(_below_thousand(rest))
    return " ".join(parts)


def amount_in_words(paise: int) -> str:
    rupees, remainder = divmod(abs(paise), 100)
    words = f"Rupees {number_in_words(rupees)}"
    if remainder:
        words += f" and {number_in_words(remainder)} Paise"
    prefix = "Minus " if paise < 0 else ""
    return f"{prefix}{words} Only"


__all__ = ["amount_in_words", "number_in_words"]
