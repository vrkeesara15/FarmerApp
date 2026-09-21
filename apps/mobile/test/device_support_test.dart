import 'dart:io';

import 'package:test/test.dart';

/// NF-001: "Android 8+ (API 26), 2 GB RAM, 16 GB storage; tested on 3
/// reference devices".
///
/// Only the first of those three can be asserted from a test: RAM and storage
/// are measured on a device, by a person, against docs/device-matrix.md. What
/// *can* be automated is the floor itself, and it is worth automating because
/// `minSdk` moves on its own: a plugin upgrade raises it, `flutter create`
/// regenerates the file with the Flutter default, and nothing complains until
/// a farmer on an Android 8 phone finds the app missing from the Play Store.
void main() {
  final root = Directory.current.path.endsWith('/apps/mobile')
      ? Directory.current.path
      : '${Directory.current.path}/apps/mobile';

  /// NF-001: Android 8.0 Oreo.
  const int minSdkFloor = 26;

  for (final app in <String>['agent', 'farmer']) {
    group('$app app', () {
      final gradle = File('$root/apps/$app/android/app/build.gradle.kts');

      test('declares minSdk $minSdkFloor (Android 8, NF-001)', () {
        expect(gradle.existsSync(), isTrue, reason: 'missing ${gradle.path}');
        final text = gradle.readAsStringSync();
        final match = RegExp(r'minSdk\s*=\s*(\d+)').firstMatch(text);
        expect(
          match,
          isNotNull,
          reason:
              'minSdk is not set explicitly, so it follows whatever Flutter '
              'defaults to this month. NF-001 is a promise to a farmer with '
              'an Android 8 phone; pin it.',
        );
        final minSdk = int.parse(match!.group(1)!);
        expect(
          minSdk,
          minSdkFloor,
          reason:
              'NF-001 supports Android 8 (API 26). Raising this drops real '
              'devices in the pilot districts: change the SPEC first, with '
              'the Play Console device-reach number to back it.',
        );
      });

      test('does not silently raise the floor through a manifest override', () {
        final manifest = File(
          '$root/apps/$app/android/app/src/main/AndroidManifest.xml',
        );
        expect(manifest.existsSync(), isTrue);
        expect(
          manifest.readAsStringSync(),
          isNot(contains('uses-sdk')),
          reason:
              'a <uses-sdk> element in the manifest overrides the Gradle '
              'value and would make the test above meaningless',
        );
      });
    });
  }

  test('both apps ship the same floor', () {
    int minSdkOf(String app) => int.parse(
      RegExp(r'minSdk\s*=\s*(\d+)')
          .firstMatch(
            File('$root/apps/$app/android/app/build.gradle.kts')
                .readAsStringSync(),
          )!
          .group(1)!,
    );
    // A farmer and the officer who visits them are often on the same handset.
    expect(minSdkOf('agent'), minSdkOf('farmer'));
  });

  test('the APK size gate covers both shipped ABIs (NF-001 / FM-014)', () {
    // Play delivers one ABI per device, so the 25 MB budget applies per ABI.
    // A gate that only built arm64 would miss armeabi-v7a, which is exactly
    // the older, cheaper phone NF-001 is about.
    final script = File('$root/tool/apk_size_check.sh').readAsStringSync();
    expect(script, contains('--split-per-abi'));
    expect(script, contains('android-arm,android-arm64'));
    expect(script, contains('app-armeabi-v7a-release.apk'));
    expect(script, contains('app-arm64-v8a-release.apk'));
  });
}
