import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// Data for a [CropChip].
@immutable
class CropChipData {
  /// Creates the data.
  const CropChipData({
    required this.name,
    this.stage,
    this.icon = Icons.eco_outlined,
  });

  /// Crop name, already localised.
  final String name;

  /// Current growth stage label, already localised.
  final String? stage;

  /// Pictogram for the crop.
  final IconData icon;
}

/// Crop icon + name + stage chip (SPEC 13.1 `CropChip`).
class CropChip extends StatelessWidget {
  /// Creates the chip.
  const CropChip({
    required this.data,
    this.selected = false,
    this.onTap,
    super.key,
  });

  /// Crop to show.
  final CropChipData data;

  /// Selected state (filled primary container).
  final bool selected;

  /// Optional tap handler; when set the chip is a toggle button.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final fg = selected ? p.primary : p.text;
    final label = data.stage == null
        ? data.name
        : '${data.name} · ${data.stage}';
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? app.tint(p.primaryContainer) : p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusChip),
          side: BorderSide(
            color: selected ? p.primary : p.border,
            width: app.borderWidth,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: Tokens.sizeTouchTargetMin - Tokens.space2,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Tokens.space3,
                vertical: Tokens.space2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(data.icon, size: Tokens.sizeIcon, color: fg),
                  const SizedBox(width: Tokens.space2),
                  Text(data.name, style: app.text.label.copyWith(color: fg)),
                  if (data.stage != null) ...<Widget>[
                    const SizedBox(width: Tokens.space1),
                    Text(
                      '· ${data.stage}',
                      style: app.text.caption.copyWith(color: p.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
