import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';

/// A06 Permissions explainer: one card per permission with the reason,
/// then the system prompt (location first, then "Allow all the time" per
/// the Play background-location policy, camera, notifications).
class PermissionsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  final Map<AppPermission, PermissionOutcome> _status =
      <AppPermission, PermissionOutcome>{};
  AppPermission? _asking;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final gate = ref.read(permissionGateProvider);
    for (final p in AppPermission.values) {
      final s = await gate.status(p);
      if (!mounted) return;
      setState(() => _status[p] = s);
    }
  }

  Future<void> _ask(AppPermission p) async {
    final gate = ref.read(permissionGateProvider);
    setState(() => _asking = p);
    final outcome = _status[p] == PermissionOutcome.permanentlyDenied
        ? await _openSettings(gate)
        : await gate.request(p);
    if (!mounted) return;
    setState(() {
      _status[p] = outcome;
      _asking = null;
    });
  }

  Future<PermissionOutcome> _openSettings(PermissionGate gate) async {
    await gate.openSettings();
    return PermissionOutcome.permanentlyDenied;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final locationGranted =
        _status[AppPermission.location] == PermissionOutcome.granted;
    final cards = <(AppPermission, IconData, String, String)>[
      (
        AppPermission.location,
        Icons.location_on_outlined,
        l10n.permLocationTitle,
        l10n.permLocationBody,
      ),
      (
        AppPermission.backgroundLocation,
        Icons.my_location_outlined,
        l10n.permBackgroundTitle,
        l10n.permBackgroundBody,
      ),
      (
        AppPermission.camera,
        Icons.photo_camera_outlined,
        l10n.permCameraTitle,
        l10n.permCameraBody,
      ),
      (
        AppPermission.notifications,
        Icons.notifications_outlined,
        l10n.permNotificationsTitle,
        l10n.permNotificationsBody,
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.permissionsTitle),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                l10n.permissionsIntro,
                style: app.text.body.copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: Tokens.space4),
              for (final (perm, icon, title, body) in cards)
                Padding(
                  padding: const EdgeInsets.only(bottom: Tokens.space3),
                  child: _PermissionCard(
                    key: Key('perm-${perm.name}'),
                    icon: icon,
                    title: title,
                    body: body,
                    status: _status[perm],
                    busy: _asking == perm,
                    // Background location is only asked once foreground
                    // location is granted (Android shows its own page).
                    enabled:
                        perm != AppPermission.backgroundLocation ||
                        locationGranted,
                    onAllow: () => _ask(perm),
                  ),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          child: AppButton(
            key: const Key('permissions-continue'),
            label: l10n.actionContinue,
            icon: Icons.arrow_forward,
            onPressed: () => context.go(AppRoutes.registered),
          ),
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.status,
    required this.busy,
    required this.enabled,
    required this.onAllow,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final PermissionOutcome? status;
  final bool busy;
  final bool enabled;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final granted = status == PermissionOutcome.granted;
    final permanentlyDenied = status == PermissionOutcome.permanentlyDenied;
    final statusText = status == null
        ? null
        : granted
        ? l10n.permGranted
        : l10n.permDenied;
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        side: BorderSide(
          color: granted ? p.statusSuccess : p.border,
          width: app.borderWidth,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Tokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, color: granted ? p.statusSuccess : p.primary),
                const SizedBox(width: Tokens.space2),
                Expanded(child: Text(title, style: app.text.heading)),
                if (statusText != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        granted ? Icons.check_circle : Icons.cancel_outlined,
                        size: Tokens.space4,
                        color: granted ? p.statusSuccess : p.textSecondary,
                      ),
                      const SizedBox(width: Tokens.space1),
                      Text(
                        statusText,
                        style: app.text.caption.copyWith(
                          color: granted ? p.statusSuccess : p.textSecondary,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: Tokens.space2),
            Text(body, style: app.text.body),
            if (!granted) ...<Widget>[
              const SizedBox(height: Tokens.space2),
              AppButton(
                label: permanentlyDenied
                    ? l10n.permOpenSettings
                    : l10n.permAllow,
                icon: permanentlyDenied
                    ? Icons.settings_outlined
                    : Icons.check_outlined,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.medium,
                expand: false,
                loading: busy,
                onPressed: enabled ? onAllow : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
