import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:share_plus/share_plus.dart';

/// FM-013: the OS share sheet, where the farmer picks WhatsApp (the agent
/// app shares invoices through the same package).
class SharePlusTextSharer implements TextSharer {
  /// Creates the sharer.
  const SharePlusTextSharer();

  @override
  Future<void> share(String text, {String? subject}) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }
}
