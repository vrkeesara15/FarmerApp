import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// FA-025: schema v1 (kv only, M0) upgrades in place, keeping the settings
/// rows and adding the sync tables and indexes; FA-012: v2 upgrades to v3
/// adding the typed `villages` table without touching queued outbox rows;
/// FA-010 / VV-001: v3 upgrades to v4 adding `duty_sessions`,
/// `location_buffer` and `sync_docs`; FA-014 .. FA-017: v4 upgrades to v5
/// adding `visits`, `visit_photos`, `visit_confirmations` and the village
/// meeting point columns.
void main() {
  const currentVersion = 5;
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

  const v4Tables = <String>{'duty_sessions', 'location_buffer', 'sync_docs'};

  const v5Tables = <String>{'visits', 'visit_photos', 'visit_confirmations'};

  Future<Set<String>> columns(AppDatabase db, String table) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }

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
      expect(await tables(db), containsAll(v4Tables));
      expect(await tables(db), containsAll(v5Tables));

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
        ..execute('DROP TABLE duty_sessions')
        ..execute('DROP TABLE location_buffer')
        ..execute('DROP TABLE sync_docs')
        ..execute('DROP TABLE visits')
        ..execute('DROP TABLE visit_photos')
        ..execute('DROP TABLE visit_confirmations')
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

  test('a v3 database migrates to v4: duty tables added, villages and outbox '
      'rows kept, no point buffered by the migration', () async {
    final file = File('${dir.path}/v3.db');
    final seed = AppDatabase(NativeDatabase(file));
    await seed.setValue('settings.locale', 'mr');
    await seed
        .into(seed.villages)
        .insert(
          VillagesCompanion.insert(
            id: 'v-1',
            name: 'Kondapur',
            updatedAt: DateTime.utc(2026, 9, 20),
          ),
        );
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
      ..execute('DROP TABLE duty_sessions')
      ..execute('DROP TABLE location_buffer')
      ..execute('DROP TABLE sync_docs')
      ..execute('DROP TABLE visits')
      ..execute('DROP TABLE visit_photos')
      ..execute('DROP TABLE visit_confirmations')
      ..execute('ALTER TABLE villages DROP COLUMN meeting_point_lat')
      ..execute('ALTER TABLE villages DROP COLUMN meeting_point_lon')
      ..execute('ALTER TABLE villages DROP COLUMN meeting_point_radius_m')
      ..execute('PRAGMA user_version = 3')
      ..close();

    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    expect(await userVersion(db), currentVersion);
    expect(await tables(db), containsAll(v4Tables));
    expect(await db.getValue('settings.locale'), 'mr');
    expect((await db.select(db.villages).getSingle()).name, 'Kondapur');
    expect((await db.select(db.outboxTable).getSingle()).opId, 'op-1');
    final indexes = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .get();
    expect(
      indexes.map((r) => r.read<String>('name')),
      contains('location_buffer_session'),
    );
    expect(await db.select(db.locationBuffer).get(), isEmpty);
    expect(await db.select(db.dutySessions).get(), isEmpty);

    // The new tables are usable right away.
    await db
        .into(db.dutySessions)
        .insert(
          DutySessionsCompanion.insert(
            id: 'ds-1',
            startAt: DateTime.utc(2026, 9, 21, 3, 30),
            updatedAt: DateTime.utc(2026, 9, 21, 3, 30),
          ),
        );
    await db
        .into(db.locationBuffer)
        .insert(
          LocationBufferCompanion.insert(
            sessionId: 'ds-1',
            ts: DateTime.utc(2026, 9, 21, 3, 31),
            lat: 17.4,
            lon: 78.4,
            accuracyM: 8,
          ),
        );
    expect((await db.select(db.locationBuffer).getSingle()).sessionId, 'ds-1');
  });

  test('a v4 database migrates to v5: visit tables and the village meeting '
      'point columns added, duty and outbox rows kept', () async {
    final file = File('${dir.path}/v4.db');
    final seed = AppDatabase(NativeDatabase(file));
    await seed.setValue('settings.locale', 'hi');
    await seed
        .into(seed.villages)
        .insert(
          VillagesCompanion.insert(
            id: 'v-1',
            name: 'Kondapur',
            updatedAt: DateTime.utc(2026, 9, 20),
          ),
        );
    await seed
        .into(seed.dutySessions)
        .insert(
          DutySessionsCompanion.insert(
            id: 'ds-1',
            startAt: DateTime.utc(2026, 9, 21, 3, 30),
            updatedAt: DateTime.utc(2026, 9, 21, 3, 30),
          ),
        );
    await seed
        .into(seed.outboxTable)
        .insert(
          OutboxTableCompanion.insert(
            opId: 'op-1',
            seq: 1,
            entity: 'duty_session',
            action: 'create',
            entityId: 'ds-1',
            payload: '{}',
            clientTs: '2026-09-21T03:30:00.000Z',
          ),
        );
    await seed.close();
    final raw = sqlite.sqlite3.open(file.path);
    raw
      ..execute('DROP TABLE visits')
      ..execute('DROP TABLE visit_photos')
      ..execute('DROP TABLE visit_confirmations')
      ..execute('ALTER TABLE villages DROP COLUMN meeting_point_lat')
      ..execute('ALTER TABLE villages DROP COLUMN meeting_point_lon')
      ..execute('ALTER TABLE villages DROP COLUMN meeting_point_radius_m')
      ..execute('PRAGMA user_version = 4')
      ..close();

    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    expect(await userVersion(db), currentVersion);
    expect(await tables(db), containsAll(v5Tables));
    expect(
      await columns(db, 'villages'),
      containsAll(<String>[
        'meeting_point_lat',
        'meeting_point_lon',
        'meeting_point_radius_m',
      ]),
    );
    expect(await db.getValue('settings.locale'), 'hi');
    final village = await db.select(db.villages).getSingle();
    expect(village.name, 'Kondapur');
    expect(village.meetingPointLat, isNull);
    expect((await db.select(db.dutySessions).getSingle()).id, 'ds-1');
    expect((await db.select(db.outboxTable).getSingle()).opId, 'op-1');
    final indexes = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .get();
    expect(
      indexes.map((r) => r.read<String>('name')),
      containsAll(<String>[
        'visits_checkin',
        'visit_photos_visit',
        'visit_confirmations_visit',
      ]),
    );
    expect(await db.select(db.visits).get(), isEmpty);

    // The new tables are usable right away.
    await db
        .into(db.visits)
        .insert(
          VisitsCompanion.insert(
            id: 'visit-1',
            farmerId: 'f-1',
            checkinAt: DateTime.utc(2026, 9, 21, 4),
            checkinLat: 17.4,
            checkinLon: 78.4,
            updatedAt: DateTime.utc(2026, 9, 21, 4),
          ),
        );
    await db
        .into(db.visitPhotos)
        .insert(
          VisitPhotosCompanion.insert(
            id: 'photo-1',
            visitId: 'visit-1',
            updatedAt: DateTime.utc(2026, 9, 21, 4, 1),
          ),
        );
    await db
        .into(db.visitConfirmations)
        .insert(
          VisitConfirmationsCompanion.insert(
            id: 'conf-1',
            visitId: 'visit-1',
            channel: 'sms_otp',
            updatedAt: DateTime.utc(2026, 9, 21, 4, 2),
          ),
        );
    expect((await db.select(db.visits).getSingle()).status, 'open');
    expect((await db.select(db.visitPhotos).getSingle()).takenInApp, isTrue);
    expect(
      (await db.select(db.visitConfirmations).getSingle()).status,
      'pending',
    );
  });

  test(
    'a fresh database is created at the current version with every table',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      expect(await userVersion(db), currentVersion);
      expect(
        await tables(db),
        containsAll(<String>{
          ...v2Tables,
          'villages',
          ...v4Tables,
          ...v5Tables,
        }),
      );
    },
  );

  test(
    're-opening a current database does not run the upgrade again',
    () async {
      final file = File('${dir.path}/v5.db');
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
