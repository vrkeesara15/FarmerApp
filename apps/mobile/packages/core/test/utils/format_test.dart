import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatInr', () {
    test('groups lakhs and crores the Indian way', () {
      expect(formatInr(12500050), '₹1,25,000.50');
      expect(formatInr(100000), '₹1,000.00');
      expect(formatInr(10000000), '₹1,00,000.00');
      expect(formatInr(1234567890), '₹1,23,45,678.90');
    });

    test('handles small and zero amounts', () {
      expect(formatInr(0), '₹0.00');
      expect(formatInr(5), '₹0.05');
      expect(formatInr(99900), '₹999.00');
    });

    test('handles negative amounts', () {
      expect(formatInr(-12500050), '-₹1,25,000.50');
    });

    test('can hide zero paise', () {
      expect(formatInr(12500000, showPaise: false), '₹1,25,000');
      expect(formatInr(12500050, showPaise: false), '₹1,25,000.50');
    });
  });

  group('formatIndianDigits', () {
    test('groups 3 then 2', () {
      expect(formatIndianDigits(0), '0');
      expect(formatIndianDigits(999), '999');
      expect(formatIndianDigits(1000), '1,000');
      expect(formatIndianDigits(100000), '1,00,000');
      expect(formatIndianDigits(1234567), '12,34,567');
      expect(formatIndianDigits(20000000), '2,00,00,000');
    });
  });

  group('formatDateIst', () {
    test('renders DD-MM-YYYY in IST', () {
      expect(formatDateIst(DateTime.utc(2026, 9, 17, 10, 30)), '17-09-2026');
    });

    test('rolls the day over at IST midnight', () {
      // 18:30 UTC is 00:00 IST next day.
      expect(formatDateIst(DateTime.utc(2026, 1, 31, 18, 30)), '01-02-2026');
      expect(formatDateIst(DateTime.utc(2026, 1, 31, 18, 29)), '31-01-2026');
    });

    test('zero-pads day and month', () {
      expect(formatDateIst(DateTime.utc(2026, 3, 5)), '05-03-2026');
    });
  });

  group('formatDateTimeIst', () {
    test('renders date and 24h time', () {
      expect(
        formatDateTimeIst(DateTime.utc(2026, 9, 17, 10, 5)),
        '17-09-2026 15:35',
      );
    });
  });

  group('durations', () {
    test('formatElapsed is H:MM', () {
      expect(formatElapsed(const Duration(hours: 3, minutes: 7)), '3:07');
      expect(formatElapsed(Duration.zero), '0:00');
    });

    test('formatCountdown is M:SS', () {
      expect(formatCountdown(const Duration(minutes: 4, seconds: 9)), '4:09');
    });
  });
}
