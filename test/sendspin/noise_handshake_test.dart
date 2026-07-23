import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koti/sendspin/noise/handshake_state.dart';
import 'package:koti/sendspin/noise/primitives.dart';
import 'package:koti/sendspin/noise/symmetric_state.dart';

/// There's no public KKpsk2 test-vector suite to check against, so this
/// simulates the *initiator* (server) side directly — using the same
/// [SymmetricState] primitives [KKpsk2ResponderHandshake] is built on, but
/// performing the initiator's own token/DH assignments (which differ from
/// the responder's for the `es`/`se` tokens) — and asserts a full handshake
/// between the two lands on matching transport keys. This exercises every
/// primitive (mixHash/mixKey/mixKeyAndHash/encryptAndHash/split) and every
/// DH token assignment; the real cross-implementation check against a live
/// Music Assistant server happens in the next build stage.
class _FakeInitiator {
  _FakeInitiator(this.localStatic, this.remoteStaticPublicKey);

  final SimpleKeyPair localStatic;
  final Uint8List remoteStaticPublicKey;
  final _sym = SymmetricState();
  SimpleKeyPair? _localEphemeral;

  Future<void> initialize(List<int> prologue) async {
    await _sym.initializeSymmetric(
      utf8.encode(KKpsk2ResponderHandshake.protocolName),
    );
    await _sym.mixHash(prologue);
    // Initiator's own static key is hashed first, then the responder's.
    await _sym.mixHash(await extractPublicKeyBytes(localStatic));
    await _sym.mixHash(remoteStaticPublicKey);
  }

  Future<Uint8List> writeMessage1(List<int> payload) async {
    final e = await newX25519KeyPair();
    _localEphemeral = e;
    final ePub = await extractPublicKeyBytes(e);
    await _sym.mixHash(ePub);
    // es, as initiator: DH(our ephemeral, their static).
    await _sym.mixKey(await x25519SharedSecret(e, remoteStaticPublicKey));
    // ss: DH(our static, their static).
    await _sym.mixKey(await x25519SharedSecret(localStatic, remoteStaticPublicKey));
    final ciphertext = await _sym.encryptAndHash(payload);
    return Uint8List.fromList([...ePub, ...ciphertext]);
  }

  Future<Uint8List> readMessage2(Uint8List message, Uint8List psk) async {
    final remoteEphemeral = message.sublist(0, 32);
    await _sym.mixHash(remoteEphemeral);
    // ee: DH(our ephemeral, their ephemeral).
    await _sym.mixKey(
      await x25519SharedSecret(_localEphemeral!, remoteEphemeral),
    );
    // se, as initiator: DH(our static, their ephemeral).
    await _sym.mixKey(
      await x25519SharedSecret(localStatic, remoteEphemeral),
    );
    await _sym.mixKeyAndHash(psk);
    return _sym.decryptAndHash(message.sublist(32));
  }

  Future<(Uint8List sendKey, Uint8List receiveKey)> split() async {
    final (c1, c2) = await _sym.split();
    return (c1, c2); // initiator: no swap (responder is the one that swaps)
  }

  Uint8List get handshakeHash => Uint8List.fromList(_sym.h);
}

void main() {
  test('KKpsk2 handshake round-trips and derives matching transport keys', () async {
    final serverStatic = await newX25519KeyPair();
    final clientStatic = await newX25519KeyPair();
    final serverStaticPub = await extractPublicKeyBytes(serverStatic);
    final clientStaticPub = await extractPublicKeyBytes(clientStatic);

    final prologue = utf8.encode('client/init+server/init placeholder');
    final psk = await sha256Hash(utf8.encode('sendspin-sentinel-psk-v1'));

    final initiator = _FakeInitiator(serverStatic, clientStaticPub);
    final responder = KKpsk2ResponderHandshake(
      localStatic: clientStatic,
      remoteStaticPublicKey: serverStaticPub,
    );
    await initiator.initialize(prologue);
    await responder.initialize(prologue);

    final message1 = await initiator.writeMessage1(utf8.encode('{"psk_id":"abc"}'));
    final message1Payload = await responder.readMessage1(message1);
    expect(utf8.decode(message1Payload), '{"psk_id":"abc"}');

    final message2 = await responder.writeMessage2(psk, utf8.encode('{}'));
    final message2Payload = await initiator.readMessage2(message2, psk);
    expect(utf8.decode(message2Payload), '{}');

    expect(responder.handshakeHash, initiator.handshakeHash);

    final (responderSend, responderReceive) = await responder.split();
    final (initiatorSend, initiatorReceive) = await initiator.split();
    expect(responderSend, initiatorReceive);
    expect(responderReceive, initiatorSend);
  });

  test('decryptAndHash rejects tampered ciphertext', () async {
    final serverStatic = await newX25519KeyPair();
    final clientStatic = await newX25519KeyPair();
    final serverStaticPub = await extractPublicKeyBytes(serverStatic);
    final clientStaticPub = await extractPublicKeyBytes(clientStatic);
    final prologue = utf8.encode('prologue');

    final initiator = _FakeInitiator(serverStatic, clientStaticPub);
    final responder = KKpsk2ResponderHandshake(
      localStatic: clientStatic,
      remoteStaticPublicKey: serverStaticPub,
    );
    await initiator.initialize(prologue);
    await responder.initialize(prologue);

    final message1 = await initiator.writeMessage1(utf8.encode('{}'));
    message1[message1.length - 1] ^= 0xFF; // flip a bit in the auth tag
    expect(() => responder.readMessage1(message1), throwsA(anything));
  });

  test('noiseHkdf matches hand-computed HMAC chain for 2 outputs', () async {
    final chainingKey = Uint8List.fromList(List.generate(32, (i) => i));
    const ikm = [1, 2, 3, 4];
    final outputs = await noiseHkdf(chainingKey, ikm, 2);

    final hmac = Hmac.sha256();
    final tempKeyMac = await hmac.calculateMac(ikm, secretKey: SecretKey(chainingKey));
    final tempKey = SecretKey(tempKeyMac.bytes);
    final expectedOutput1 = (await hmac.calculateMac([0x01], secretKey: tempKey)).bytes;
    final expectedOutput2 =
        (await hmac.calculateMac([...expectedOutput1, 0x02], secretKey: tempKey)).bytes;

    expect(outputs[0], expectedOutput1);
    expect(outputs[1], expectedOutput2);
  });
}
