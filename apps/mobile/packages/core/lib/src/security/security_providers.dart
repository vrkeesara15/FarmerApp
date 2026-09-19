import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/open_database.dart';
import '../duty/duty_providers.dart' show locationPolicyProvider;
import '../state/tenant_settings.dart';
import '../sync/sync_providers.dart';
import '../visits/visit_providers.dart';
import 'api_http_client.dart';
import 'remote_wipe.dart';

/// The wipe order shared by every API client of this app run (SEC-025);
/// the apps override it with the [WipeSignal] their [SecureApiClient]
/// reports to.
final Provider<WipeSignal> wipeSignalProvider = Provider<WipeSignal>(
  (ref) => WipeSignal(),
);

/// A remote wipe happened before this app run: the router opens A08
/// "Signed out by your administrator" (the apps override it from
/// [hasWipeNotice] at start-up).
final Provider<bool> wipeNoticeProvider = Provider<bool>((ref) => false);

/// `GET /v1/devices/me/status`; the apps override it with
/// [HttpDeviceStatusApi].
final Provider<DeviceStatusApi> deviceStatusApiProvider =
    Provider<DeviceStatusApi>((ref) => FakeDeviceStatusApi());

/// `GET /v1/settings/public`; the apps override it with
/// [HttpTenantSettingsApi].
final Provider<TenantSettingsApi> tenantSettingsApiProvider =
    Provider<TenantSettingsApi>((ref) => FakeTenantSettingsApi());

/// Pulls and caches the tenant settings; a pull refreshes the visit
/// settings and the duty policy the duty controller runs on.
final Provider<TenantSettingsSync> tenantSettingsSyncProvider =
    Provider<TenantSettingsSync>(
      (ref) => TenantSettingsSync(
        db: ref.watch(appDatabaseProvider),
        api: ref.watch(tenantSettingsApiProvider),
        clock: ref.watch(clockProvider),
        onApplied: (_) {
          ref
            ..invalidate(visitSettingsProvider)
            ..invalidate(tenantSettingsProvider);
          if (ref.exists(locationPolicyProvider)) {
            ref.read(locationPolicyProvider.notifier).reloadDutyPolicy();
          }
        },
      ),
    );

/// The cached tenant settings (defaults until the first pull).
final FutureProvider<PublicTenantSettings> tenantSettingsProvider =
    FutureProvider<PublicTenantSettings>(
      (ref) => ref.read(tenantSettingsSyncProvider).cached(),
    );
