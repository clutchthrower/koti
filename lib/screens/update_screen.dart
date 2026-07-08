import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api/app_update.dart';
import 'koti_splash_screen.dart';

/// Blocking "Please Update" screen shown when a newer release exists.
/// Downloads the APK in-app with progress, then hands it to Android's
/// package installer. A small escape hatch at the bottom lets the
/// dashboard keep working if updating right now isn't possible.
class UpdateScreen extends StatefulWidget {
  final AppUpdateInfo info;
  final String currentVersion;
  final VoidCallback onSkip;

  const UpdateScreen({
    super.key,
    required this.info,
    required this.currentVersion,
    required this.onSkip,
  });

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  double? _progress; // null = not downloading, 0..1 while downloading
  String? _error;

  Future<void> _update() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/koti-update.apk');

      final request = http.Request('GET', Uri.parse(widget.info.apkUrl));
      final response = await http.Client().send(request);
      if (response.statusCode != 200) {
        throw Exception('download failed (HTTP ${response.statusCode})');
      }
      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();
      await response.stream.listen((chunk) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0 && mounted) {
          setState(() => _progress = received / total);
        }
      }).asFuture<void>();
      await sink.close();

      // Hand the APK to Android's installer (FileProvider on the native
      // side). The system takes over from here.
      await const MethodChannel('koti/native')
          .invokeMethod('installApk', {'path': file.path});
      if (mounted) setState(() => _progress = null);
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = 'Update failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloading = _progress != null;

    return Scaffold(
      backgroundColor: KotiSplashScreen.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  const Icon(Icons.system_update_alt,
                      size: 56, color: Color(0xFF6EBAFF)),
                  const SizedBox(height: 20),
                  const Text(
                    'Update Available',
                    style: TextStyle(
                      fontFamily: 'Hanken Grotesk',
                      fontWeight: FontWeight.w700,
                      fontSize: 28,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Koti ${widget.currentVersion} → ${widget.info.version}',
                    style: const TextStyle(
                        color: Color.fromRGBO(255, 255, 255, 0.75), fontSize: 15),
                  ),
                  if (widget.info.notes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: SingleChildScrollView(
                        child: Text(
                          widget.info.notes,
                          style: const TextStyle(
                              color: Color.fromRGBO(255, 255, 255, 0.6), fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ],
                  const SizedBox(height: 24),
                  if (downloading) ...[
                    LinearProgressIndicator(
                        value: _progress == 0 ? null : _progress,
                        backgroundColor: const Color.fromRGBO(255, 255, 255, 0.2),
                        color: const Color(0xFF6EBAFF)),
                    const SizedBox(height: 12),
                    Text(
                      'Downloading… ${((_progress ?? 0) * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(color: Color.fromRGBO(255, 255, 255, 0.75)),
                    ),
                  ] else
                    FilledButton.icon(
                      icon: const Icon(Icons.download),
                      label: const Text('Update Now'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 40, vertical: 16),
                      ),
                      onPressed: _update,
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: widget.onSkip,
                    child: const Text('Not now',
                        style: TextStyle(color: Color.fromRGBO(255, 255, 255, 0.55))),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
