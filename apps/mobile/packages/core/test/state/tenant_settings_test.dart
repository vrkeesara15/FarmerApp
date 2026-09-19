import 'dart:convert';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../duty/duty_harness.dart';

/// M2 follow-up: `GET /v1/settings/public` fills the local settings cache
/// the visit pre-check, the proof checklist, the duty controller and the
/// sampling cadence read; the SPEC defaults hold until the first pull.
const Map<String, Object?> _wire = <String, Object?>{
  'geofence_radius_m': 80,
  'meeting_point_radius_m': 250,
  'min_visit_duration_s': 600,
  'auto_duty_end_local_time': '19:30',
  'idle_end_minutes': 45,
  'location_policy_version': '2026-09-v2',
  'sampling': <String, Object?>{
    'moving_s': 60,
    'stationary_s': 300,
    'upload_s': 1800,
  },
  'languages_enabled': <String>['en', 'te'],
  'default_language': 'te',
  'branding': <String, Object?>{
    'app_name_agent': 'Sahayak',
    'app_name_farmer': null,
    'primary_colour': '#123456',
    'logo_blob_uri': null,
    'support_phone': '+919000000000',
  },
};

void main() {
  group('PublicTenantSettings', () {
    test('parses the API shape', () {
      final s = PublicTenantSettings.fromJson(_wire);
      expect(s.geofenceRadiusM, 80);
      expect(s.meetingPointRadiusM, 250);
      expect(s.minVisitDurationS, 600);
      expect(s.autoDutyEndLocalTime, '19:30');
      expect(s.samplingMovingS, 60);
      expect(s.samplingStationaryS, 300);
      expect(s.samplingUploadS, 1800);
      expect(s.languagesEnabled, <String>['en', 'te']);
      expect(s.defaultLanguage, 'te');
      expect(s.branding.appNameAgent, 'Sahayak');
      expect(s.branding.primaryColour, '#123456');
      expect(PublicTenantSettings.fromJson(s.toJson()), s);
    });

    test('bad or missing values keep the SPEC defaults', () {
      final s = PublicTenantSettings.fromJson(const <String, Object?>{
        'geofence_radius_m': -5,
        'auto_duty_end_local_time': '25:99',
        'sampling': 'x',
        'branding': <String, Object?>{'primary_colour': 'red'},
      });
      expect(s, const PublicTenantSettings());
      expect(s.geofenceRadiusM, 150);
      expect(s.minVisitDurationS, 300);
      expect(s.autoDutyEndLocalTime, '20:00');
      expect(s.samplingMovingS, 120);
      expect(s.branding.primaryColour, '#1F6B3A');
    });
  });

  group('TenantSettingsSync', () {
    late DutyDeps deps;
    late FakeTenantSettingsApi api;
    late ProviderContainer c;

    setUp(() {
      deps = DutyDeps();
      api = FakeTenantSettingsApi();
      c = ProviderContainer(
        overrides: <Override>[
          ...deps.overrides(),
          tenantSettingsApiProvider.overrideWithValue(api),
        ],
      );
    });

    tearDown(() async {
      c.dispose();
      await deps.dispose();
    });

    TenantSettingsSync sync() => c.read(tenantSettingsSyncProvider);

    test('never fetched: the defaults apply', () async {
      expect(await sync().cached(), const PublicTenantSettings());
      expect(await sync().fetchedAt(), isNull);
      expect(await c.read(visitSettingsProvider.future), const VisitSettings());
    });

    test(
      'a pull fills the visit settings and the duty policy caches',
      () async {
        api.settings = PublicTenantSettings.fromJson(_wire);
        expect(await sync().pull(), isNotNull);

        final visit = await c.read(visitRepositoryProvider).settings();
        expect(visit.geofenceRadiusM, 80);
        expect(visit.minVisitDurationS, 600);
        expect(visit.meetingPointRadiusM, 250);

        final duty = DutyPolicy.fromJson(
          jsonDecode((await deps.db.getValue('duty.policy'))!)
              as Map<String, Object?>,
        );
        expect(duty.movingInterval, const Duration(seconds: 60));
        expect(duty.stationaryInterval, const Duration(minutes: 5));
        expect(duty.uploadInterval, const Duration(minutes: 30));
        expect(duty.autoEndLocalTime, '19:30');
        expect(await sync().fetchedAt(), deps.clock.now);
        expect(
          (await c.read(tenantSettingsProvider.future)).defaultLanguage,
          'te',
        );
      },
    );

    test('the duty controller runs on the pulled cadence', () async {
      // The controller's policy state is live before the pull.
      await c.read(locationPolicyProvider.notifier).load();
      expect(
        c.read(locationPolicyProvider).duty.movingInterval,
        const Duration(minutes: 2),
      );
      api.settings = PublicTenantSettings.fromJson(_wire);
      await sync().pull();
      await pumpEventQueue();
      final duty = c.read(locationPolicyProvider).duty;
      expect(duty.movingInterval, const Duration(seconds: 60));
      expect(duty.autoEndLocalTime, '19:30');
      final cadence = SamplingCadence(duty);
      expect(cadence.policy.stationaryInterval, const Duration(minutes: 5));
    });

    test('offline keeps the cache; daily refresh only when stale', () async {
      expect(await sync().pull(), isNull);
      expect(await sync().cached(), const PublicTenantSettings());

      api.settings = PublicTenantSettings.fromJson(_wire);
      expect(await sync().pullIfStale(), isTrue);
      expect(api.calls, 2);
      deps.clock.advance(const Duration(hours: 23));
      expect(await sync().pullIfStale(), isFalse);
      expect(api.calls, 2);
      deps.clock.advance(const Duration(hours: 2));
      expect(await sync().pullIfStale(), isTrue);
      expect(api.calls, 3);

      api.settings = null; // offline again
      deps.clock.advance(const Duration(days: 2));
      expect(await sync().pullIfStale(), isFalse);
      expect((await sync().cached()).geofenceRadiusM, 80);
    });

    test('HttpTenantSettingsApi reads /v1/settings/public', () async {
      final requests = <http.Request>[];
      final rest = RestJsonClient(
        store: InMemoryTokenStore(
          session: AuthSession(
            accessToken: 'a',
            refreshToken: 'r',
            expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
            user: const AuthUser(
              id: 'u',
              tenantId: 't',
              phone: '+919000000004',
              name: 'R',
              role: 'field_officer',
              language: 'en',
              status: 'active',
            ),
          ),
        ),
        config: const ApiConfig(baseUrl: 'https://api.test'),
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode(_wire), 200);
        }),
      );
      final s = await HttpTenantSettingsApi(rest).fetch();
      expect(requests.single.url.path, '/v1/settings/public');
      expect(s!.geofenceRadiusM, 80);
      final offline = await HttpTenantSettingsApi(
        RestJsonClient(
          store: InMemoryTokenStore(),
          config: const ApiConfig(baseUrl: 'https://api.test'),
        ),
      ).fetch();
      expect(offline, isNull);
    });
  });

  group('login', () {
    test('a successful login pulls the tenant settings', () async {
      final deps = DutyDeps();
      final api = FakeTenantSettingsApi(
        settings: PublicTenantSettings.fromJson(_wire),
      );
      final c = ProviderContainer(
        overrides: <Override>[
          ...deps.overrides(),
          authApiProvider.overrideWithValue(FakeAuthApi()),
          tenantSettingsApiProvider.overrideWithValue(api),
        ],
      );
      addTearDown(() async {
        c.dispose();
        await deps.dispose();
      });
      final flow = c.read(authFlowProvider.notifier);
      await flow.requestOtp('9000000004');
      await flow.verifyOtp(FakeAuthApi.acceptedOtp);
      await pumpEventQueue();
      expect(api.calls, 1);
      expect(
        (await c.read(visitRepositoryProvider).settings()).geofenceRadiusM,
        80,
      );
    });

    test('device_not_bound: clear failure, no pull, no session', () async {
      final api = FakeTenantSettingsApi();
      final c = ProviderContainer(
        overrides: <Override>[
          authApiProvider.overrideWithValue(FakeAuthApi(deviceBound: false)),
          tenantSettingsApiProvider.overrideWithValue(api),
        ],
      );
      addTearDown(c.dispose);
      final flow = c.read(authFlowProvider.notifier);
      await flow.requestOtp('9000000004');
      await flow.verifyOtp(FakeAuthApi.acceptedOtp);
      final state = c.read(authFlowProvider);
      expect(state.failure, AuthFailure.deviceNotBound);
      expect(state.step, AuthStep.otp);
      expect(state.session, isNull);
      expect(state.phone, '9000000004', reason: 'the number is kept');
      expect(api.calls, 0);
    });
  });
}
