import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'primitives.dart';
import 'symmetric_state.dart';

/// `Noise_KKpsk2_25519_ChaChaPoly_SHA256`, hardcoded to the one role this
/// app ever plays: the spec fixes the Sendspin server as the Noise
/// *initiator* and the client (this tablet) as the *responder*, regardless
/// of which side opened the WebSocket — so this only implements the
/// responder's half of KKpsk2 (message 1 read, message 2 written) rather
/// than a general-purpose Noise engine. `KK` pre-shares both static keys
/// (`client_id`/`server_id`, exchanged in the cleartext `client/init`/
/// `server/init` messages before either Noise message is sent); `psk2`
/// mixes a pre-shared key in at the end of message 2.
///
/// Token math per the Noise spec (section 5.3), transcribed literally:
/// message 1 is `-> e, es, ss` (initiator writes), message 2 is
/// `<- e, ee, se, psk` (responder writes). Each DH token's exact operands
/// depend on which side is computing it, but both sides always land on the
/// same shared value by ECDH commutativity — see the inline comments below
/// for which pair this side computes.
class KKpsk2ResponderHandshake {
  KKpsk2ResponderHandshake({
    required this.localStatic,
    required this.remoteStaticPublicKey,
  });

  static const protocolName = 'Noise_KKpsk2_25519_ChaChaPoly_SHA256';

  final SimpleKeyPair localStatic;
  final Uint8List remoteStaticPublicKey;

  final _sym = SymmetricState();
  Uint8List? _remoteEphemeralPublicKey;

  /// `prologue` is the concatenated raw bytes of the cleartext
  /// `client/init` then `server/init` JSON messages.
  Future<void> initialize(List<int> prologue) async {
    await _sym.initializeSymmetric(utf8.encode(protocolName));
    await _sym.mixHash(prologue);
    // Pre-message tokens: the initiator's (server's) static key is hashed
    // first, then the responder's (ours) — unconditional on both sides.
    await _sym.mixHash(remoteStaticPublicKey);
    await _sym.mixHash(await extractPublicKeyBytes(localStatic));
  }

  /// Reads message 1 (`-> e, es, ss`) and returns its decrypted payload —
  /// the server's `psk_id` announcement, still cleartext of any PSK (the
  /// `es`+`ss` DH-derived key here provides confidentiality on its own;
  /// `psk2`'s actual PSK mixing doesn't happen until message 2).
  Future<Uint8List> readMessage1(Uint8List message) async {
    final remoteEphemeral = message.sublist(0, 32);
    _remoteEphemeralPublicKey = remoteEphemeral;
    await _sym.mixHash(remoteEphemeral);

    // es: as responder, this is DH(our static, their ephemeral).
    await _sym.mixKey(
      await x25519SharedSecret(localStatic, remoteEphemeral),
    );
    // ss: DH(our static, their static).
    await _sym.mixKey(
      await x25519SharedSecret(localStatic, remoteStaticPublicKey),
    );

    return _sym.decryptAndHash(message.sublist(32));
  }

  /// Writes message 2 (`<- e, ee, se, psk`) — our reply, carrying `psk` (the
  /// Sentinel PSK, a Pairing PSK, or a long-term PSK depending on what
  /// `psk_id` selected) and `payload` (an empty `{}` for a normal
  /// handshake completion).
  Future<Uint8List> writeMessage2(Uint8List psk, List<int> payload) async {
    final remoteEphemeral = _remoteEphemeralPublicKey!;
    final localEphemeral = await newX25519KeyPair();
    final localEphemeralPublicKey = await extractPublicKeyBytes(localEphemeral);
    await _sym.mixHash(localEphemeralPublicKey);

    // ee: DH(our ephemeral, their ephemeral).
    await _sym.mixKey(
      await x25519SharedSecret(localEphemeral, remoteEphemeral),
    );
    // se: as responder writing, this is DH(our ephemeral, their static).
    await _sym.mixKey(
      await x25519SharedSecret(localEphemeral, remoteStaticPublicKey),
    );
    // psk2's PSK mix, at the end of message 2's token list.
    await _sym.mixKeyAndHash(psk);

    final ciphertext = await _sym.encryptAndHash(payload);
    return Uint8List.fromList([...localEphemeralPublicKey, ...ciphertext]);
  }

  /// Returns `(sendKey, receiveKey)` for this side (the responder) — the
  /// initiator gets the same two keys in the opposite roles.
  Future<(Uint8List sendKey, Uint8List receiveKey)> split() async {
    final (c1, c2) = await _sym.split();
    return (c2, c1);
  }

  /// The 32-byte Noise handshake hash (`h`) once the handshake completes —
  /// used as PAKE session-binding material for pairing (`sid` in CPace),
  /// not needed for the unpaired-access v1 path but kept accessible since
  /// it's a cheap byproduct of the handshake either way.
  Uint8List get handshakeHash => Uint8List.fromList(_sym.h);
}
