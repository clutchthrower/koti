import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../api/ha_discovery.dart';
import 'login_screen.dart';

/// First-launch landing page. No setup chores up front: the app sits on a
/// branded screen and keeps scanning the Wi-Fi for Home Assistant on its
/// own (spec 1.5 "Auto Discovery"); found instances appear with a single
/// Connect button. Manual address entry is a fallback link at the bottom.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final List<DiscoveredInstance> _results = [];
  bool _scanning = false;
  int _attempts = 0;
  Timer? _rescanTimer;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _rescanTimer?.cancel();
    super.dispose();
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      final results = await HaDiscoveryService().scan();
      if (!mounted) return;
      setState(() {
        // Keep previously-seen instances; mDNS answers can be flaky.
        for (final r in results) {
          if (!_results.any((e) => e.url == r.url)) _results.add(r);
        }
        _attempts++;
      });
    } catch (_) {
      if (mounted) setState(() => _attempts++);
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
        // Keep looking quietly until something is found.
        if (_results.isEmpty) {
          _rescanTimer = Timer(const Duration(seconds: 6), _scan);
        }
      }
    }
  }

  void _goToLogin(String baseUrl, {String? externalUrl}) {
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) =>
              LoginScreen(baseUrl: baseUrl, externalUrl: externalUrl)),
    );
  }

  Future<void> _enterManually() async {
    final controller = TextEditingController(text: dotenv.env['HA_URL'] ?? '');
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Home Assistant Address'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'http://192.168.1.100:8123',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Connect')),
        ],
      ),
    );
    if (url != null && url.isNotEmpty) _goToLogin(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF19191F),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),
                  const Text(
                    'Koti',
                    style: TextStyle(
                      fontFamily: 'Hanken Grotesk',
                      fontWeight: FontWeight.w700,
                      fontSize: 56,
                      color: Color(0xFFEDEDF0),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Home Assistant dashboard',
                    style: TextStyle(
                      fontFamily: 'Hanken Grotesk',
                      fontSize: 16,
                      color: Colors.white38,
                    ),
                  ),
                  const SizedBox(height: 48),
                  if (_results.isEmpty) ...[
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF6EBAFF)),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _attempts == 0
                          ? 'Searching your Wi-Fi for Home Assistant…'
                          : 'Still searching… make sure the tablet is on the '
                              'same Wi-Fi as Home Assistant.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  ] else ...[
                    for (final r in _results)
                      Card(
                        color: const Color(0xFF26262E),
                        child: ListTile(
                          leading:
                              const Icon(Icons.home_outlined, color: Colors.white70),
                          title: Text(r.name,
                              style: const TextStyle(color: Colors.white)),
                          subtitle: Text(r.url,
                              style: const TextStyle(color: Colors.white54)),
                          trailing: FilledButton(
                            onPressed: () =>
                                _goToLogin(r.url, externalUrl: r.externalUrl),
                            child: const Text('Connect'),
                          ),
                        ),
                      ),
                  ],
                  const Spacer(flex: 3),
                  TextButton(
                    onPressed: _enterManually,
                    child: const Text('Enter address manually',
                        style: TextStyle(color: Colors.white38)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
