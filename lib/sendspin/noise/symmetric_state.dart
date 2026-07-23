import 'dart:typed_data';

import 'primitives.dart';

/// Noise Protocol Framework `SymmetricState` (spec section 5.2), mechanical
/// transliteration of the spec's own pseudocode — kept literal on purpose so
/// it can be checked line-by-line against the spec rather than trusted on
/// faith. `HASHLEN` is fixed at 32 (SHA-256), so the "truncate to 32 bytes
/// if HASHLEN==64" steps the spec describes for SHA-512 don't apply here.
class SymmetricState {
  late Uint8List h;
  late Uint8List ck;
  Uint8List? _k;
  int _n = 0;

  Future<void> initializeSymmetric(List<int> protocolName) async {
    if (protocolName.length <= 32) {
      h = Uint8List(32)..setRange(0, protocolName.length, protocolName);
    } else {
      h = await sha256Hash(protocolName);
    }
    ck = Uint8List.fromList(h);
    _k = null;
    _n = 0;
  }

  Future<void> mixHash(List<int> data) async {
    h = await sha256Hash([...h, ...data]);
  }

  Future<void> mixKey(List<int> inputKeyMaterial) async {
    final outputs = await noiseHkdf(ck, inputKeyMaterial, 2);
    ck = outputs[0];
    _k = outputs[1];
    _n = 0;
  }

  /// Only used for the `psk` token — also mixes into `h`, unlike [mixKey].
  Future<void> mixKeyAndHash(List<int> inputKeyMaterial) async {
    final outputs = await noiseHkdf(ck, inputKeyMaterial, 3);
    ck = outputs[0];
    await mixHash(outputs[1]);
    _k = outputs[2];
    _n = 0;
  }

  Future<Uint8List> encryptAndHash(List<int> plaintext) async {
    final k = _k;
    if (k == null) {
      await mixHash(plaintext);
      return Uint8List.fromList(plaintext);
    }
    final ciphertext = await aeadEncrypt(k, _n, h, plaintext);
    _n++;
    await mixHash(ciphertext);
    return ciphertext;
  }

  Future<Uint8List> decryptAndHash(List<int> ciphertext) async {
    final k = _k;
    if (k == null) {
      await mixHash(ciphertext);
      return Uint8List.fromList(ciphertext);
    }
    final plaintext = await aeadDecrypt(k, _n, h, ciphertext);
    _n++;
    await mixHash(ciphertext);
    return plaintext;
  }

  /// Returns `(c1, c2)` — two independent transport keys derived from the
  /// final chaining key once the handshake's message pattern is exhausted.
  Future<(Uint8List, Uint8List)> split() async {
    final outputs = await noiseHkdf(ck, const [], 2);
    return (outputs[0], outputs[1]);
  }
}
