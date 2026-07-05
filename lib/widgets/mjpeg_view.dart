import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Live camera view fed by Home Assistant's MJPEG proxy
/// (`/api/camera_proxy_stream/<entity>`): parses the multipart stream and
/// swaps JPEG frames into an [Image.memory]. No video codecs, no WebView —
/// works on Android 7 and costs one JPEG decode per shown frame. Falls
/// back to polling still snapshots if the stream won't open.
class MjpegView extends StatefulWidget {
  final String baseUrl;
  final String accessToken;
  final String entityId;

  const MjpegView({
    super.key,
    required this.baseUrl,
    required this.accessToken,
    required this.entityId,
  });

  @override
  State<MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends State<MjpegView> {
  http.Client? _client;
  StreamSubscription? _sub;
  Timer? _snapshotTimer;
  Uint8List? _frame;
  bool _fallback = false;
  String? _error;

  final List<int> _buffer = [];
  int _lastShownMs = 0;

  @override
  void initState() {
    super.initState();
    _openStream();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _client?.close();
    _snapshotTimer?.cancel();
    super.dispose();
  }

  Map<String, String> get _headers =>
      {'Authorization': 'Bearer ${widget.accessToken}'};

  Future<void> _openStream() async {
    try {
      _client = http.Client();
      final request = http.Request(
          'GET',
          Uri.parse(
              '${widget.baseUrl}/api/camera_proxy_stream/${widget.entityId}'));
      request.headers.addAll(_headers);
      final response =
          await _client!.send(request).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      _sub = response.stream.listen(_onChunk,
          onError: (_) => _startFallback(), onDone: _startFallback);
    } catch (_) {
      _startFallback();
    }
  }

  void _onChunk(List<int> chunk) {
    _buffer.addAll(chunk);
    // Extract complete JPEGs by their SOI/EOI markers. (FF bytes inside
    // entropy-coded data are always stuffed as FF00, so FFD9 is reliable.)
    while (true) {
      final start = _indexOfMarker(0xD8);
      if (start == -1) {
        if (_buffer.length > 4 * 1024 * 1024) _buffer.clear();
        return;
      }
      final end = _indexOfMarker(0xD9, from: start + 2);
      if (end == -1) {
        if (start > 0) _buffer.removeRange(0, start);
        return;
      }
      final frame = Uint8List.fromList(_buffer.sublist(start, end + 2));
      _buffer.removeRange(0, end + 2);

      // Cap the shown rate — decoding 1080p JPEGs is the expensive part
      // on this hardware, the stream itself is cheap.
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastShownMs >= 350 && mounted) {
        _lastShownMs = now;
        setState(() => _frame = frame);
      }
    }
  }

  int _indexOfMarker(int second, {int from = 0}) {
    for (var i = from; i < _buffer.length - 1; i++) {
      if (_buffer[i] == 0xFF && _buffer[i + 1] == second) return i;
    }
    return -1;
  }

  /// Stream unavailable (some cameras only serve stills): poll snapshots.
  void _startFallback() {
    if (!mounted || _fallback) return;
    _fallback = true;
    _sub?.cancel();
    _client?.close();
    Future<void> fetch() async {
      try {
        final resp = await http
            .get(
              Uri.parse(
                  '${widget.baseUrl}/api/camera_proxy/${widget.entityId}?t=${DateTime.now().millisecondsSinceEpoch}'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200 && mounted) {
          setState(() => _frame = resp.bodyBytes);
        } else if (mounted && _frame == null) {
          setState(() => _error = 'Camera unavailable');
        }
      } catch (_) {
        if (mounted && _frame == null) {
          setState(() => _error = 'Camera unavailable');
        }
      }
    }

    fetch();
    _snapshotTimer =
        Timer.periodic(const Duration(milliseconds: 1500), (_) => fetch());
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _frame == null) {
      return SizedBox(
        height: 120,
        child: Center(
            child: Text(_error!, style: const TextStyle(color: Colors.white54))),
      );
    }
    if (_frame == null) {
      return const SizedBox(
        height: 160,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(
        _frame!,
        gaplessPlayback: true,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox(
          height: 120,
          child: Center(
              child: Text('Decode error', style: TextStyle(color: Colors.white54))),
        ),
      ),
    );
  }
}
