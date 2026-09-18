import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import '../utils/format.dart';
import 'app_button.dart';

/// Large On duty / Off duty switch card with elapsed time and the
/// "location on while on duty" note (SPEC 13.1 `DutyToggle`, FA-010).
class DutyToggle extends StatelessWidget {
  /// Creates the card.
  const DutyToggle({
    required this.onDuty,
    required this.onChanged,
    this.elapsed = Duration.zero,
    this.loading = false,
    this.blockedReason,
    this.blockedActionLabel,
    this.onBlockedAction,
    super.key,
  });

  /// Whether the officer is currently on duty.
  final bool onDuty;

  /// Called with the requested new state; `null` disables the switch.
  final ValueChanged<bool>? onChanged;

  /// Time since duty started (only shown when [onDuty]).
  final Duration elapsed;

  /// Shows a spinner while the state is changing.
  final bool loading;

  /// Why the switch is disabled (FA-011: "Accept the location policy to go
  /// on duty"); shown under the card with [blockedActionLabel].
  final String? blockedReason;

  /// Label of the link next to [blockedReason] ("Review policy").
  final String? blockedActionLabel;

  /// Tap handler of the link.
  final VoidCallback? onBlockedAction;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final blocked = blockedReason != null;
    final enabled = onChanged != null && !loading && !blocked;
    final accent = onDuty ? p.statusSuccess : p.textSecondary;

    return Semantics(
      toggled: onDuty,
      label: onDuty ? l10n.dutyOn : l10n.dutyOff,
      child: Material(
        color: onDuty ? app.tint(p.statusSuccessContainer) : p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
          side: BorderSide(
            color: onDuty ? p.statusSuccess : p.border,
            width: app.borderWidth,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? () => onChanged!(!onDuty) : null,
          child: Padding(
            padding: const EdgeInsets.all(Tokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      onDuty ? Icons.work_outline : Icons.work_off_outlined,
                      color: accent,
                      size: Tokens.space8,
                    ),
                    const SizedBox(width: Tokens.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            onDuty ? l10n.dutyOn : l10n.dutyOff,
                            style: app.text.heading.copyWith(color: accent),
                          ),
                          if (onDuty)
                            Text(
                              l10n.dutyElapsed(formatElapsed(elapsed)),
                              style: app.text.body.copyWith(
                                color: p.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (loading)
                      const SizedBox.square(
                        dimension: Tokens.sizeIcon,
                        child: CircularProgressIndicator(
                          strokeWidth: Tokens.borderWidthSunlight,
                        ),
                      )
                    else
                      SizedBox(
                        height: Tokens.sizeTouchTargetMin,
                        child: Switch.adaptive(
                          value: onDuty,
                          onChanged: enabled ? onChanged : null,
                          activeTrackColor: p.statusSuccess,
                          inactiveTrackColor: app.tint(p.border),
                          inactiveThumbColor: p.textSecondary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: Tokens.space3),
                Text(
                  onDuty ? l10n.dutyGoOff : l10n.dutyGoOn,
                  style: app.text.label.copyWith(
                    color: blocked ? p.textMuted : p.primary,
                  ),
                ),
                if (blocked) ...<Widget>[
                  const SizedBox(height: Tokens.space2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.lock_outline,
                        size: Tokens.space4,
                        color: p.statusWarning,
                      ),
                      const SizedBox(width: Tokens.space1),
                      Expanded(
                        child: Text(
                          blockedReason!,
                          style: app.text.caption.copyWith(
                            color: p.statusWarning,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (blockedActionLabel != null && onBlockedAction != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppButton(
                        key: const Key('duty-blocked-action'),
                        label: blockedActionLabel!,
                        variant: AppButtonVariant.tertiary,
                        size: AppButtonSize.medium,
                        expand: false,
                        icon: Icons.description_outlined,
                        onPressed: onBlockedAction,
                      ),
                    ),
                ],
                const SizedBox(height: Tokens.space2),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.location_on_outlined,
                      size: Tokens.space4,
                      color: p.textSecondary,
                    ),
                    const SizedBox(width: Tokens.space1),
                    Expanded(
                      child: Text(
                        l10n.dutyLocationNote,
                        style: app.text.caption.copyWith(
                          color: p.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
