import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Animated splash: a single-line house-drawing animation (a Trim Path
/// reveal baked into assets/animations/koti_house_intro.json — sourced
/// from LottieFiles, recolored at runtime) plays draw → hold → erase →
/// repeat, doubling as a loading indicator for as long as the app is
/// still connecting. The "KOTI" wordmark is static — it fades in once the
/// house finishes its first build and then stays put. The moment the app
/// is ready, the house is allowed to finish its current redraw and settle
/// before the dashboard takes over — same behavior this screen always
/// had, just with a richer hand-drawn asset instead of the simple
/// custom-painted house silhouette it replaces.
class KotiSplashScreen extends StatefulWidget {
  /// Whether the app behind the splash is ready to be shown.
  final bool ready;
  final VoidCallback onFinished;

  const KotiSplashScreen({
    super.key,
    required this.ready,
    required this.onFinished,
  });

  // A dark neutral already used elsewhere in the app (main.dart's dark
  // onSurface) rather than the old warm tan — the rest of the app's
  // "glass" look is a translucent surface over a photo, but a splash has
  // nothing behind it to show through, so this is just that same family
  // of dark tone as a plain solid instead.
  static const background = Color(0xFF1A1A1A);
  static const _strokeColor = Colors.white;

  @override
  State<KotiSplashScreen> createState() => _KotiSplashScreenState();
}

enum _Phase { intro, looping, finishing }

class _KotiSplashScreenState extends State<KotiSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  // Drives the Lottie widget itself: its value (0..1, a fraction of the
  // composition's own frame range) is set imperatively from _intro/_loop
  // below rather than animated directly — the same draw/hold/erase timing
  // this screen always used for its hand-painted reveal now drives the
  // Lottie asset instead. Its own duration is irrelevant since nothing
  // ever calls forward()/repeat() on it.
  late final AnimationController _lottieController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  _Phase _phase = _Phase.intro;
  bool _titleVisible = false;

  @override
  void initState() {
    super.initState();
    _intro.addListener(
        () => _lottieController.value = Curves.easeInOut.transform(_intro.value));
    _intro.addStatusListener((status) {
      if (status == AnimationStatus.completed) _onIntroComplete();
    });
    _loop.addListener(_onLoopTick);
    // Deferred to the next frame rather than started synchronously here:
    // this is the very first animation of a cold app launch, and the gap
    // between engine startup and the first real frame can otherwise get
    // absorbed into the controller's first tick, making the house-draw
    // appear to jump straight to "done" instead of animating.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _intro.forward();
    });
  }

  void _onIntroComplete() {
    // Always play the redraw loop at least once, even if the app was
    // already ready before the intro finished — on a fast connection the
    // splash would otherwise flash past with no loop at all.
    setState(() {
      _titleVisible = true;
      _phase = _Phase.looping;
    });
    _loop.repeat();
  }

  int _loopsCompleted = 0;
  double _lastLoopValue = 0;

  /// Only settle once the house is fully (re)drawn and briefly held — never
  /// cut the redraw off mid-erase — and only after at least one full loop.
  void _onLoopTick() {
    if (_phase != _Phase.looping) return;
    final v = _loop.value;
    if (v < _lastLoopValue) _loopsCompleted++;
    _lastLoopValue = v;
    _lottieController.value = _loopCycle(v);

    if (_loopsCompleted >= 1 && widget.ready && v >= 0.45 && v < 0.70) {
      _loop.stop();
      _finish();
    }
  }

  void _finish() {
    setState(() => _phase = _Phase.finishing);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    _lottieController.dispose();
    super.dispose();
  }

  /// Draw 0→1, hold at 1, erase 1→0, then the loop repeats — the house
  /// redrawing itself doubles as the loading cue. A generous hold plateau
  /// (0.45-0.70, wider than the original hand-painted version's) so the
  /// finished house is actually appreciable rather than a blink.
  double _loopCycle(double v) {
    if (v < 0.45) return Curves.easeInOut.transform(v / 0.45);
    if (v < 0.70) return 1.0;
    return 1.0 - Curves.easeIn.transform((v - 0.70) / 0.30);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KotiSplashScreen.background,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Tap fast-forwards the one-time build; the redraw loop itself is
        // a genuine "still connecting" state and isn't skippable.
        onTap: () {
          if (_phase == _Phase.intro && _intro.isAnimating) {
            _intro.value = 1.0;
          }
        },
        child: Stack(
          children: [
            SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Builder(builder: (context) {
                    // Explicit width AND height (a square, matching the
                    // composition's own 1000x1000 canvas) rather than
                    // width-only — leaving height to intrinsic sizing
                    // was producing an off-center result. Same
                    // shortestSide-based sizing convention the original
                    // custom-painted house used — safe on both portrait
                    // and landscape wall tablets.
                    final houseSize = MediaQuery.sizeOf(context).shortestSide * 0.85;
                    // Wrapped the same way as the title below: an
                    // explicit full-width SizedBox + Center, rather than
                    // leaving this as the Column's widest child. Column
                    // sizes its own cross-axis to fit its widest child
                    // under loose constraints — with only this box in
                    // play that widest child was the house itself, so its
                    // measured position drifted depending on what the
                    // title's own wrapper did to the Column's resolved
                    // width. Both children now independently claim full
                    // width and center their own fixed-size content within
                    // it, decoupling them from each other entirely.
                    return SizedBox(
                      width: double.infinity,
                      child: Center(
                        child: RepaintBoundary(
                          child: SizedBox(
                            width: houseSize,
                            height: houseSize,
                            child: Lottie.asset(
                              'assets/animations/koti_house_intro.json',
                              controller: _lottieController,
                              fit: BoxFit.contain,
                              alignment: Alignment.center,
                              onLoaded: (composition) {
                                _lottieController.duration = composition.duration;
                              },
                              delegates: LottieDelegates(
                                values: [
                                  ValueDelegate.strokeColor(
                                    const ['**'],
                                    value: KotiSplashScreen._strokeColor,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  // Explicit full-width + Center rather than relying on
                  // the Column's own cross-axis centering — measured live
                  // on-device that the Text (with its manual spaces +
                  // letterSpacing combination) was landing ~55px left of
                  // true center under plain crossAxisAlignment.center, far
                  // more than a letterSpacing trailing-space effect could
                  // explain. This sidesteps whatever's actually causing
                  // that rather than chasing a magic-number offset.
                  SizedBox(
                    width: double.infinity,
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _titleVisible ? 1 : 0,
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOut,
                        child: const Text(
                          'K O T I',
                          style: TextStyle(
                            fontFamily: 'Hanken Grotesk',
                            fontWeight: FontWeight.w700,
                            fontSize: 22,
                            letterSpacing: 8,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 48,
              child: AnimatedOpacity(
                opacity: _phase == _Phase.looping && !widget.ready ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                child: const Text(
                  'Connecting to Home Assistant…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Hanken Grotesk',
                    fontSize: 14,
                    color: Color.fromRGBO(255, 255, 255, 0.85),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
