import 'package:flutter/material.dart';

import '../theme/koti_theme.dart';

/// Pushes [page] (any ordinary `Scaffold`-returning page) constrained into
/// a standard-sized, rounded, glass-bordered card floating over a dimmed
/// backdrop — instead of taking over the whole screen. Settings sub-pages
/// (Rooms, Display, Connection, …) read as popups growing out of the
/// Settings "room" this way, rather than a different kind of screen
/// bolted on top of it. [page] itself is untouched — it still renders its
/// own Scaffold/AppBar/body exactly as it does when pushed normally (e.g.
/// from the pre-onboarding "no rooms yet" fallback), just inside a smaller
/// box, so the same page works either way.
Future<T?> pushGlassSheet<T>(
  BuildContext context,
  Widget page, {
  double maxWidth = 560,
}) {
  return Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) {
        final tokens = KotiTheme.of(context);
        final size = MediaQuery.sizeOf(context);
        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: size.height * 0.86,
              ),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                padding: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: tokens.borderGradient,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(27),
                  child: page,
                ),
              ),
            ),
          ),
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
    ),
  );
}
