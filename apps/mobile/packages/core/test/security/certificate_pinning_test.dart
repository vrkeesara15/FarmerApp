import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// SEC-024 certificate pinning. Fixture certificates are generated in the
/// test with the `openssl` CLI (RSA and EC keys, SAN localhost); the pin the
/// app computes must equal the one `openssl` prints, and a TLS server with
/// the certificate is reached only when its pin is configured.
class _Fixture {
  _Fixture(this.certPem, this.keyPem, this.der, this.opensslPin);

  final String certPem;
  final String keyPem;
  final Uint8List der;
  final String opensslPin;
}

Future<ProcessResult> _run(List<String> args, {String? stdin}) async {
  if (stdin == null) return Process.run('openssl', args);
  final p = await Process.start('openssl', args);
  p.stdin.add(utf8.encode(stdin));
  await p.stdin.close();
  final out = await p.stdout.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
  final err = await p.stderr.transform(utf8.decoder).join();
  return ProcessResult(p.pid, await p.exitCode, out, err);
}

/// A throwaway CA (the "system trust store" of the test).
Future<(String pem, String key)> _makeCa(Directory dir) async {
  final key = '${dir.path}/ca.key';
  final cert = '${dir.path}/ca.pem';
  final gen = await _run(<String>[
    'req',
    '-x509',
    '-nodes',
    '-days',
    '2',
    '-subj',
    '/CN=FarmerApp Test CA',
    '-newkey',
    'rsa:2048',
    '-keyout',
    key,
    '-out',
    cert,
  ]);
  expect(gen.exitCode, 0, reason: '${gen.stderr}');
  return (cert, key);
}

/// A server certificate for localhost signed by the test CA.
Future<_Fixture> _makeCert(
  Directory dir,
  (String, String) ca,
  String name,
  List<String> keyArgs,
) async {
  final key = '${dir.path}/$name.key';
  final csr = '${dir.path}/$name.csr';
  final cert = '${dir.path}/$name.pem';
  final der = '${dir.path}/$name.der';
  final ext = File('${dir.path}/$name.ext')
    ..writeAsStringSync(
      'basicConstraints=CA:FALSE\n'
      'keyUsage=digitalSignature,keyEncipherment\n'
      'extendedKeyUsage=serverAuth\n'
      'subjectAltName=DNS:localhost,IP:127.0.0.1\n',
    );
  final req = await _run(<String>[
    'req',
    '-new',
    '-nodes',
    '-subj',
    '/CN=localhost',
    ...keyArgs,
    '-keyout',
    key,
    '-out',
    csr,
  ]);
  expect(req.exitCode, 0, reason: '${req.stderr}');
  final sign = await _run(<String>[
    'x509',
    '-req',
    '-in',
    csr,
    '-CA',
    ca.$1,
    '-CAkey',
    ca.$2,
    '-CAcreateserial',
    '-days',
    '2',
    '-extfile',
    ext.path,
    '-out',
    cert,
  ]);
  expect(sign.exitCode, 0, reason: '${sign.stderr}');
  final toDer = await _run(<String>[
    'x509',
    '-in',
    cert,
    '-outform',
    'der',
    '-out',
    der,
  ]);
  expect(toDer.exitCode, 0, reason: '${toDer.stderr}');
  // Reference pin: openssl x509 -pubkey | openssl pkey -pubin -outform der
  //   | openssl dgst -sha256 -binary | base64
  final pub = await _run(<String>['x509', '-in', cert, '-pubkey', '-noout']);
  final pubDer = await _run(<String>[
    'pkey',
    '-pubin',
    '-outform',
    'der',
  ], stdin: pub.stdout as String);
  final digest = await Process.start('openssl', <String>[
    'dgst',
    '-sha256',
    '-binary',
  ]);
  digest.stdin.add(pubDer.stdout as List<int>);
  await digest.stdin.close();
  final hash = await digest.stdout.fold<List<int>>(
    <int>[],
    (a, b) => a..addAll(b),
  );
  expect(hash, hasLength(32));
  return _Fixture(
    File(cert).readAsStringSync(),
    File(key).readAsStringSync(),
    File(der).readAsBytesSync(),
    base64.encode(hash),
  );
}

