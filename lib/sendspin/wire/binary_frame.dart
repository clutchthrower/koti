import 'dart:typed_data';

/// Binary frame type byte values this client actually handles. The full
/// allocation (spec messaging.md) covers artwork/source/visualizer roles
/// too (v1 only implements `player@v1`, so only these four matter).
class BinaryMessageType {
  static const jsonBody = 0;
  static const fragmentMore = 2;
  static const fragmentEnd = 3;
  static const audioChunk = 4;
}

/// The `[timestamp_us:8 BE][payload]` layout used by every "role data"
/// binary type (audio, artwork, source, visualizer) — always *after* the
/// leading type byte, which [FragmentReassembler] (or a direct single-frame
/// read) strips first, so this only ever sees the 8-byte-timestamp-plus-
/// payload remainder, not the type byte itself.
class TimestampedFramePayload {
  const TimestampedFramePayload(this.timestampUs, this.payload);

  final int timestampUs;
  final Uint8List payload;

  Uint8List encode() {
    final out = Uint8List(8 + payload.length);
    ByteData.view(out.buffer).setInt64(0, timestampUs, Endian.big);
    out.setRange(8, out.length, payload);
    return out;
  }

  static TimestampedFramePayload decode(Uint8List data) {
    return TimestampedFramePayload(
      ByteData.sublistView(data, 0, 8).getInt64(0, Endian.big),
      data.sublist(8),
    );
  }
}

/// Reassembles fragmented binary messages (spec: any application payload
/// over 65,518 bytes must fragment) into one logical `(type, data)` pair,
/// with the leading type byte already stripped from `data` either way.
/// Only one reassembly is ever in flight per connection, matching the spec.
class FragmentReassembler {
  int? _origType;
  final _chunks = <int>[];

  /// Feeds one raw (post-Noise-decryption) WS binary frame. Returns the
  /// completed `(type, data)` once a non-fragmented frame or a closing
  /// fragment-end frame is fed; returns null while more fragments of an
  /// in-progress message are still expected.
  (int type, Uint8List data)? feed(Uint8List frame) {
    final type = frame[0];
    if (type == BinaryMessageType.fragmentMore) {
      if (_origType == null) {
        _origType = frame[1];
        _chunks.addAll(frame.sublist(2));
      } else {
        _chunks.addAll(frame.sublist(1));
      }
      return null;
    }
    if (type == BinaryMessageType.fragmentEnd) {
      _chunks.addAll(frame.sublist(1));
      final data = Uint8List.fromList(_chunks);
      final origType = _origType!;
      _origType = null;
      _chunks.clear();
      return (origType, data);
    }
    return (type, Uint8List.fromList(frame.sublist(1)));
  }
}
