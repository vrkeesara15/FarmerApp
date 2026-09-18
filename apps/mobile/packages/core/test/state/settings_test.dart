import 'package:drift/native.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late KvSettingsStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = KvSettingsStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('KvSettingsStore defaults to no locale and Light', () async {
    final s = await store.load();
    expect(s.locale, isNull);
    expect(s.themeMode, AppThemeMode.light);
  });

  test('KvSettingsStore round-trips locale and theme through kv', () async {
    await store.save(
      const AppSettings(locale: Locale('te'), themeMode: AppThemeMode.sunlight),
    );
    expect(await db.getValue(KvSettingsStore.localeKey), 'te');
    expect(await db.getValue(KvSettingsStore.themeKey), 'sunlight');
    final s = await store.load();
    expect(s.locale, const Locale('te'));
    expect(s.themeMode, AppThemeMode.sunlight);
  });

  test('unsupported or malformed stored locale is ignored', () async {
    await db.setValue(KvSettingsStore.localeKey, 'fr');
    expect((await store.load()).locale, isNull);
    await db.setValue(KvSettingsStore.localeKey, 'hi-IN');
    expect((await store.load()).locale, const Locale('hi'));
    expect(parseSupportedLocale(''), isNull);
    expect(parseSupportedLocale('kn_IN'), const Locale('kn'));
  });

  test(
    'settingsProvider persists every change and restores on restart',
    () async {
      // First app start: nothing stored.
      final first = ProviderContainer(
        overrides: await settingsOverrides(store),
      );
      addTearDown(first.dispose);
      expect(first.read(settingsProvider).locale, isNull);

      first.read(settingsProvider.notifier).setLocale(const Locale('mr'));
      first.read(settingsProvider.notifier).toggleTheme();
      expect(first.read(settingsProvider).locale, const Locale('mr'));
      await pumpEventQueue();
      expect((await store.load()).locale, const Locale('mr'));
      expect((await store.load()).themeMode, AppThemeMode.sunlight);

      // Second app start: a new container over the same database.
      final second = ProviderContainer(
        overrides: await settingsOverrides(store),
      );
      addTearDown(second.dispose);
      expect(second.read(settingsProvider).locale, const Locale('mr'));
      expect(second.read(settingsProvider).themeMode, AppThemeMode.sunlight);
    },
  );

  test('setting the same value again does not write', () async {
    final tracking = _CountingStore();
    final container = ProviderContainer(
      overrides: <Override>[settingsStoreProvider.overrideWithValue(tracking)],
    );
    addTearDown(container.dispose);
    container.read(settingsProvider.notifier).setLocale(const Locale('kn'));
    container.read(settingsProvider.notifier).setLocale(const Locale('kn'));
    await pumpEventQueue();
    expect(tracking.saves, 1);
  });
}

class _CountingStore extends InMemorySettingsStore {
  int saves = 0;

  @override
  Future<void> save(AppSettings settings) {
    saves++;
    return super.save(settings);
  }
}
