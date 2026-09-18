import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// FA-025: schema v1 (kv only, M0) upgrades in place, keeping the settings
/// rows and adding the sync tables and indexes; FA-012: v2 upgrades to v3
/// adding the typed `villages` table without touching queued outbox rows.
void main() {
  const currentVersion = 3;
  const v2Tables = <String>{
    'kv',
    'farmers',
    'farms',
    'crop_plots',
    'consent_records',
    'outbox',
    'uploads',
    'sync_states',
    'synced_refs',
  };

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('farmerapp_migration');
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  Future<Set<String>> tables(AppDatabase db) async {
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }

  Future<int> userVersion(AppDatabase db) async {
    final row = await db.customSelect('PRAGMA user_version').getSingle();
    return row.read<int>('user_version');
  }

  test(
    'a v1 database migrates to the current version and keeps its settings',
    () async {
      final file = File('${dir.path}/v1.db');
      final raw = sqlite.sqlite3.open(file.path);
      raw
        ..execute(
          'CREATE TABLE IF NOT EXISTS "kv" ("key" TEXT NOT NULL, '
          '"value" TEXT NOT NULL, "updated_at" INTEGER NOT NULL, '
          'PRIMARY KEY ("key"))',
        )
        ..execute(
          "INSERT INTO kv VALUES ('settings.locale', 'te', 1758100000), "
          "('settings.theme_mode', 'sunlight', 1758100000)",
        )
        ..execute('PRAGMA user_version = 1')
        ..close();

      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);

      expect(await db.getValue('settings.locale'), 'te');
      expect(await db.getValue('settings.theme_mode'), 'sunlight');
      expect(await userVersion(db), currentVersion);
      expect(await tables(db), containsAll(v2Tables));
      expect(await tables(db), contains('villages'));

      final indexes = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
          .get();
      expect(
        indexes.map((r) => r.read<String>('name')),
        containsAll(<String>['outbox_state_seq', 'outbox_entity']),
      );

      // The new tables are usable right away.
      await db
          .into(db.outboxTable)
          .insert(
            OutboxTableCompanion.insert(
              opId: 'op-1',
              seq: 1,
              entity: 'farmer',
              action: 'create',
              entityId: 'f-1',
              payload: '{}',
              clientTs: '2026-09-20T00:30:00.000Z',
            ),
          );
      expect(await db.select(db.outboxTable).get(), hasLength(1));
      await db
          .into(db.syncStates)
          .insert(
            const SyncStatesCompanion(
              id: Value<int>(1),
              cursor: Value<String?>('42'),
            ),
          );
      expect((await db.select(db.syncStates).getSingle()).cursor, '42');
    },
  );

  test(
    'a v2 database migrates to v3: villages added, outbox rows kept',
    () async {
      final file = File('${dir.path}/v2.db');
      // Build a genuine v2 file: open at the current schema, then rewrite it
      // down to v2 (drop the v3 table, reset user_version).
      final seed = AppDatabase(NativeDatabase(file));
      await seed.setValue('settings.locale', 'kn');
      await seed
          .into(seed.outboxTable)
          .insert(
            OutboxTableCompanion.insert(
              opId: 'op-1',
              seq: 1,
              entity: 'farmer',
              action: 'create',
              entityId: 'f-1',
              payload: '{"name":"Ramesh"}',
              clientTs: '2026-09-20T00:30:00.000Z',
            ),
          );
      await seed.close();
      final raw = sqlite.sqlite3.open(file.path);
      raw
        ..execute('DROP TABLE villages')
        ..execute('PRAGMA user_version = 2')
        ..close();

      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      expect(await userVersion(db), currentVersion);
      expect(await tables(db), contains('villages'));
      expect(await db.getValue('settings.locale'), 'kn');
      final op = await db.select(db.outboxTable).getSingle();
      expect(op.opId, 'op-1');
      expect(op.state, 'queued');

      await db
          .into(db.villages)
          .insert(
            VillagesCompanion.insert(
              id: 'v-1',
              name: 'Kondapur',
              updatedAt: DateTime.utc(2026, 9, 20),
            ),
          );
      expect((await db.select(db.villages).getSingle()).name, 'Kondapur');
    },
  );

  test(
    'a fresh database is created at the current version with every table',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      expect(await userVersion(db), currentVersion);
      expect(await tables(db), containsAll(<String>{...v2Tables, 'villages'}));
    },
  );

  test(
    're-opening a current database does not run the upgrade again',
    () async {
      final file = File('${dir.path}/v3.db');
      final first = AppDatabase(NativeDatabase(file));
      await first.setValue('k', 'v');
      await first.close();

      final second = AppDatabase(NativeDatabase(file));
      addTearDown(second.close);
      expect(await second.getValue('k'), 'v');
      expect(await userVersion(second), currentVersion);
    },
  );
}
