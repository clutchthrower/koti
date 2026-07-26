import 'dart:math' as math;

/// Tracks clock offset and drift between this client and the Sendspin
/// server via periodic `client/time`/`server/time` round trips, so a
/// server-domain playback timestamp can be converted to this device's own
/// clock. A 1:1 port of `aiosendspin`'s `SendspinTimeFilter` (itself a port
/// of ESPHome's implementation) — a 2D Kalman filter over `[offset, drift]`
/// with covariance tracked as three scalars rather than a full matrix.
///
/// All timestamps are microseconds. Callers should use a monotonic clock
/// consistently (e.g. `Stopwatch`) — an NTP-slewed wall clock "poisons" the
/// filter per the spec, though this app has no direct equivalent of Linux's
/// `CLOCK_MONOTONIC_RAW` to reach for instead.
class SendspinTimeFilter {
  double? _offset;
  double _drift = 0;
  double _offsetCovariance = 0;
  double _offsetDriftCovariance = 0;
  double _driftCovariance = 0;
  int? _lastUpdateUs;
  int _count = 0;

  static const _driftProcessVariance = 1e-11 * 1e-11;
  static const _processVariance = 0.0;
  static const _forgetFactor = 2.0;
  static const _maxErrorScale = 0.5;
  static const _adaptiveForgettingCutoff = 3.0;
  static const _adaptiveForgettingMinSamples = 100;
  static const _driftSignificanceThresholdSquared = 4.0;
  static const _minCovariance = 1e-9;

  bool get isSynchronized =>
      _count >= 2 && _offset != null && _offsetCovariance.isFinite;

  /// Estimated one-way sync error (µs) — feeds the spec's recommended
  /// `client/time` send-interval tuning (3s/1s/0.5s/0.2s at <1ms/<2ms/<5ms/
  /// else).
  double get errorUs =>
      _offsetCovariance.isFinite ? math.sqrt(_offsetCovariance.abs()) : double.infinity;

  /// Stricter than [isSynchronized] — that one matches aiosendspin's own
  /// spec-defined threshold (just 2 samples) and shouldn't change, but 2
  /// samples is a very thin basis for actually trusting this filter's
  /// offset/drift enough to SCHEDULE audio precisely against it, rather
  /// than just writing chunks as they arrive. Modeled on a second,
  /// independent Sendspin client's own equivalent gate
  /// (massdroid_native's ClockSynchronizer.isReadyForPlaybackStart: count
  /// >= 8, error <= 5ms) — right when a tablet joins an already-playing
  /// group is exactly when the filter is freshest and least converged,
  /// so committing to precise scheduling that early is a plausible
  /// contributor to reported multi-second group-sync drift.
  bool get isReadyForPrecisionScheduling => _count >= 8 && errorUs <= 5000;

  /// Feeds one round trip: `t0`=`client_transmitted` (this client's own
  /// send time), `t1`=`server_received`, `t2`=`server_transmitted` (both
  /// from the `server/time` reply), `t3`=this client's local receive time
  /// for that reply.
  void update(int t0, int t1, int t2, int t3) {
    final offsetMeasurement = ((t1 - t0) + (t2 - t3)) / 2.0;
    final delay = ((t3 - t0) - (t2 - t1)) / 2.0;
    _applyMeasurement(offsetMeasurement, delay * _maxErrorScale, t3);
  }

  void _applyMeasurement(double measurement, double maxError, int timeUs) {
    final lastUpdate = _lastUpdateUs;
    if (lastUpdate != null && timeUs <= lastUpdate) {
      return; // non-monotonic sample — discard
    }

    if (_offset == null) {
      _offset = measurement;
      // maxError already has _maxErrorScale applied once by update() (the
      // caller) — matching aiosendspin's own SendspinTimeFilter, which
      // computes measurement_variance = (max_error * MAX_ERROR_SCALE)^2
      // identically for every sample. This branch previously applied an
      // extra, erroneous *0.5 on top, making the very first covariance
      // seed 4x too small (overconfident) relative to every later
      // sample's plain maxError^2 — confirmed against both the actual
      // aiosendspin source and a second independent Kotlin port
      // (massdroid_native's ClockSynchronizer). An overconfident first
      // seed propagates into the drift-covariance calculation on sample 2
      // and from there into the Kalman gains for a while, a real
      // mechanism for a slow-to-correct offset bias — plausibly
      // contributing to the reported multi-second group-sync drift.
      _offsetCovariance = maxError * maxError;
      _lastUpdateUs = timeUs;
      _count = 1;
      return;
    }

    if (_count == 1) {
      // dt stays in the same units as the timestamps (µs), not seconds —
      // `drift` must be a dimensionless ratio (offset-delta / time-delta,
      // both µs) for computeClientTime's `drift * (time delta in µs)` to
      // yield a µs result.
      final dt = (timeUs - lastUpdate!).toDouble();
      final measurementVariance = maxError * maxError;
      if (dt > 0) {
        _drift = (measurement - _offset!) / dt;
        _driftCovariance = (_offsetCovariance + measurementVariance) / (dt * dt);
      }
      _offset = measurement;
      _lastUpdateUs = timeUs;
      _count = 2;
      return;
    }

    final dt = (timeUs - lastUpdate!).toDouble();
    var offsetPred = _offset! + _drift * dt;
    var driftCovPred = _driftCovariance + dt * _driftProcessVariance;
    var offsetDriftCovPred = _offsetDriftCovariance + _driftCovariance * dt;
    var offsetCovPred = _offsetCovariance +
        2 * _offsetDriftCovariance * dt +
        _driftCovariance * dt * dt +
        dt * _processVariance;

    final residual = measurement - offsetPred;
    final measurementVariance = maxError * maxError;

    if (_count >= _adaptiveForgettingMinSamples &&
        residual.abs() > _adaptiveForgettingCutoff * maxError) {
      final forgetSq = _forgetFactor * _forgetFactor;
      driftCovPred *= forgetSq;
      offsetDriftCovPred *= forgetSq;
      offsetCovPred *= forgetSq;
    }

    final s = math.max(offsetCovPred + measurementVariance, _minCovariance);
    final kOffset = offsetCovPred / s;
    final kDrift = offsetDriftCovPred / s;

    _offset = offsetPred + kOffset * residual;
    _drift = _drift + kDrift * residual;
    _driftCovariance = driftCovPred - kDrift * offsetDriftCovPred;
    _offsetDriftCovariance = offsetDriftCovPred - kDrift * offsetCovPred;
    _offsetCovariance = offsetCovPred - kOffset * offsetCovPred;

    _lastUpdateUs = timeUs;
    _count++;
  }

  /// Drift is only applied in conversions once it's statistically
  /// significant (2σ gate) — otherwise treated as zero.
  double get _effectiveDrift =>
      _drift * _drift > _driftSignificanceThresholdSquared * _driftCovariance ? _drift : 0.0;

  /// Converts a server-domain timestamp (as carried in `stream/start` and
  /// binary audio-frame headers) to this client's local clock, using the
  /// last accepted filter state (not re-predicted per call).
  int computeClientTime(int serverTimeUs) {
    final offset = _offset;
    final lastUpdate = _lastUpdateUs;
    if (offset == null || lastUpdate == null) {
      throw StateError('Time filter has no samples yet');
    }
    final drift = _effectiveDrift;
    return ((serverTimeUs - offset + drift * lastUpdate) / (1 + drift)).round();
  }
}
