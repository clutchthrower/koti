import 'dart:convert';

/// JSON message `type` string constants actually used by this client —
/// limited to the core connection/player-role set the plan scopes v1 to
/// (unpaired access, `player@v1` only). Pairing and management message
/// types are deliberately omitted; v1 never sends or expects them.
class MessageType {
  static const clientInit = 'client/init';
  static const serverInit = 'server/init';
  static const noiseHandshake = 'noise/handshake';
  static const serverHello = 'server/hello';
  static const clientHello = 'client/hello';
  static const serverActivate = 'server/activate';
  static const clientTime = 'client/time';
  static const serverTime = 'server/time';
  static const clientState = 'client/state';
  static const serverState = 'server/state';
  static const groupUpdate = 'group/update';
  static const streamStart = 'stream/start';
  static const streamClear = 'stream/clear';
  static const streamEnd = 'stream/end';
  static const clientCommand = 'client/command';
  static const serverCommand = 'server/command';
  static const clientGoodbye = 'client/goodbye';
}

/// The `{"type": ..., "payload": {...}}` envelope every Sendspin JSON
/// message uses.
class SendspinEnvelope {
  const SendspinEnvelope(this.type, this.payload);

  final String type;
  final Map<String, dynamic> payload;

  /// The exact UTF-8 bytes this encodes to — callers that need the raw
  /// wire bytes (e.g. for the Noise handshake prologue) should keep this
  /// rather than re-encoding, since re-serializing could reorder keys.
  String encode() => jsonEncode({'type': type, 'payload': payload});

  static SendspinEnvelope decode(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final payload = json['payload'];
    return SendspinEnvelope(
      json['type'] as String,
      payload is Map ? payload.cast<String, dynamic>() : const {},
    );
  }
}
