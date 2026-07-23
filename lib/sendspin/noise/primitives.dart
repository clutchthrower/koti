import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Thin wrappers over `package:cryptography` primitives, scoped to exactly
/// what `Noise_KKpsk2_25519_ChaChaPoly_SHA256` needs — kept separate from
/// [SymmetricState]/`handshake_state.dart` so those read as the Noise spec's
/// own pseudocode, not tangled with which Dart package supplies the math.

Future<Uint8List> sha256Hash(List<int> data) async {
  final hash = await Sha256().hash(data);
  return Uint8List.fromList(hash.bytes);
}

/// Noise's own HKDF (spec section 4.3) — HMAC-based, 2 or 3 outputs.
/// Deliberately hand-rolled from raw HMAC calls rather than routed through
/// `package:cryptography`'s `Hkdf` (RFC 5869) class: that class's
/// `secretKey`/`nonce` parameters map to IKM/salt in a way not worth risking
/// a mismatch on for a handshake where a wrong byte fails silently.
Future<List<Uint8List>> noiseHkdf(
  Uint8List chainingKey,
  List<int> inputKeyMaterial,
  int numOutputs,
) async {
  final hmac = Hmac.sha256();
  final tempKeyMac = await hmac.calculateMac(
    inputKeyMaterial,
    secretKey: SecretKey(chainingKey),
  );
  final tempKey = SecretKey(tempKeyMac.bytes);

  final output1 = Uint8List.fromList(
    (await hmac.calculateMac([0x01], secretKey: tempKey)).bytes,
  );
  final output2 = Uint8List.fromList(
    (await hmac.calculateMac([...output1, 0x02], secretKey: tempKey)).bytes,
  );
  if (numOutputs == 2) return [output1, output2];

  final output3 = Uint8List.fromList(
    (await hmac.calculateMac([...output2, 0x03], secretKey: tempKey)).bytes,
  );
  return [output1, output2, output3];
}

/// Noise nonce encoding: 4 zero bytes followed by an 8-byte little-endian
/// counter (spec section 4, "the 96-bit nonce ... 32 bits of zeros followed
/// by little-endian encoding of n").
Uint8List noiseNonce(int counter) {
  final bytes = Uint8List(12);
  ByteData.view(bytes.buffer).setUint64(4, counter, Endian.little);
  return bytes;
}

const _aeadTagLength = 16;

Future<Uint8List> aeadEncrypt(
  Uint8List key,
  int counter,
  List<int> associatedData,
  List<int> plaintext,
) async {
  final box = await Chacha20.poly1305Aead().encrypt(
    plaintext,
    secretKey: SecretKey(key),
    nonce: noiseNonce(counter),
    aad: associatedData,
  );
  return Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
}

Future<Uint8List> aeadDecrypt(
  Uint8List key,
  int counter,
  List<int> associatedData,
  List<int> ciphertextAndTag,
) async {
  final splitAt = ciphertextAndTag.length - _aeadTagLength;
  final box = SecretBox(
    ciphertextAndTag.sublist(0, splitAt),
    nonce: noiseNonce(counter),
    mac: Mac(ciphertextAndTag.sublist(splitAt)),
  );
  final clear = await Chacha20.poly1305Aead().decrypt(
    box,
    secretKey: SecretKey(key),
    aad: associatedData,
  );
  return Uint8List.fromList(clear);
}

Future<SimpleKeyPair> newX25519KeyPair() => X25519().newKeyPair();

Future<Uint8List> x25519SharedSecret(
  SimpleKeyPair localKeyPair,
  Uint8List remotePublicKeyBytes,
) async {
  final secret = await X25519().sharedSecretKey(
    keyPair: localKeyPair,
    remotePublicKey: SimplePublicKey(remotePublicKeyBytes, type: KeyPairType.x25519),
  );
  return Uint8List.fromList(await secret.extractBytes());
}

Future<Uint8List> extractPublicKeyBytes(SimpleKeyPair keyPair) async {
  final publicKey = await keyPair.extractPublicKey();
  return Uint8List.fromList(publicKey.bytes);
}
