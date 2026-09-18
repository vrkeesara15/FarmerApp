import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:share_plus/share_plus.dart';

/// A57 "Share invoice on WhatsApp": the OS share sheet (WhatsApp is picked
/// there) with the signed invoice PDF link.
class SharePlusInvoiceSharer implements InvoiceSharer {
  /// Creates the sharer.
  const SharePlusInvoiceSharer();

  @override
  Future<void> share(String text, {String? subject}) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }
}
