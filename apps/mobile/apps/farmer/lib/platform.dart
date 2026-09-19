import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

/// NF-009 audio prompts over the device's text-to-speech voice for the
/// locale (`te-IN`, `hi-IN`, ...). When the phone has no voice for the
/// language, [isAvailable] is false and the speaker buttons show "Audio
/// unavailable". Recorded clips by native speakers (human gate) replace
/// this class behind [AudioPrompt] without touching the screens.
class TtsAudioPrompt implements AudioPrompt {
  /// Creates the player.
  TtsAudioPrompt() : _tts = FlutterTts();

  final FlutterTts _tts;
  final Map<String, bool> _available = <String, bool>{};

  static String _tag(Locale locale) => '${locale.languageCode}-IN';

  @override
  Future<bool> isAvailable(Locale locale) async {
    final tag = _tag(locale);
    final known = _available[tag];
    if (known != null) return known;
    bool ok;
    try {
      ok = (await _tts.isLanguageAvailable(tag)) == true;
    } on Object {
      ok = false;
    }
    return _available[tag] = ok;
  }

  @override
  Future<AudioPlayResult> play({
    required String promptId,
    required String text,
    required Locale locale,
  }) async {
    if (!await isAvailable(locale)) return AudioPlayResult.unavailable;
    try {
      await _tts.stop();
      await _tts.setLanguage(_tag(locale));
      // Slower than default: farmers hear it once, outdoors.
      await _tts.setSpeechRate(0.42);
      await _tts.speak(text);
      return AudioPlayResult.played;
    } on Object {
      _available[_tag(locale)] = false;
      return AudioPlayResult.unavailable;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } on Object {
      // Nothing playing.
    }
  }
}

/// F60 QR scan over `mobile_scanner` (unbundled ML Kit model, FM-014):
/// returns the first QR code read, or null when the farmer goes back.
class MobileScannerQrScanner implements BarcodeScanner {
  /// Creates the scanner.
  const MobileScannerQrScanner();

  @override
  Future<String?> scan(BuildContext context) => Navigator.of(context)
      .push<String>(
        MaterialPageRoute<String>(
          fullscreenDialog: true,
          builder: (_) => const _QrPage(),
        ),
      );
}

class _QrPage extends StatefulWidget {
  const _QrPage();

  @override
  State<_QrPage> createState() => _QrPageState();
}

class _QrPageState extends State<_QrPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.kisanScanTitle)),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          if (_done) return;
          for (final b in capture.barcodes) {
            final value = b.rawValue;
            if (value != null && value.isNotEmpty) {
              _done = true;
              Navigator.of(context).pop(value);
              return;
            }
          }
        },
      ),
    );
  }
}

/// UPI intents, phone calls and WhatsApp over `url_launcher`.
class LauncherUrlOpener implements UrlOpener {
  /// Creates the opener.
  const LauncherUrlOpener();

  @override
  Future<bool> open(String url) async {
    try {
      return await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } on Object {
      return false;
    }
  }
}
