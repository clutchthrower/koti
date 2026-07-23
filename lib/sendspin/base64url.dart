import 'dart:convert';
import 'dart:typed_data';

/// Every identifier/handshake-blob field in the Sendspin wire protocol is
/// base64url with no padding (`client_id`, `server_id`, `noise/handshake`'s
/// `data`, `psk_id`, ...) — `dart:convert`'s codec defaults to padded output
/// and a decoder that requires it, so both directions need a small wrapper.
String base64UrlNoPad(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List base64UrlNoPadDecode(String value) {
  final padded = value.padRight((value.length + 3) ~/ 4 * 4, '=');
  return base64Url.decode(padded);
}
