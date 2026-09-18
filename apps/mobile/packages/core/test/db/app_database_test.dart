import 'package:drift/native.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('kv table round-trips a value', () async {
    expect(await db.getValue('theme'), isNull);
    await db.setValue('theme', 'sunlight');
    expect(await db.getValue('theme'), 'sunlight');
  });

  test('setValue upserts', () async {
    await db.setValue('locale', 'en');
    await db.setValue('locale', 'te');
    expect(await db.getValue('locale'), 'te');
    expect(await db.select(db.kv).get(), hasLength(1));
  });

  test('removeValue deletes the row', () async {
    await db.setValue('k', 'v');
    expect(await db.removeValue('k'), 1);
    expect(await db.getValue('k'), isNull);
  });
}
