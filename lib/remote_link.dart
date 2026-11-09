import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// V2: verification locale de connexion par defi HMAC.
/// Ni streaming ni controle distant ne sont ouverts sans transport chiffre.
class HostStatus {
  final String name;
  final int latencyMs;
  final DateTime checkedAt;
  const HostStatus(this.name, this.latencyMs, this.checkedAt);
}

class RemoteLink {
  HttpServer? _server;
  bool get isServing => _server != null;
  static const int port = 47186;
  final Map<String, DateTime> _challenges = {};
  bool screenSharingEnabled = false;
  DateTime _lastScreen = DateTime.fromMillisecondsSinceEpoch(0);

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

  static const _captureScript = r'''
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
$rect = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$w = [Math]::Min(1280, $rect.Width)
$h = [Math]::Max(1, [int]($rect.Height * $w / $rect.Width))
$full = New-Object System.Drawing.Bitmap($rect.Width, $rect.Height)
$g = [System.Drawing.Graphics]::FromImage($full)
$g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $full.Size)
$g.Dispose()
$small = New-Object System.Drawing.Bitmap($full, (New-Object System.Drawing.Size($w, $h)))
$full.Dispose()
$stream = New-Object System.IO.MemoryStream
$small.Save($stream, [System.Drawing.Imaging.ImageFormat]::Jpeg)
$small.Dispose()
$bytes = $stream.ToArray()
$stream.Dispose()
[Console]::OpenStandardOutput().Write($bytes, 0, $bytes.Length)
''';

  static Future<List<int>> _windowsScreenshot() async {
    final bytes = <int>[];
    for (final unit in _captureScript.codeUnits) {
      bytes.add(unit & 255);
      bytes.add(unit >> 8);
    }
    final encoded = base64Encode(bytes);
    final result = await Process.run('powershell.exe',
        ['-NoProfile', '-NonInteractive', '-EncodedCommand', encoded],
        stdoutEncoding: null, stderrEncoding: utf8).timeout(const Duration(seconds: 8));
    if (result.exitCode != 0) throw const HttpException('Capture impossible');
    final output = result.stdout as List<int>;
    if (output.length < 100 || output.length > 3000000 || output[0] != 0xff || output[1] != 0xd8) {
      throw const HttpException('Image invalide');
    }
    return output;
  }

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
      } else if (request.uri.path == '/v2/status' || request.uri.path == '/v4/screen') {
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
        if (!accepted) {
          request.response.write(jsonEncode({'error': 'Code incorrect'}));
        } else if (request.uri.path == '/v4/screen') {
          final now = DateTime.now();
          if (!screenSharingEnabled) {
            request.response.statusCode = HttpStatus.forbidden;
            request.response.write(jsonEncode({'error': 'Activer le partage sur Windows'}));
          } else if (now.difference(_lastScreen).inMilliseconds < 1200) {
            request.response.statusCode = HttpStatus.tooManyRequests;
            request.response.write(jsonEncode({'error': 'Actualisation trop rapide'}));
          } else {
            _lastScreen = now;
            try {
              final frame = await _windowsScreenshot();
              request.response.headers.contentType = ContentType('image', 'jpeg');
              request.response.add(frame);
            } catch (_) {
              request.response.statusCode = HttpStatus.internalServerError;
              request.response.write(jsonEncode({'error': 'Capture Windows impossible'}));
            }
          }
        } else {
          request.response.write(jsonEncode({'name': Platform.localHostname, 'version': 4, 'online': true, 'mode': 'local'}));
        }
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

  static Future<List<int>> fetchScreen(String ip, String code) async {
    if (!isPrivateIPv4(ip)) throw const FormatException('IP privee requise');
    if (code.trim().length < 20) throw const FormatException('Code invalide');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final first = await client.get(ip, port, '/v2/challenge').timeout(const Duration(seconds: 5));
      final challengeResponse = await first.close().timeout(const Duration(seconds: 5));
      if (challengeResponse.statusCode != 200) throw const HttpException('PC indisponible');
      final body = await utf8.decoder.bind(challengeResponse).join().timeout(const Duration(seconds: 5));
      final challenge = (jsonDecode(body) as Map<String, dynamic>)['challenge'] as String;
      final request = await client.get(ip, port, '/v4/screen').timeout(const Duration(seconds: 5));
      request.headers.set('X-Challenge', challenge);
      request.headers.set('X-Proof', _proof(code, challenge));
      final response = await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) throw HttpException('Capture refusee (${response.statusCode})');
      final frame = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 12))) {
        frame.addAll(chunk);
        if (frame.length > 3000000) throw const HttpException('Image trop grande');
      }
      if (frame.length < 100 || frame[0] != 0xff || frame[1] != 0xd8) {
        throw const HttpException('Capture incorrecte');
      }
      return frame;
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> checkHost(String ip, String code) async =>
      (await checkHostDetails(ip, code)).name;

  static Future<HostStatus> checkHostDetails(String ip, String code) async {
    final stopwatch = Stopwatch()..start();
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
      stopwatch.stop();
      return HostStatus((data['name'] as String?) ?? 'PC Windows', stopwatch.elapsedMilliseconds, DateTime.now());
    } finally {
      client.close(force: true);
    }
  }
}
