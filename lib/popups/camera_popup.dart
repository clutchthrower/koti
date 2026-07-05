import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../store/settings_store.dart';
import '../widgets/mjpeg_view.dart';
import 'popup_base.dart';

/// Live camera view in an anchored popup: MJPEG stream while open,
/// falling back to fast snapshot polling for stills-only cameras.
void showCameraPopup(BuildContext context, {required String entityId, String? title}) {
  final settings = Provider.of<SettingsStore>(context, listen: false);
  showHemmaPopup(
    context,
    title: title ?? 'Camera',
    builder: (context) => MjpegView(
      baseUrl: settings.activeUrl,
      accessToken: settings.accessToken ?? '',
      entityId: entityId,
    ),
  );
}
