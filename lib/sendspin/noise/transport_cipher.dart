import 'dart:typed_data';

import 'primitives.dart';

/// Noise transport-mode `CipherState` (spec section 5.1) for one direction
/// — send and receive each get their own instance (their own key, their
/// own independently-incrementing nonce counter). Transport messages use
/// empty associated data, per the Noise spec's standard transport-mode
/// `EncryptWithAd`/`DecryptWithAd` default.
class TransportCipher {
  TransportCipher(this._key);

  final Uint8List _key;
  int _n = 0;

  Future<Uint8List> encrypt(List<int> plaintext) async {
    final ciphertext = await aeadEncrypt(_key, _n, const [], plaintext);
    _n++;
    return ciphertext;
  }

  Future<Uint8List> decrypt(List<int> ciphertext) async {
    final plaintext = await aeadDecrypt(_key, _n, const [], ciphertext);
    _n++;
    return plaintext;
  }
}
