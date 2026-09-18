/// Indian number and date formatting helpers (NF-008).
///
/// Money is always integer paise (CLAUDE.md); timestamps are UTC in the DB
/// and rendered in IST here.
library;

/// Rupee sign used in all money output.
const String rupeeSign = '₹';

/// IST offset from UTC.
const Duration istOffset = Duration(hours: 5, minutes: 30);

/// Formats [paise] as Indian rupees with lakh/crore grouping.
///
/// `formatInr(12500050)` returns `₹1,25,000.50`. Negative amounts render as
/// `-₹1,25,000.50`. Set [showPaise] to `false` to drop the decimal part when
/// it is zero.
String formatInr(int paise, {bool showPaise = true}) {
  final negative = paise < 0;
  final abs = paise.abs();
  final rupees = abs ~/ 100;
  final fraction = abs % 100;
  final grouped = formatIndianDigits(rupees);
  final buffer = StringBuffer();
  if (negative) buffer.write('-');
  buffer.write(rupeeSign);
  buffer.write(grouped);
  if (showPaise || fraction != 0) {
    buffer.write('.');
    buffer.write(fraction.toString().padLeft(2, '0'));
  }
  return buffer.toString();
}

/// Groups a non-negative integer the Indian way: `1234567` -> `12,34,567`.
String formatIndianDigits(int value) {
  assert(value >= 0, 'formatIndianDigits expects a non-negative value');
  final digits = value.toString();
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var head = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (head.length > 2) {
    parts.insert(0, head.substring(head.length - 2));
    head = head.substring(0, head.length - 2);
  }
  if (head.isNotEmpty) parts.insert(0, head);
  return '${parts.join(',')},$last3';
}

/// Formats [utc] in IST as `DD-MM-YYYY`.
///
/// The input is converted to UTC first, then shifted by +05:30, so both UTC
/// and local [DateTime]s give the correct calendar day in India.
String formatDateIst(DateTime utc) {
  final ist = utc.toUtc().add(istOffset);
  final d = ist.day.toString().padLeft(2, '0');
  final m = ist.month.toString().padLeft(2, '0');
  return '$d-$m-${ist.year}';
}

/// Formats [utc] in IST as `DD-MM-YYYY HH:mm` (24-hour clock).
String formatDateTimeIst(DateTime utc) {
  final ist = utc.toUtc().add(istOffset);
  final h = ist.hour.toString().padLeft(2, '0');
  final min = ist.minute.toString().padLeft(2, '0');
  return '${formatDateIst(utc)} $h:$min';
}

/// Formats [utc] in IST as `HH:mm` (24-hour clock).
String formatTimeIst(DateTime utc) {
  final ist = utc.toUtc().add(istOffset);
  final hh = ist.hour.toString().padLeft(2, '0');
  final mm = ist.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// Formats a [Duration] as `H:MM` for elapsed-time displays (DutyToggle).
String formatElapsed(Duration d) {
  final h = d.inHours;
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// Formats a [Duration] as `M:SS` for countdowns (OTP resend, UPI expiry).
String formatCountdown(Duration d) {
  final m = d.inMinutes;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
