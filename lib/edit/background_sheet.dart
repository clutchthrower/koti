import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/room_config.dart';

const _demoOptions = [
  ('home-demo', 'Home'),
  ('livingroom-demo', 'Living Room'),
  ('kitchen-demo', 'Kitchen'),
  ('bedroom-demo', 'Bedroom'),
  ('security-demo', 'Security'),
];

/// Pick a room background: automatic (keyword-matched bundled photo), one
/// of the bundled photos explicitly, or the user's own photo. Returns the
/// updated room, or null if cancelled.
Future<RoomConfig?> showBackgroundSheet(BuildContext context, RoomConfig room) {
  return showModalBottomSheet<RoomConfig>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _BackgroundSheet(room: room),
  );
}

class _BackgroundSheet extends StatefulWidget {
  final RoomConfig room;
  const _BackgroundSheet({required this.room});

  @override
  State<_BackgroundSheet> createState() => _BackgroundSheetState();
}

class _BackgroundSheetState extends State<_BackgroundSheet> {
  bool _busy = false;
  String? _error;

  /// Copies the picked photo into app storage, shrunk (480px wide) so
  /// stretching it fullscreen gives the dashboard's soft-blur look with
  /// zero runtime blur cost — same trick as the pre-blurred bundled photos.
  Future<void> _pickPhoto() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) {
        setState(() => _busy = false);
        return;
      }
      final bytes = await picked.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 480);
      final frame = await codec.getNextFrame();
      final data =
          await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('could not read the image');

      final dir = await getApplicationDocumentsDirectory();
      final bgDir = Directory('${dir.path}/backgrounds');
      await bgDir.create(recursive: true);
      final file = File(
          '${bgDir.path}/${widget.room.id}-${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(data.buffer.asUint8List());

      // Clean up this room's previous custom photo, if any.
      final old = widget.room.backgroundAsset;
      if (old != null && old.startsWith('/')) {
        try {
          await File(old).delete();
        } catch (_) {}
      }

      if (!mounted) return;
      Navigator.of(context)
          .pop(widget.room.copyWith(backgroundAsset: file.path));
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'Couldn\'t use that photo: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.room.backgroundAsset;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Background', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Choose what shows behind ${widget.room.name}.',
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('Automatic'),
            subtitle: const Text('Picks a bundled photo matching the room'),
            trailing: current == null ? const Icon(Icons.check) : null,
            onTap: () => Navigator.of(context)
                .pop(widget.room.copyWith(backgroundAsset: null)),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _demoOptions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final (base, label) = _demoOptions[i];
                final selected = current == 'demo:$base';
                return GestureDetector(
                  onTap: () => Navigator.of(context)
                      .pop(widget.room.copyWith(backgroundAsset: 'demo:$base')),
                  child: Column(
                    children: [
                      Container(
                        width: 110,
                        height: 70,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: selected
                              ? Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2)
                              : null,
                          image: DecorationImage(
                            image: AssetImage('assets/rooms/blur/$base.jpg'),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(label, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: _busy
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.photo_library_outlined),
            label: Text(_busy ? 'Preparing…' : 'Choose Your Own Photo'),
            onPressed: _busy ? null : _pickPhoto,
          ),
        ],
      ),
    );
  }
}
