import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'remote_link.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PcDistanceApp());
}

const darkBg = Color(0xFF090F1F);
const panel = Color(0xFF151F36);
const cyan = Color(0xFF5FE9DF);
const violet = Color(0xFF9885FF);

class PcDistanceApp extends StatelessWidget {
  const PcDistanceApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Controle PC Distance',
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
          scaffoldBackgroundColor: darkBg,
          colorScheme: ColorScheme.fromSeed(seedColor: cyan, brightness: Brightness.dark),
          inputDecorationTheme: InputDecorationTheme(
            filled: true, fillColor: const Color(0xFF111A2D),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16))),
        home: const HomeScreen(),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final link = RemoteLink();
  final ip = TextEditingController();
  final code = TextEditingController();
  String info = 'Aucune connexion active';
  String hostIp = '';
  HostStatus? lastCheck;
  DateTime? lastFailure;
  bool busy = false;
  bool connected = false;
  int tab = 0;
  final bool windows = Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    ip.text = p.getString('pc_ip') ?? '';
    code.text = p.getString('pairing_code') ?? '';
    if (windows) {
      final list = await RemoteLink.localAddresses();
      hostIp = list.isNotEmpty ? list.first : '';
      if (code.text.length < 16) {
        code.text = RemoteLink.createPairingCode();
        await p.setString('pairing_code', code.text);
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('pc_ip', ip.text.trim());
    await p.setString('pairing_code', code.text.trim());
  }

  Future<void> _connect() async {
    setState(() { busy = true; info = 'Verification du PC…'; });
    try {
      final status = await RemoteLink.checkHostDetails(ip.text.trim(), code.text);
      await _persist();
      if (mounted) setState(() { connected = true; lastCheck = status; lastFailure = null; info = '${status.name} · Liaison verifiee en ${status.latencyMs} ms'; });
    } catch (e) {
      if (mounted) setState(() { connected = false; lastFailure = DateTime.now(); info = 'Connexion impossible : $e'; });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _hostToggle() async {
    setState(() => busy = true);
    try {
      if (link.isServing) {
        await link.stopHost();
        info = 'Serveur arrete';
      } else {
        await link.startHost(code.text);
        await _persist();
        info = 'PC joignable sur $hostIp:${RemoteLink.port}';
      }
    } catch (e) {
      info = 'Demarrage impossible : $e';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    link.stopHost();
    ip.dispose();
    code.dispose();
    super.dispose();
  }

  Widget _surface(Widget child, {Color? color}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: color ?? panel, borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white.withValues(alpha: 0.07))),
    child: child,
  );

  Widget _tag(String text, IconData icon, Color color) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 11),
    decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(30)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 15, color: color), const SizedBox(width: 7),
      Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700))]),
  );

  Widget _header() => Row(children: [
    Container(width: 52, height: 52, padding: const EdgeInsets.all(7), decoration: BoxDecoration(
      color: const Color(0xFF1E304B), borderRadius: BorderRadius.circular(16)),
      child: Image.asset('branding/logo.png')),
    const SizedBox(width: 14),
    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('CONTROLE PC', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.4, fontSize: 19)),
      Text('DISTANCE  /  V3', style: TextStyle(color: cyan, letterSpacing: 2.3, fontSize: 10, fontWeight: FontWeight.w700)),
    ])),
    _tag(windows ? 'WINDOWS' : 'ANDROID', windows ? Icons.desktop_windows : Icons.phone_android, cyan),
  ]);

  Widget _hero() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(25),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), gradient: const LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFF273B63), Color(0xFF192540), Color(0xFF191C37)]),
      border: Border.all(color: cyan.withValues(alpha: .22))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Icon(Icons.cast_connected, color: cyan, size: 39), const Spacer(),
        _tag(windows ? (link.isServing ? 'SERVEUR ACTIF' : 'SERVEUR INACTIF') : (connected ? 'CONNECTE' : 'HORS LIGNE'),
          connected || link.isServing ? Icons.check_circle : Icons.circle_outlined, connected || link.isServing ? cyan : Colors.white70)]),
      const SizedBox(height: 22),
      Text(windows ? 'Votre PC, pret a etre rejoint.' : 'Votre PC. Partout avec vous.',
        style: const TextStyle(fontSize: 26, height: 1.12, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      const Text('V3 : diagnostic de liaison locale et mesure de latence. Acces Internet, bureau distant et carte Tuya restent a developper.',
        style: TextStyle(color: Color(0xFFB9C4DA), height: 1.5)),
    ]));

  Widget _field(TextEditingController controller, String label, String hint, {bool secret = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(controller: controller, obscureText: secret, autocorrect: false, enableSuggestions: false,
      style: const TextStyle(fontSize: 15), decoration: InputDecoration(labelText: label, hintText: hint)));

  Widget _connectionPanel() => _surface(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(windows ? 'SERVEUR LOCAL DU PC' : 'CONNECTER MON PC', style: const TextStyle(fontSize: 14, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: cyan)),
    const SizedBox(height: 16),
    if (windows) ...[
      const Text('Adresse locale de cet ordinateur', style: TextStyle(color: Colors.white70)),
      const SizedBox(height: 8),
      SelectableText(hostIp.isEmpty ? 'Aucune adresse reseau prive detectee' : hostIp,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 17),
      Row(children: [const Expanded(child: Text('Code a saisir sur Android', style: TextStyle(color: Colors.white70))),
        IconButton(tooltip: 'Copier le code', onPressed: () => Clipboard.setData(ClipboardData(text: code.text)), icon: const Icon(Icons.copy, color: cyan))]),
      SelectableText(code.text, style: const TextStyle(letterSpacing: 2, fontSize: 19, fontWeight: FontWeight.w700)),
      const SizedBox(height: 17),
      OutlinedButton.icon(onPressed: hostIp.isEmpty ? null : () => Clipboard.setData(ClipboardData(text: hostIp)), icon: const Icon(Icons.copy), label: const Text('Copier l’adresse IP')),
    ] else ...[
      _field(ip, 'IP locale du PC', 'Ex. 192.168.1.20'),
      _field(code, 'Code de jumelage du PC', '20 caracteres'),
    ],
    SizedBox(width: double.infinity, child: FilledButton.icon(
      onPressed: busy || (windows && hostIp.isEmpty) ? null : (windows ? _hostToggle : _connect),
      icon: Icon(windows ? (link.isServing ? Icons.stop_circle_outlined : Icons.power_settings_new) : Icons.link),
      label: Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(
        windows ? (link.isServing ? 'Arreter le serveur' : 'Activer le serveur') : (busy ? 'Connexion en cours…' : 'Tester la connexion'))),
      style: FilledButton.styleFrom(backgroundColor: cyan, foregroundColor: darkBg))),
    const SizedBox(height: 15),
    Text(info, style: TextStyle(fontSize: 13, color: connected || link.isServing ? cyan : Colors.white70)),
    if (!windows && lastCheck != null) ...[
      const SizedBox(height: 16),
      _diagnostic(),
    ],
  ]));

  Widget _diagnostic() {
    final status = lastCheck!;
    final ms = status.latencyMs;
    final quality = ms < 80 ? 'Rapide' : (ms < 200 ? 'Moyenne' : 'Lente');
    final clock = status.checkedAt;
    final hour = '${clock.hour.toString().padLeft(2, '0')}:${clock.minute.toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF0B2C35), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('DIAGNOSTIC DE LIAISON', style: TextStyle(color: cyan, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('PC : ${status.name}'),
        Text('Temps de reponse : $ms ms ($quality)'),
        Text('Dernier test : $hour'),
        const SizedBox(height: 6),
        const Text('Ce test ne mesure pas encore la fluidite de la video.', style: TextStyle(fontSize: 12, color: Colors.white60)),
      ]),
    );
  }

  Widget _module(IconData icon, String title, String detail, Color color) => _surface(
    Row(children: [Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(
      color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: color)),
      const SizedBox(width: 15), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 4), Text(detail, style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ])), const Icon(Icons.lock_clock_outlined, color: Colors.white38, size: 20)]));

  Widget _page() {
    if (tab == 0) return Column(children: [
      _hero(), const SizedBox(height: 18), _connectionPanel(), const SizedBox(height: 18),
      _module(Icons.desktop_windows, 'Bureau distant', 'Streaming et commandes : en developpement', violet),
      const SizedBox(height: 12),
      _module(Icons.folder_copy_outlined, 'Fichiers & telechargements', 'Envoi, reception et suivi : prochaine etape', cyan),
      const SizedBox(height: 12),
      _module(Icons.power_settings_new, 'Alimentation PC', 'Carte Tuya A3 : integration apres verification', const Color(0xFFFFC17D)),
    ]);
    if (tab == 1) return Column(children: [
      _surface(const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('BUREAU DISTANT', style: TextStyle(color: cyan, fontWeight: FontWeight.w800)),
        SizedBox(height: 13), Text('La V3 ajoute un diagnostic de connexion (nom du PC, latence du test). Le partage d’ecran, le clavier et la souris ne sont pas encore disponibles.'),
      ]))]);
    if (tab == 2) return Column(children: [
      _surface(const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('FICHIERS & TELECHARGEMENTS', style: TextStyle(color: cyan, fontWeight: FontWeight.w800)),
        SizedBox(height: 13), Text('Les transferts et les telechargements distants seront ajoutes sans exposer les fichiers du PC a Internet.'),
      ]))]);
    return Column(children: [
      _surface(const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('GUIDE DE CONNEXION', style: TextStyle(color: cyan, fontWeight: FontWeight.w800)),
        SizedBox(height: 14),
        Text('1. Connectez le PC et Android au meme Wi-Fi prive.\n\n2. Sur Windows, ouvrez l’EXE, copiez l’adresse IP locale et le code, puis activez le serveur.\n\n3. Sur Android, saisissez cette adresse et ce code. Appuyez sur Tester la connexion.\n\n4. Autorisez l’application sur le pare-feu Windows pour votre reseau prive uniquement. N’ouvrez PAS de port sur la box.\n\n5. La connexion Internet et la carte Tuya A3 seront ajoutees apres verification technique.'),
        SizedBox(height: 13),
      ]))]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 780),
      child: ListView(padding: const EdgeInsets.all(22), children: [
        _header(), const SizedBox(height: 26), _page(), const SizedBox(height: 18),
        const Center(child: Text('CONTROLE PC DISTANCE   •   V3', style: TextStyle(fontSize: 10, letterSpacing: 1.8, color: Colors.white38))),
      ])))),
    bottomNavigationBar: NavigationBar(backgroundColor: const Color(0xFF10192A), height: 72,
      selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Accueil'),
        NavigationDestination(icon: Icon(Icons.desktop_windows_outlined), label: 'Bureau'),
        NavigationDestination(icon: Icon(Icons.folder_outlined), label: 'Fichiers'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Guide'),
      ]));
}
