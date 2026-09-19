"""Rule implementations, one small module per rule (VA-001). Importing this package registers
every ``@rule``; a new rule is a module here + ``rules/<id>.yaml`` + its two fixtures."""

from farmerapp.rules.checks import (
    va_e01,
    va_e02,
    va_e03,
    va_e04,
    va_e05,
    va_e08,
    va_f01,
    va_f02,
    va_f03,
    va_f06,
    va_f08,
)

__all__ = [
    "va_e01",
    "va_e02",
    "va_e03",
    "va_e04",
    "va_e05",
    "va_e08",
    "va_f01",
    "va_f02",
    "va_f03",
    "va_f06",
    "va_f08",
]
