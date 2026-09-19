"""Rule implementations, one small module per rule (VA-001). Importing this package registers
every ``@rule``; a new rule is a module here + ``rules/<id>.yaml`` + its two fixtures."""

from farmerapp.rules.checks import va_f01, va_f02, va_f03, va_f06

__all__ = ["va_f01", "va_f02", "va_f03", "va_f06"]
