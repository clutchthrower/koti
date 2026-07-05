import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../theme/hemma_theme.dart';
import '../../theme/tokens.dart';

/// Physical-screen settings for an always-mounted tablet: brightness,
/// light/dark mode, and an idle screensaver timeout.
class DisplaySettingsPage extends StatefulWidget {
  const DisplaySettingsPage({super.key});

  @override
  State<DisplaySettingsPage> createState() => _DisplaySettingsPageState();
}

class _DisplaySettingsPageState extends State<DisplaySettingsPage> {
  double? _brightness;
  String? _brightnessError;

  @override
  void initState() {
    super.initState();
    _loadBrightness();
  }

  Future<void> _loadBrightness() async {
    try {
      final current = await ScreenBrightness().application;
      if (mounted) setState(() => _brightness = current);
    } catch (e) {
      if (mounted) setState(() => _brightnessError = 'Brightness control unavailable on this device');
    }
  }

  Future<void> _setBrightness(double value) async {
    setState(() => _brightness = value);
    try {
      await ScreenBrightness().setApplicationScreenBrightness(value);
    } catch (_) {
      // Some emulators/devices reject programmatic brightness changes.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    const timeoutOptions = [0, 5, 10, 15, 30, 60];

    return Scaffold(
      appBar: AppBar(title: const Text('Display')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Color Mode', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SegmentedButton<ColorModePref>(
            segments: const [
              ButtonSegment(value: ColorModePref.system, label: Text('System')),
              ButtonSegment(value: ColorModePref.light, label: Text('Light')),
              ButtonSegment(value: ColorModePref.dark, label: Text('Dark')),
            ],
            selected: {theme.colorMode},
            onSelectionChanged: (s) => theme.setColorMode(s.first),
          ),
          const SizedBox(height: 24),
          const Text('Brightness', style: TextStyle(fontWeight: FontWeight.bold)),
          if (_brightnessError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_brightnessError!, style: TextStyle(color: Theme.of(context).hintColor)),
            )
          else
            Row(
              children: [
                const Icon(Icons.brightness_low),
                Expanded(
                  child: Slider(
                    value: _brightness ?? 0.5,
                    onChanged: _brightness == null ? null : _setBrightness,
                  ),
                ),
                const Icon(Icons.brightness_high),
              ],
            ),
          const SizedBox(height: 24),
          const Text('Screensaver', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Shows a dimmed clock after this many minutes without a touch.',
            style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
          ),
          const SizedBox(height: 8),
          DropdownButton<int>(
            value: timeoutOptions.contains(theme.screensaverTimeoutMinutes)
                ? theme.screensaverTimeoutMinutes
                : 0,
            items: timeoutOptions
                .map((m) => DropdownMenuItem(
                      value: m,
                      child: Text(m == 0 ? 'Off' : '$m minutes'),
                    ))
                .toList(),
            onChanged: (v) => theme.setScreensaverTimeoutMinutes(v ?? 0),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show clock'),
            value: theme.screensaverShowClock,
            onChanged: theme.setScreensaverShowClock,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show weather'),
            value: theme.screensaverShowWeather,
            onChanged: theme.setScreensaverShowWeather,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Motion'),
            subtitle: const Text('Keeps moving to prevent screen burn-in'),
            trailing: DropdownButton<ScreensaverMotion>(
              value: theme.screensaverMotion,
              items: const [
                DropdownMenuItem(
                    value: ScreensaverMotion.hop, child: Text('Hop every minute')),
                DropdownMenuItem(
                    value: ScreensaverMotion.bounce, child: Text('DVD bounce')),
              ],
              onChanged: (v) =>
                  theme.setScreensaverMotion(v ?? ScreensaverMotion.hop),
            ),
          ),
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Fullscreen'),
            subtitle: const Text(
                'Hide Android\'s status and navigation bars. Swipe from a screen edge to peek at them.'),
            value: theme.fullscreenEnabled,
            onChanged: theme.setFullscreenEnabled,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Keep screen awake'),
            subtitle: const Text(
                'Stops the display from ever sleeping, even when Android\'s screen timeout is capped (e.g. 15 minutes). Use the screensaver for burn-in protection.'),
            value: theme.keepScreenOnEnabled,
            onChanged: theme.setKeepScreenOnEnabled,
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.home_outlined),
            title: const Text('Use as Home Screen App'),
            subtitle: const Text(
                'Opens Android\'s home-app picker — choose Koti to make the tablet boot straight into the dashboard. Pick your old launcher there to undo.'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => const MethodChannel('hemma/native')
                .invokeMethod('openHomeSettings'),
          ),
        ],
      ),
    );
  }
}
