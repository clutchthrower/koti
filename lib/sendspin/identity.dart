import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'base64url.dart';
import 'noise/primitives.dart';

/// This tablet's stable Sendspin identity — an X25519 keypair whose public
/// key is the `client_id` sent in every `client/init`. Persisted rather
/// than regenerated per connection: a stable identity is what a future
/// Pairing-PSK trust tier would key its persisted PSK record against, even
/// though v1's unpaired-access path doesn't itself require stability.
/// Stored via `flutter_secure_storage`, matching how the HA access token is
/// already stored (see `lib/store/settings_store.dart`).
class SendspinIdentity {
  SendspinIdentity._(this.keyPair, this.publicKeyBytes);

  final SimpleKeyPair keyPair;
  final Uint8List publicKeyBytes;

  static const _storageKey = 'koti_sendspin_identity_seed_b64url';
  static const _storage = FlutterSecureStorage();

  static Future<SendspinIdentity> load() async {
    final stored = await _storage.read(key: _storageKey);
    final SimpleKeyPair keyPair;
    if (stored != null) {
      keyPair = await X25519().newKeyPairFromSeed(base64UrlNoPadDecode(stored));
    } else {
      keyPair = await newX25519KeyPair();
      final seed = await keyPair.extractPrivateKeyBytes();
      await _storage.write(key: _storageKey, value: base64UrlNoPad(seed));
    }
    return SendspinIdentity._(keyPair, await extractPublicKeyBytes(keyPair));
  }

  /// Bypasses secure-storage persistence — for tests only, since
  /// `flutter_secure_storage` has no platform implementation under
  /// `flutter test` (see `test/widget_test.dart`'s header comment for the
  /// same constraint elsewhere in this codebase).
  static Future<SendspinIdentity> forTesting(SimpleKeyPair keyPair) async {
    return SendspinIdentity._(keyPair, await extractPublicKeyBytes(keyPair));
  }

  /// The `client_id` field value — 43-char base64url, no padding.
  String get clientId => base64UrlNoPad(publicKeyBytes);
}
