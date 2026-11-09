import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// V2: verification locale de connexion par defi HMAC.
/// Ni streaming ni controle distant ne sont ouverts sans transport chiffre.
class RemoteLink {
  HttpServer? _server;
  bool get isServing => _server != null;
  static const int port = 47186;
  final Map<String, DateTime> _challenges = {};

  static bool isPrivateIPv4(String raw) {
    final parts = raw.trim().split('.');
    if (parts.length != 4) return false;
    final p = <int>[];
    for (final part in parts) {
      if (!RegExp(r'^(0|[1-9][0-9]{0,2})$').hasMatch(part)) return false;
      final value = int.parse(part);
      if (value > 255) return false;
      p.add(value);
    }
    return p[0] == 10 || (p[0] == 172 && p[1] >= 16 && p[1] <= 31) ||
        (p[0] == 192 && p[1] == 168);
  }

  static Future<List<String>> localAddresses() async {
    final addresses = <String>[];
    for (final interface in await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false)) {
      for (final addr in interface.addresses) {
        if (isPrivateIPv4(addr.address)) addresses.add(addr.address);
      }
    }
    return addresses;
  }

  static String createPairingCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(24, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  static String _newChallenge() {
    final rand = Random.secure();
    return base64UrlEncode(List.generate(32, (_) => rand.nextInt(256)));
  }

  static String _proof(String code, String challenge) =>
      Hmac(sha256, utf8.encode(code.trim())).convert(utf8.encode(challenge)).toString();

  Future<void> startHost(String code) async {
    if (!Platform.isWindows) throw const SocketException('Hote reserve a Windows');
    if (code.trim().length < 20) throw const FormatException('Code trop court');
    await stopHost();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: false);
    _server!.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.headers.set('Cache-Control', 'no-store');
      request.response.headers.set('X-Content-Type-Options', 'nosniff');
      final remote = request.connectionInfo?.remoteAddress.address ?? '';
      if (request.method != 'GET' || (!isPrivateIPv4(remote) && remote != '127.0.0.1')) {
        request.response.statusCode = HttpStatus.forbidden;
        request.response.write(jsonEncode({'error':'Reseau local uniquement'}));
      } else if (request.uri.path == '/v2/challenge') {
        _challenges.removeWhere((_, expiry) => DateTime.now().isAfter(expiry));
        if (_challenges.length >= 100) _challenges.clear();
        final challenge = _newChallenge();
        _challenges[challenge] = DateTime.now().add(const Duration(seconds: 20));
        request.response.write(jsonEncode({'challenge': challenge}));
      } else if (request.uri.path == '/v2/status') {
        final nonce = request.headers.value('X-Challenge') ?? '';
        final proof = request.headers.value('X-Proof') ?? '';
        final expires = _challenges.remove(nonce);
        final expected = _proof(code, nonce);
        // Compare all characters, avoid early exit when lengths match.
        var diff = proof.length ^ expected.length;
        for (var i = 0; i < expected.length; i++) {
          diff |= expected.codeUnitAt(i) ^ (i < proof.length ? proof.codeUnitAt(i) : 0);
        }
        final accepted = expires != null && DateTime.now().isBefore(expires) && diff == 0;
        request.response.statusCode = accepted ? HttpStatus.ok : HttpStatus.unauthorized;
        request.response.write(jsonEncode(accepted
            ? {'name': Platform.localHostname, 'version': 2, 'online': true, 'mode': 'local'}
            : {'error':'Code incorrect'}));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(jsonEncode({'error':'Route inconnue'}));
      }
      await request.response.close();
    });
  }

  Future<void> stopHost() async {
    await _server?.close(force: true);
    _server = null;
    _challenges.clear();
  }

  static Future<String> checkHost(String ip, String code) async {
    if (!isPrivateIPv4(ip)) throw const FormatException('Saisir une IP locale du PC (192.168.x.x, 10.x.x.x)');
    if (code.trim().isEmpty) throw const FormatException('Saisir le code du PC');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final first = await client.get(ip.trim(), port, '/v2/challenge').timeout(const Duration(seconds: 5));
      final firstResponse = await first.close().timeout(const Duration(seconds: 5));
      if (firstResponse.statusCode != 200) throw const HttpException('PC indisponible');
      final firstBody = await utf8.decoder.bind(firstResponse).join().timeout(const Duration(seconds: 5));
      final challenge = (jsonDecode(firstBody) as Map<String, dynamic>)['challenge'] as String;
      final request = await client.get(ip.trim(), port, '/v2/status').timeout(const Duration(seconds: 5));
      request.headers.set('X-Challenge', challenge);
      request.headers.set('X-Proof', _proof(code, challenge));
      final response = await request.close().timeout(const Duration(seconds: 5));
      final body = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) throw const HttpException('Code incorrect ou acces refuse');
      final data = jsonDecode(body) as Map<String, dynamic>;
      if (data['online'] != true) throw const HttpException('Reponse inattendue');
      return (data['name'] as String?) ?? 'PC Windows';
    } finally {
      client.close(force: true);
    }
  }
}
