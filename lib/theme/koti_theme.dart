import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tokens.dart';

/// How the screensaver content moves to protect the panel from burn-in.
enum ScreensaverMotion {
  /// Glides to a new random spot once a minute.
  hop,

  /// Drifts continuously, bouncing off the screen edges (the DVD logo).
  bounce,
}

/// Owns theme preferences (variant, color mode, accent, blur/transparency
/// sliders) and derives the active [KotiTokens]. Persisted to
/// SharedPreferences so choices survive app restarts.
class ThemeController extends ChangeNotifier {
  ColorModePref colorMode = ColorModePref.system;
  final Color accentColor = KotiTokens.defaultAccent;
  double cardTransparency = 1.0;
  double animationSpeed = 1.0;
  bool entranceAnimationsEnabled = true;
  bool smartRowSortingEnabled = true;
  bool parallaxEnabled = true;

  /// Minutes of no touch before the screensaver shows; 0 disables it.
  int screensaverTimeoutMinutes = 0;

  /// Hide Android's status/navigation bars (wall-dashboard look).
  bool fullscreenEnabled = true;

  /// Hold Android's FLAG_KEEP_SCREEN_ON so the display never sleeps —
  /// needed on devices whose system screen timeout maxes out at 15
  /// minutes. The screensaver (not the OS) protects the panel instead.
  bool keepScreenOnEnabled = true;

  /// What the screensaver shows and how it moves (motion is always on —
  /// a static image would burn into an always-on panel).
  bool screensaverShowClock = true;
  bool screensaverShowWeather = true;
  ScreensaverMotion screensaverMotion = ScreensaverMotion.hop;

