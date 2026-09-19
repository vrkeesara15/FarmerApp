import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show immutable;

/// SEC-024 certificate pinning for the API domain.
///
/// A pin is the base64 SHA-256 of the certificate's DER
/// `SubjectPublicKeyInfo` (the same value as OkHttp / Android
/// `<pin digest="SHA-256">` and `openssl x509 -pubkey | openssl pkey -pubin
/// -outform der | openssl dgst -sha256 -binary | base64`). Pins come from
/// `--dart-define=API_CERT_PINS=<primary>,<backup>` (per environment, see
/// `apps/mobile/config/env/*.json`).
///
/// `dart:io` exposes only the server's leaf certificate on a connection, so
/// the leaf SPKI is pinned; the backup pin is the SPKI of the next key pair
/// (generated and stored offline before it is needed), so a key rotation
/// ships in an app update before the certificate changes. The check runs in
/// the connection factory, after the TLS handshake and chain validation and
/// before a single request byte (bearer token included) is written.

/// Hosts that never get pinning: the Android emulator's alias for the
/// developer machine and loopback (local `make up` stack over plain HTTP).
const Set<String> localDevHosts = <String>{
  '10.0.2.2',
  '10.0.3.2',
  'localhost',
  '127.0.0.1',
  '::1',
};

/// Whether [host] is a local development host (no pinning).
bool isLocalDevHost(String host) => localDevHosts.contains(host.toLowerCase());

/// The pin failed (or no pin was configured for a pinned host).
class CertificatePinningException extends TlsException {
  /// Creates the exception.
  const CertificatePinningException(String host)
    : super('certificate pin mismatch for $host');
}

/// Pins for the API domain.
@immutable
class CertificatePinning {
  /// Creates the policy from base64 SPKI SHA-256 [pins] (a `sha256/` prefix
  /// is accepted and dropped). [exemptHosts] are never pinned (default:
  /// [localDevHosts]).
  CertificatePinning(Iterable<String> pins, {this.exemptHosts = localDevHosts})
    : pins = <String>{
        for (final p in pins)
          if (p.trim().isNotEmpty)
            p.trim().startsWith('sha256/') ? p.trim().substring(7) : p.trim(),
      };

  /// From `--dart-define=API_CERT_PINS=pinA,pinB`.
  factory CertificatePinning.fromEnvironment() =>
      CertificatePinning(configuredPins.split(','));

  /// The raw compile-time pin list.
  static const String configuredPins = String.fromEnvironment('API_CERT_PINS');

  /// Accepted SPKI hashes (base64).
  final Set<String> pins;

  /// Hosts that are never pinned (local development).
  final Set<String> exemptHosts;

  /// Pinning applies to TLS connections to anything but a local dev host.
  /// With no pins configured such connections are refused (fail closed):
  /// set real pins per environment before shipping (human gate).
  bool appliesTo(Uri uri) =>
      uri.isScheme('https') && !exemptHosts.contains(uri.host.toLowerCase());

  /// Whether [certificateDer] carries one of the [pins].
  bool matches(Uint8List certificateDer) {
    try {
      return pins.contains(spkiSha256Base64(certificateDer));
    } on FormatException {
      return false;
    }
  }
}

/// Base64 SHA-256 of the DER `SubjectPublicKeyInfo` of an X.509 certificate.
String spkiSha256Base64(Uint8List certificateDer) =>
    base64.encode(sha256.convert(subjectPublicKeyInfo(certificateDer)).bytes);

/// The DER `SubjectPublicKeyInfo` (tag, length and content) of an X.509
/// certificate: `Certificate ::= SEQUENCE { tbsCertificate SEQUENCE {
/// [0] version OPTIONAL, serialNumber, signature, issuer, validity, subject,
/// subjectPublicKeyInfo, … }, … }`.
Uint8List subjectPublicKeyInfo(Uint8List der) {
  final cert = _tlv(der, 0, 0x30);
  final tbs = _tlv(der, cert.contentStart, 0x30);
  var p = tbs.contentStart;
  final first = _tlv(der, p);
  if (first.tag == 0xA0) p = first.end; // explicit version
  for (final tag in const <int>[0x02, 0x30, 0x30, 0x30, 0x30]) {
    p = _tlv(der, p, tag).end; // serial, signature, issuer, validity, subject
  }
  final spki = _tlv(der, p, 0x30);
  if (spki.end > tbs.end) throw const FormatException('SPKI outside TBS');
  return Uint8List.sublistView(der, p, spki.end);
}

class _Tlv {
  const _Tlv(this.tag, this.contentStart, this.end);
  final int tag;
  final int contentStart;
  final int end;
}

_Tlv _tlv(Uint8List der, int offset, [int? expectTag]) {
  if (offset + 2 > der.length) throw const FormatException('truncated DER');
  final tag = der[offset];
  if (expectTag != null && tag != expectTag) {
    throw FormatException('unexpected DER tag 0x${tag.toRadixString(16)}');
  }
  var p = offset + 1;
  var length = der[p++];
  if (length & 0x80 != 0) {
    final n = length & 0x7f;
    if (n == 0 || n > 4 || p + n > der.length) {
      throw const FormatException('bad DER length');
    }
    length = 0;
    for (var i = 0; i < n; i++) {
      length = (length << 8) | der[p++];
    }
  }
  final end = p + length;
  if (end > der.length) throw const FormatException('truncated DER');
  return _Tlv(tag, p, end);
}

/// A `dart:io` [HttpClient] that validates the chain as usual and then
/// requires one of [pinning]'s pins on the server certificate for every
/// pinned host ([CertificatePinning.appliesTo]). Proxies are never used
/// (a pinned connection is always direct). [context] overrides the trust
/// store (tests trust a generated certificate).
HttpClient createPinnedHttpClient(
  CertificatePinning pinning, {
  SecurityContext? context,
  Duration connectionTimeout = const Duration(seconds: 20),
}) {
  final client = HttpClient(context: context)
    ..connectionTimeout = connectionTimeout
    ..findProxy = ((_) => 'DIRECT')
    ..badCertificateCallback = ((cert, host, port) => false);
  client.connectionFactory = (uri, proxyHost, proxyPort) async {
    if (!uri.isScheme('https')) {
      return Socket.startConnect(uri.host, uri.port);
    }
    final task = await SecureSocket.startConnect(
      uri.host,
      uri.port,
      context: context,
      onBadCertificate: (_) => false,
    );
    if (!pinning.appliesTo(uri)) return task;
    final checked = task.socket.then<Socket>((socket) {
      final cert = socket.peerCertificate;
      if (cert == null || !pinning.matches(cert.der)) {
        socket.destroy();
        throw CertificatePinningException(uri.host);
      }
      return socket;
    });
    return ConnectionTask.fromSocket(checked, task.cancel);
  };
  return client;
}
