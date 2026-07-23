import 'dart:async';

/// Queues events off a stream via one persistent subscription, so a test
/// fixture can `await` each expected message in strict order without the
/// `stream.firstWhere(...)` anti-pattern: calling `firstWhere` repeatedly on
/// a broadcast stream re-subscribes each time, and any event arriving in
/// the gap between one call's subscription being cancelled and the next
/// one's starting is silently dropped — a real race that surfaced as
/// intermittent "wrong MAC" failures once two client messages started
/// arriving close enough together (a few milliseconds apart).
class TestEventPump {
  TestEventPump(Stream<dynamic> source) {
    _subscription = source.listen((event) {
      _queue.add(event);
      _drain();
    });
  }

  late final StreamSubscription<dynamic> _subscription;
  final _queue = <dynamic>[];
  final _waiters = <Completer<void>>[];

  void _drain() {
    while (_waiters.isNotEmpty && _queue.isNotEmpty) {
      _waiters.removeAt(0).complete();
    }
  }

  Future<dynamic> _next() async {
    while (_queue.isEmpty) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    return _queue.removeAt(0);
  }

  Future<String> nextText() async {
    final event = await _next();
    if (event is! String) {
      throw StateError('Expected a text frame, got ${event.runtimeType}');
    }
    return event;
  }

  Future<List<int>> nextBinary() async {
    final event = await _next();
    if (event is List<int>) return event;
    throw StateError('Expected a binary frame, got ${event.runtimeType}');
  }

  Future<void> cancel() => _subscription.cancel();
}
