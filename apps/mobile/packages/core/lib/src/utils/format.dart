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

/// Formats a calendar month as `MM-YYYY` (harvest month on the khata).
String formatMonthYear(DateTime date) =>
    '${date.month.toString().padLeft(2, '0')}-${date.year}';

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

/// Formats a decimal the Indian way: `125000.5` -> `1,25,000.5`.
///
/// Trailing zeros are dropped ( `2.00` -> `2` ) because a farmer reads "2
/// acres", not "2.00 acres"; [maxDecimals] caps the fraction. This is the
/// helper every non-money number goes through, so grouping never depends on
/// the platform's ICU build (NF-008: numbers in Indian format).
String formatIndianDecimal(double value, {int maxDecimals = 2}) {
  assert(maxDecimals >= 0 && maxDecimals <= 6, 'maxDecimals out of range');
  if (value.isNaN || value.isInfinite) return '-';
  final negative = value < 0;
  final abs = value.abs();
  final fixed = abs.toStringAsFixed(maxDecimals);
  final dot = fixed.indexOf('.');
  final whole = dot == -1 ? fixed : fixed.substring(0, dot);
  var fraction = dot == -1 ? '' : fixed.substring(dot + 1);
  while (fraction.isNotEmpty && fraction.endsWith('0')) {
    fraction = fraction.substring(0, fraction.length - 1);
  }
  final grouped = formatIndianDigits(int.parse(whole));
  final body = fraction.isEmpty ? grouped : '$grouped.$fraction';
  // "-0" is never what anyone means.
  return negative && body != '0' ? '-$body' : body;
}

/// Formats an area in acres for an ARB placeholder (NF-008: unit acre).
///
/// Land is measured in acres across the app (`farm.area_acres`,
/// `crop_plot.area_acres`); the *word* "acre" comes from the ARB string in
/// the farmer's language, so this formats only the number.
String formatAcres(double acres) => formatIndianDecimal(acres);

/// Formats a volume held in millilitres (NF-008: unit litre).
///
/// Under a litre it reads in ml (`250 ml`), from a litre up it reads in
/// litres (`1.5 L`, `15 L`) -- the way a dose on a pesticide label and a
/// spray tank are actually written. The unit is part of the output here
/// because `ml` and `L` are the same glyphs in every launch language;
/// anything a farmer reads as a sentence uses an ARB string instead.
String formatVolume(int millilitres) {
  final negative = millilitres < 0;
  final abs = millilitres.abs();
  final body = abs < 1000
      ? '$abs $millilitreUnit'
      : '${formatIndianDecimal(abs / 1000)} $litreUnit';
  return negative ? '-$body' : body;
}

/// Symbol for millilitres.
const String millilitreUnit = 'ml';

/// Symbol for litres.
const String litreUnit = 'L';

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
