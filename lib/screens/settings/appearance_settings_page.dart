import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/koti_theme.dart';
import '../../theme/tokens.dart';

class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance & Theme')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Color Mode', style: TextStyle(fontWeight: FontWeight.bold)),
          SegmentedButton<ColorModePref>(
            segments: const [
              ButtonSegment(value: ColorModePref.system, label: Text('System')),
              ButtonSegment(value: ColorModePref.light, label: Text('Light')),
              ButtonSegment(value: ColorModePref.dark, label: Text('Dark')),
            ],
            selected: {theme.colorMode},
            onSelectionChanged: (s) => theme.setColorMode(s.first),
          ),
          const SizedBox(height: 16),
          Text('Card Transparency: ${(theme.cardTransparency * 100).round()}%'),
          Slider(
            value: theme.cardTransparency,
            onChanged: theme.setCardTransparency,
          ),
          const SizedBox(height: 8),
          Text('Animation Speed: ${theme.animationSpeed.toStringAsFixed(1)}x'),
          Slider(
            value: theme.animationSpeed,
            min: 0.5,
            max: 2.0,
            divisions: 6,
            onChanged: theme.setAnimationSpeed,
          ),
          SwitchListTile(
            title: const Text('Entrance Animations'),
            value: theme.entranceAnimationsEnabled,
            onChanged: theme.setEntranceAnimationsEnabled,
          ),
          SwitchListTile(
            title: const Text('Smart Row Sorting'),
            value: theme.smartRowSortingEnabled,
            onChanged: theme.setSmartRowSortingEnabled,
          ),
          SwitchListTile(
            title: const Text('Parallax Background Effect'),
            value: theme.parallaxEnabled,
            onChanged: theme.setParallaxEnabled,
          ),
        ],
      ),
    );
  }
}
