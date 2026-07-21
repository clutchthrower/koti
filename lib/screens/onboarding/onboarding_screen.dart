import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../api/ha_discovery.dart';
import '../../theme/koti_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/koti_icon.dart';
import '../koti_splash_screen.dart';
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
      backgroundColor: KotiSplashScreen.background,
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
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Home Assistant dashboard',
                    style: TextStyle(
                      fontFamily: 'Hanken Grotesk',
                      fontSize: 16,
                      color: Color.fromRGBO(255, 255, 255, 0.7),
                    ),
                  ),
                  const SizedBox(height: 48),
                  if (_results.isEmpty) ...[
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: KotiTokens.defaultAccent),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _attempts == 0
                          ? 'Searching your Wi-Fi for Home Assistant…'
                          : 'Still searching… make sure the tablet is on the '
                              'same Wi-Fi as Home Assistant.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: KotiTokens.secondaryOnDark, fontSize: 14),
                    ),
                  ] else ...[
                    for (final r in _results)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _DiscoveredInstanceCard(
                          instance: r,
                          onConnect: () =>
                              _goToLogin(r.url, externalUrl: r.externalUrl),
                        ),
                      ),
                  ],
                  const Spacer(flex: 3),
                  TextButton(
                    onPressed: _enterManually,
                    child: const Text('Enter address manually',
                        style: TextStyle(color: Color.fromRGBO(255, 255, 255, 0.7))),
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

/// Same glass-card recipe as the dashboard's entity cards (specular
/// border, translucent dark surface, icon circle) — a discovered instance
/// reads as "one of these cards" rather than a plain settings-style list
/// row, even though it's sitting on the onboarding screen's tan ground.
class _DiscoveredInstanceCard extends StatelessWidget {
  final DiscoveredInstance instance;
  final VoidCallback onConnect;

  const _DiscoveredInstanceCard({required this.instance, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final tokens = KotiTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        gradient: tokens.borderGradient,
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tokens.cardRadius - 1),
          color: tokens.entityBackground,
        ),
        child: Row(
          children: [
            KotiIconCircle(
              iconName: 'home',
              iconColor: tokens.textPrimary,
              backgroundColor: tokens.iconCircleBackground,
              diameter: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(instance.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'Hanken Grotesk',
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: tokens.entityName)),
                  Text(instance.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: tokens.entityState)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: onConnect, child: const Text('Connect')),
          ],
        ),
      ),
    );
  }
}
