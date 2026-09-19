import '../i18n/generated/core_localizations.dart';
import '../photo/photo_quality.dart';

/// Maps [PhotoTipKeys] to localised retake tips (FM-004).
extension PhotoTipText on CoreLocalizations {
  /// The tip for [tipKey]; unknown keys fall back to the "ok" line.
  String photoTip(String tipKey) => switch (tipKey) {
    PhotoTipKeys.blurry => photoTipBlurry,
    PhotoTipKeys.dark => photoTipDark,
    PhotoTipKeys.notPlant => photoTipNotPlant,
    _ => photoTipOk,
  };
}