void main() {
  final hasOpenssl = () {
    try {
      return Process.runSync('openssl', <String>['version']).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }();
  final skip = hasOpenssl
      ? null
      : 'openssl CLI not found: fixture certificates '
            'cannot be generated';

  group('pin policy', () {
    test('local dev hosts and plain http are never pinned', () {
      final pinning = CertificatePinning(const <String>['abc=']);
      expect(
        pinning.appliesTo(Uri.parse('https://api.farmerapp.in/v1')),
        isTrue,
      );
      expect(pinning.appliesTo(Uri.parse('http://10.0.2.2:8000/v1')), isFalse);
      expect(pinning.appliesTo(Uri.parse('https://10.0.2.2:8443')), isFalse);
      expect(pinning.appliesTo(Uri.parse('https://localhost')), isFalse);
      expect(pinning.appliesTo(Uri.parse('https://127.0.0.1')), isFalse);
      expect(pinning.appliesTo(Uri.parse('http://api.farmerapp.in')), isFalse);
    });

    test('pins accept the sha256/ prefix and ignore blanks', () {
      final pinning = CertificatePinning(const <String>[
        ' sha256/AAA= ',
        '',
        'BBB=',
      ]);
      expect(pinning.pins, <String>{'AAA=', 'BBB='});
      expect(CertificatePinning(''.split(',')).pins, isEmpty);
    });

    test('garbage is not a certificate', () {
      expect(
        () => subjectPublicKeyInfo(Uint8List.fromList(<int>[1, 2, 3])),
        throwsFormatException,
      );
      expect(
        CertificatePinning(const <String>['x'])
            .matches(Uint8List.fromList(<int>[0x30, 0x82])),
        isFalse,
      );
    });
  });

  group('with generated certificates', () {
    late Directory dir;
    late _Fixture rsa;
    late _Fixture ec;
    late String caPem;

    setUpAll(() async {
      if (!hasOpenssl) return;
      dir = Directory.systemTemp.createTempSync('sec024_pins_');
      final ca = await _makeCa(dir);
      caPem = File(ca.$1).readAsStringSync();
      rsa = await _makeCert(dir, ca, 'rsa', <String>['-newkey', 'rsa:2048']);
      ec = await _makeCert(dir, ca, 'ec', <String>[
        '-newkey',
        'ec',
        '-pkeyopt',
        'ec_paramgen_curve:prime256v1',
      ]);
    });

    tearDownAll(() {
      if (hasOpenssl && dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('SPKI SHA-256 equals the openssl reference (RSA and EC)', () {
      expect(spkiSha256Base64(rsa.der), rsa.opensslPin);
      expect(spkiSha256Base64(ec.der), ec.opensslPin);
      expect(rsa.opensslPin, isNot(ec.opensslPin));
    }, skip: skip);

    test('matches only the configured pins', () {
      expect(
        CertificatePinning(<String>[rsa.opensslPin]).matches(rsa.der),
        isTrue,
      );
      expect(
        CertificatePinning(<String>[ec.opensslPin]).matches(rsa.der),
        isFalse,
      );
      expect(
        CertificatePinning(<String>['sha256/${rsa.opensslPin}'])
            .matches(rsa.der),
        isTrue,
      );
    }, skip: skip);

    group('over TLS', () {
      late HttpServer server;
      late int requests;
      late SecurityContext trust;

      setUp(() async {
        if (!hasOpenssl) return;
        requests = 0;
        final serverContext = SecurityContext()
          ..useCertificateChainBytes(utf8.encode(rsa.certPem))
          ..usePrivateKeyBytes(utf8.encode(rsa.keyPem));
        server = await HttpServer.bindSecure('localhost', 0, serverContext);
        server.listen((request) {
          requests += 1;
          request.response
            ..statusCode = 200
            ..write('{"ok":true}');
          request.response.close();
        });
        // Trust the test CA like the system store trusts the real CA:
        // chain validation passes, only the pin decides.
        trust = SecurityContext()
          ..setTrustedCertificatesBytes(utf8.encode(caPem));
      });

      tearDown(() async {
        if (hasOpenssl) await server.close(force: true);
      });

      http.Client client(List<String> pins) => IOClient(
        createPinnedHttpClient(
          CertificatePinning(pins, exemptHosts: const <String>{}),
          context: trust,
        ),
      );

      Uri url() => Uri.parse('https://localhost:${server.port}/v1/me');

      test('the primary pin connects', () async {
        final response = await client(<String>[rsa.opensslPin]).get(url());
        expect(response.statusCode, 200);
        expect(requests, 1);
      }, skip: skip);

      test('the backup pin connects (primary rotated away)', () async {
        final response = await client(<String>[ec.opensslPin, rsa.opensslPin])
            .get(url());
        expect(response.statusCode, 200);
      }, skip: skip);

      test('a wrong pin fails before any request byte is sent', () async {
        await expectLater(
          client(<String>[ec.opensslPin]).get(
            url(),
            headers: <String, String>{'Authorization': 'Bearer secret'},
          ),
          throwsA(isA<CertificatePinningException>()),
        );
        expect(requests, 0);
        // Through the apps' client it is an ordinary transport failure.
        final secure = SecureApiClient(inner: client(<String>[ec.opensslPin]));
        await expectLater(
          secure.get(url()),
          throwsA(
            isA<http.ClientException>().having(
              (e) => e.message,
              'message',
              contains('pin mismatch'),
            ),
          ),
        );
        expect(requests, 0);
      }, skip: skip);

      test(
        'no pin configured for a pinned host: refused (fail closed)',
        () async {
          await expectLater(client(<String>[]).get(url()), throwsA(anything));
          expect(requests, 0);
        },
        skip: skip,
      );

      test('local dev hosts skip the pin (the default exemption)', () async {
        final c = IOClient(
          createPinnedHttpClient(
            CertificatePinning(const <String>[]),
            context: trust,
          ),
        );
        expect((await c.get(url())).statusCode, 200);
      }, skip: skip);
    });
  });
}
