import 'package:flutter/material.dart';

/// Animated splash: a line-art house draws itself like a thick, rounded
/// brush stroke. The "KOTI" wordmark is static — it fades in once the
/// house finishes its first build and then stays put. The house itself
/// keeps redrawing — draw, hold, erase, repeat — as a loading indicator
/// in its own right, for as long as the app is still connecting. The
/// moment it's ready, the house is allowed to finish its current redraw
/// and settle before the dashboard takes over.
///
/// Single painter, plain [Path]/[PathMetric] reveals, no third-party
/// packages — cheap enough for the old wall tablet.
class KotiSplashScreen extends StatefulWidget {
  /// Whether the app behind the splash is ready to be shown.
  final bool ready;
  final VoidCallback onFinished;

  const KotiSplashScreen({
    super.key,
    required this.ready,
    required this.onFinished,
  });

  static const background = Color(0xFFB8A18F);

  @override
  State<KotiSplashScreen> createState() => _KotiSplashScreenState();
}

enum _Phase { intro, looping, finishing }

class _KotiSplashScreenState extends State<KotiSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  _Phase _phase = _Phase.intro;
  bool _titleVisible = false;

  @override
  void initState() {
    super.initState();
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
    // splash would otherwise flash past in ~1.5s with no loop at all.
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

    if (_loopsCompleted >= 1 && widget.ready && v >= 0.55 && v < 0.68) {
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
    super.dispose();
  }

  /// Draw 0→1, hold at 1, erase 1→0, then the loop repeats — the house
  /// redrawing itself doubles as the loading cue.
  double _loopCycle(double v) {
    if (v < 0.55) return Curves.easeInOut.transform(v / 0.55);
    if (v < 0.68) return 1.0;
    return 1.0 - Curves.easeIn.transform((v - 0.68) / 0.32);
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
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_intro, _loop]),
                  builder: (context, _) {
                    final houseReveal = _phase == _Phase.intro
                        ? Curves.easeInOut.transform(_intro.value)
                        : _loopCycle(_loop.value);
                    return CustomPaint(
                      painter: _KotiSplashPainter(houseReveal: houseReveal),
                    );
                  },
                ),
              ),
            ),
            Positioned.fill(
              child: _TitleAndStatus(
                titleVisible: _titleVisible,
                connecting: _phase == _Phase.looping && !widget.ready,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Static "KOTI" wordmark (real type, not hand-drawn) plus the "Connecting…"
/// status line, both simple fades — no path animation, matching the house
/// which is the only thing that keeps moving.
class _TitleAndStatus extends StatelessWidget {
  final bool titleVisible;
  final bool connecting;

  const _TitleAndStatus({required this.titleVisible, required this.connecting});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final houseScale = size.shortestSide * 0.30;
    final houseHeight = 1.05 * houseScale;
    final gap = size.shortestSide * 0.10;
    final titleTop = size.height / 2 - (houseHeight + gap) / 2 + houseHeight + gap;

    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: titleTop - 8,
          child: Center(
            child: AnimatedOpacity(
              opacity: titleVisible ? 1 : 0,
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
        Positioned(
          left: 0,
          right: 0,
          bottom: 48,
          child: AnimatedOpacity(
            opacity: connecting ? 1 : 0,
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
    );
  }
}

/// Reveals [source] up to arc-length fraction [t] (0..1), walking its
/// contours in the order they were added — the "pen" drawing the path.
/// Reusing this with a shrinking [t] traces the same path backward,
/// which is what makes the erase phase read as an eraser retracing the
/// pen's steps rather than a fade.
Path _revealPath(Path source, double t) {
  final result = Path();
  if (t <= 0) return result;
  final metrics = source.computeMetrics().toList();
  final total = metrics.fold<double>(0, (sum, m) => sum + m.length);
  final target = total * t.clamp(0.0, 1.0);

  var consumed = 0.0;
  for (final metric in metrics) {
    if (consumed >= target) break;
    final remaining = target - consumed;
    if (remaining >= metric.length) {
      result.addPath(metric.extractPath(0, metric.length), Offset.zero);
    } else {
      result.addPath(metric.extractPath(0, remaining), Offset.zero);
      break;
    }
    consumed += metric.length;
  }
  return result;
}

class _KotiSplashPainter extends CustomPainter {
  final double houseReveal;

  _KotiSplashPainter({required this.houseReveal});

  static final Paint _stroke = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 6.0
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  /// Minimalist house as a thick rounded stroke: the silhouette (floor,
  /// walls, roof) is ONE closed contour — the pen never lifts — so
  /// [StrokeJoin.round] softens every corner into a gentle fillet. The
  /// door is a second, separate contour.
  Path _housePath(Offset center, double scale) {
    Offset p(double x, double y) =>
        Offset(center.dx + x * scale, center.dy + y * scale);

    final outline = Path()
      ..moveTo(p(-0.50, 0.50).dx, p(-0.50, 0.50).dy)
      ..lineTo(p(0.50, 0.50).dx, p(0.50, 0.50).dy) // floor
      ..lineTo(p(0.50, -0.10).dx, p(0.50, -0.10).dy) // right wall
      ..lineTo(p(0.00, -0.55).dx, p(0.00, -0.55).dy) // roof right
      ..lineTo(p(-0.50, -0.10).dx, p(-0.50, -0.10).dy) // roof left
      ..close(); // left wall, back to start

    final door = Path()
      ..moveTo(p(-0.09, 0.50).dx, p(-0.09, 0.50).dy)
      ..lineTo(p(-0.09, 0.16).dx, p(-0.09, 0.16).dy)
      ..lineTo(p(0.09, 0.16).dx, p(0.09, 0.16).dy)
      ..lineTo(p(0.09, 0.50).dx, p(0.09, 0.50).dy);

    return outline..addPath(door, Offset.zero);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final houseScale = size.shortestSide * 0.30;
    final houseHeight = 1.05 * houseScale;
    final gap = size.shortestSide * 0.10;
    final titleCapHeight = size.shortestSide * 0.11;
    final groupHeight = houseHeight + gap + titleCapHeight;
    final top = size.height / 2 - groupHeight / 2;
    final houseCenter =
        Offset(size.width / 2, top + houseHeight / 2 - 0.025 * houseScale);

    if (houseReveal > 0) {
      canvas.drawPath(
        _revealPath(_housePath(houseCenter, houseScale), houseReveal),
        _stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _KotiSplashPainter oldDelegate) =>
      oldDelegate.houseReveal != houseReveal;
}