  static const _kColorMode = 'koti_theme_color_mode';
  static const _kTransparency = 'koti_theme_transparency';
  static const _kAnimSpeed = 'koti_theme_anim_speed';
  static const _kEntranceAnim = 'koti_theme_entrance_anim';
  static const _kSmartRow = 'koti_theme_smart_row';
  static const _kParallax = 'koti_theme_parallax';
  static const _kScreensaver = 'koti_theme_screensaver_minutes';
  static const _kFullscreen = 'koti_theme_fullscreen';
  static const _kKeepScreenOn = 'koti_theme_keep_screen_on';
  static const _kSaverClock = 'koti_theme_saver_clock';
  static const _kSaverWeather = 'koti_theme_saver_weather';
  static const _kSaverMotion = 'koti_theme_saver_motion';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    colorMode = ColorModePref.values.firstWhere(
      (v) => v.name == prefs.getString(_kColorMode),
      orElse: () => ColorModePref.system,
    );
    cardTransparency = prefs.getDouble(_kTransparency) ?? 1.0;
    animationSpeed = prefs.getDouble(_kAnimSpeed) ?? 1.0;
    entranceAnimationsEnabled = prefs.getBool(_kEntranceAnim) ?? true;
    smartRowSortingEnabled = prefs.getBool(_kSmartRow) ?? true;
    parallaxEnabled = prefs.getBool(_kParallax) ?? true;
    screensaverTimeoutMinutes = prefs.getInt(_kScreensaver) ?? 0;
    fullscreenEnabled = prefs.getBool(_kFullscreen) ?? true;
    keepScreenOnEnabled = prefs.getBool(_kKeepScreenOn) ?? true;
    _applyKeepScreenOn();
    screensaverShowClock = prefs.getBool(_kSaverClock) ?? true;
    screensaverShowWeather = prefs.getBool(_kSaverWeather) ?? true;
    screensaverMotion = ScreensaverMotion.values.firstWhere(
      (m) => m.name == prefs.getString(_kSaverMotion),
      orElse: () => ScreensaverMotion.hop,
    );
    _applyFullscreen();
    notifyListeners();
  }

  void _applyFullscreen() {
    SystemChrome.setEnabledSystemUIMode(
      fullscreenEnabled ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    // immersiveSticky alone isn't sticky enough in practice: the keyboard,
    // system dialogs, or a resume can bring the bars back for good on some
    // devices (seen on the LG wall tablet). Whenever Android reports the
    // bars became visible, quietly hide them again a few seconds later.
    SystemChrome.setSystemUIChangeCallback(!fullscreenEnabled
        ? null
        : (visible) async {
            if (!visible) return;
            await Future.delayed(const Duration(seconds: 3));
            if (fullscreenEnabled) {
              await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
            }
          });
  }

  /// Re-hides the system bars if fullscreen is on — called on app resume.
  void reassertFullscreen() {
    if (fullscreenEnabled) _applyFullscreen();
  }

  void _applyKeepScreenOn() {
    // No-op off Android (tests, desktop): the channel simply isn't there.
    const MethodChannel('koti/native')
        .invokeMethod('setKeepScreenOn', {'on': keepScreenOnEnabled})
        .catchError((_) => null);
  }

  void setKeepScreenOnEnabled(bool v) {
    keepScreenOnEnabled = v;
    _applyKeepScreenOn();
    notifyListeners();
    _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kColorMode, colorMode.name);
    await prefs.setDouble(_kTransparency, cardTransparency);
    await prefs.setDouble(_kAnimSpeed, animationSpeed);
    await prefs.setBool(_kEntranceAnim, entranceAnimationsEnabled);
    await prefs.setBool(_kSmartRow, smartRowSortingEnabled);
    await prefs.setBool(_kParallax, parallaxEnabled);
    await prefs.setInt(_kScreensaver, screensaverTimeoutMinutes);
    await prefs.setBool(_kFullscreen, fullscreenEnabled);
    await prefs.setBool(_kKeepScreenOn, keepScreenOnEnabled);
    await prefs.setBool(_kSaverClock, screensaverShowClock);
    await prefs.setBool(_kSaverWeather, screensaverShowWeather);
    await prefs.setString(_kSaverMotion, screensaverMotion.name);
  }

  void setColorMode(ColorModePref v) {
    colorMode = v;
    notifyListeners();
    _save();
  }

  void setCardTransparency(double v) {
    cardTransparency = v;
    notifyListeners();
    _save();
  }

  void setAnimationSpeed(double v) {
    animationSpeed = v;
    notifyListeners();
    _save();
  }

  void setEntranceAnimationsEnabled(bool v) {
    entranceAnimationsEnabled = v;
    notifyListeners();
    _save();
  }

  void setSmartRowSortingEnabled(bool v) {
    smartRowSortingEnabled = v;
    notifyListeners();
    _save();
  }

  void setParallaxEnabled(bool v) {
    parallaxEnabled = v;
    notifyListeners();
    _save();
  }

  void setScreensaverTimeoutMinutes(int v) {
    screensaverTimeoutMinutes = v;
    notifyListeners();
    _save();
  }

  void setFullscreenEnabled(bool v) {
    fullscreenEnabled = v;
    _applyFullscreen();
    notifyListeners();
    _save();
  }

  void setScreensaverShowClock(bool v) {
    screensaverShowClock = v;
    notifyListeners();
    _save();
  }

  void setScreensaverShowWeather(bool v) {
    screensaverShowWeather = v;
    notifyListeners();
    _save();
  }

  void setScreensaverMotion(ScreensaverMotion v) {
    screensaverMotion = v;
    notifyListeners();
    _save();
  }

  KotiTokens tokensFor(BuildContext context) {
    final systemBrightness = MediaQuery.platformBrightnessOf(context);
    final brightness = switch (colorMode) {
      ColorModePref.system => systemBrightness,
      ColorModePref.light => Brightness.light,
      ColorModePref.dark => Brightness.dark,
    };
    return KotiTokens(
      brightness: brightness,
      accentColor: accentColor,
      cardTransparency: cardTransparency,
    );
  }
}

/// Makes the resolved [KotiTokens] available to the widget tree without
/// forcing a full-tree rebuild on every theme tweak — widgets that only
/// need tokens can read via [KotiTheme.of].
class KotiTheme extends InheritedWidget {
  final KotiTokens tokens;

  const KotiTheme({super.key, required this.tokens, required super.child});

  static KotiTokens of(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<KotiTheme>();
    assert(widget != null, 'No KotiTheme found in context');
    return widget!.tokens;
  }

  @override
  bool updateShouldNotify(KotiTheme oldWidget) => oldWidget.tokens != tokens;
}
