import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import '../../api/ha_auth_flow.dart';
import '../../api/ha_registry.dart';
import '../../store/settings_store.dart';

/// Step 2 of onboarding: turn the chosen HA URL into a stored access token,
/// either via username/password (HA's own login flow, no WebView — see
/// [HaAuthFlow]) or by pasting an existing Long-Lived Access Token.
class LoginScreen extends StatefulWidget {
  final String baseUrl;

  /// The instance's advertised public URL (from discovery), saved as the
  /// optional Remote URL — never used as the local connection.
  final String? externalUrl;

  const LoginScreen({super.key, required this.baseUrl, this.externalUrl});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _signInWithPassword() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final flow = HaAuthFlow(widget.baseUrl);
      var step = await flow.startLoginFlow();
      step = await flow.submitCredentials(
        flowId: step.flowId,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
      if (!step.isComplete || step.result == null) {
        throw HaAuthFlowException('Sign-in did not complete — check your credentials');
      }
      final token = await flow.completeWithLongLivedToken(
        authorizationCode: step.result!,
        clientName: 'Koti',
      );
      await _saveAndFinish(token);
    } catch (e) {
      setState(() => _error = e is HaAuthFlowException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectWithToken() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Paste a Long-Lived Access Token first');
      return;
    }
    await _saveAndFinish(token);
  }

  Future<void> _saveAndFinish(String token) async {
    final settings = Provider.of<SettingsStore>(context, listen: false);
    await settings.setConnection(
      localUrl: widget.baseUrl,
      remoteUrl: widget.externalUrl,
      accessToken: token,
    );

    setState(() => _busy = true);
    var message = 'Connected.';
    try {
      final result =
          await RoomAutoProvisioner(baseUrl: widget.baseUrl, accessToken: token).provision();
      if (result.weatherEntityId != null) {
        await settings.setWeatherEntityId(result.weatherEntityId);
      }
      if (result.rooms.isNotEmpty) {
        await settings.setRooms(result.rooms);
        message = 'Connected — set up ${result.rooms.length} room'
            '${result.rooms.length == 1 ? '' : 's'} automatically from your '
            'Home Assistant areas.';
      } else if (!result.adminAccess) {
        message = 'Connected. This account can\'t read Areas, so rooms '
            'weren\'t auto-created — add them in Settings → Rooms.';
      } else {
        message = 'Connected. No Areas were found in Home Assistant, so add '
            'rooms in Settings → Rooms.';
      }
    } catch (e) {
      message = 'Connected, but room auto-setup failed ($e) — add rooms in '
          'Settings → Rooms.';
    }

    if (!mounted) return;
    setState(() => _busy = false);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Koti'),
        content: Text(message),
        actions: [
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
        ],
      ),
    );
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sign in to ${widget.baseUrl}')),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Username & Password'),
              Tab(text: 'Access Token'),
            ],
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              color: Colors.red.withValues(alpha: 0.1),
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _PasswordTab(
                  usernameController: _usernameController,
                  passwordController: _passwordController,
                  busy: _busy,
                  onSubmit: _signInWithPassword,
                ),
                _TokenTab(
                  tokenController: _tokenController,
                  onSubmit: _connectWithToken,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordTab extends StatelessWidget {
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool busy;
  final VoidCallback onSubmit;

  const _PasswordTab({
    required this.usernameController,
    required this.passwordController,
    required this.busy,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Signs in the same way as the Home Assistant web frontend, then '
          'creates a Long-Lived Access Token this app stores for you — no '
          'browser or manual token copy-paste required.',
          style: TextStyle(color: Theme.of(context).hintColor),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: usernameController,
          decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : onSubmit,
          child: Text(busy ? 'Signing in…' : 'Sign In'),
        ),
      ],
    );
  }
}

class _TokenTab extends StatelessWidget {
  final TextEditingController tokenController;
  final VoidCallback onSubmit;

  const _TokenTab({required this.tokenController, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    final devToken = dotenv.env['HA_ACCESS_TOKEN'];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Paste a Long-Lived Access Token created from your Home Assistant '
          'profile page (Settings → your profile → Security tab).',
          style: TextStyle(color: Theme.of(context).hintColor),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: tokenController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Long-Lived Access Token',
            border: OutlineInputBorder(),
          ),
        ),
        if (devToken != null && devToken.isNotEmpty) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.bolt_outlined),
            label: const Text('Fill from local .env (dev only)'),
            onPressed: () => tokenController.text = devToken,
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(onPressed: onSubmit, child: const Text('Connect')),
      ],
    );
  }
}
