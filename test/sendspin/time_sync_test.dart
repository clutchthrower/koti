import 'package:flutter_test/flutter_test.dart';
import 'package:koti/sendspin/time_sync.dart';

void main() {
  test('converges to the true offset and drift from noise-free round trips', () {
    const trueOffsetUs = 5000.0; // server clock reads 5ms ahead of client clock
    const trueDrift = 0.00002; // 20ppm
    const oneWayDelayUs = 1500;
    const intervalUs = 1000000; // one round trip per simulated second

    final filter = SendspinTimeFilter();
    for (var i = 0; i < 150; i++) {
      final t0 = i * intervalUs;
      // Same-clock round-trip timing on the client side needs no cross-clock
      // conversion; only t1/t2 (server clock) do.
      final t3 = t0 + 2 * oneWayDelayUs;
      final serverTimeAtSend = t0 + trueOffsetUs + trueDrift * t0;
      final t1 = (serverTimeAtSend + oneWayDelayUs).round();
      const t2Offset = 0; // negligible server-side processing time
      final t2 = t1 + t2Offset;
      filter.update(t0, t1, t2, t3);
    }

    expect(filter.isSynchronized, isTrue);
    // Spec's steady-state target for the Player role is within ±1ms (target
    // ±0.5ms) — this noise-free synthetic run should comfortably clear that.
    expect(filter.errorUs, lessThan(1000));

    // computeClientTime should invert the synthetic server-clock mapping:
    // a server timestamp corresponding to some known client time should map
    // back close to that client time.
    const probeClientTime = 130 * intervalUs;
    final probeServerTime = (probeClientTime + trueOffsetUs + trueDrift * probeClientTime).round();
    final recoveredClientTime = filter.computeClientTime(probeServerTime);
    expect(
      (recoveredClientTime - probeClientTime).abs(),
      lessThan(1000),
      reason: 'recovered client time should track the true mapping within about 1ms',
    );
  });

  test('first sample\'s error matches maxError, not a quarter of it', () {
    // t0=0 (client sent), t3=2000 (client received) -> round trip 2000us;
    // t1=t2=1000 (instant server processing) -> delay = ((t3-t0)-(t2-t1))/2
    // = 1000us, so maxError passed into the filter = 1000 * MAX_ERROR_SCALE
    // (0.5) = 500. The first sample's covariance seed should be
    // maxError^2 == 500^2, matching every later sample's plain
    // maxError*maxError — not (maxError*0.5)^2, a since-fixed regression
    // that made the very first seed 4x too confident.
    final filter = SendspinTimeFilter();
    filter.update(0, 1000, 1000, 2000);
    expect(filter.errorUs, closeTo(500, 0.001));
  });

  test('is not synchronized before at least two samples', () {
    final filter = SendspinTimeFilter();
    expect(filter.isSynchronized, isFalse);
    filter.update(0, 5000, 5000, 3000);
    expect(filter.isSynchronized, isFalse);
    filter.update(1000000, 1005000, 1005000, 1003000);
    expect(filter.isSynchronized, isTrue);
  });

  test('discards non-monotonic samples without throwing', () {
    final filter = SendspinTimeFilter();
    filter.update(0, 5000, 5000, 3000);
    filter.update(1000000, 1005000, 1005000, 1003000);
    final beforeError = filter.errorUs;
    // A reply whose local receive time doesn't advance past the last update.
    filter.update(500000, 505000, 505000, 1003000);
    expect(filter.errorUs, beforeError);
  });

  test('computeClientTime throws before any sample has been fed', () {
    final filter = SendspinTimeFilter();
    expect(() => filter.computeClientTime(1000), throwsStateError);
  });
}
