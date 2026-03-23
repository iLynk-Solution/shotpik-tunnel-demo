import 'dart:convert';
import 'package:encrypt/encrypt.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/signers/rsa_signer.dart' as pc_signer;
import 'package:pointycastle/pointycastle.dart' as pc;
import 'package:flutter/foundation.dart';

class RSAUtils {
  /// Normalizes a PEM string by adding headers and footers if missing
  static String normalizePem(String pem, {bool isPublic = true}) {
    String p = pem.trim();
    if (isPublic) {
      if (!p.contains('BEGIN PUBLIC KEY')) {
        p = '-----BEGIN PUBLIC KEY-----\n$p\n-----END PUBLIC KEY-----';
      }
    } else {
      if (!p.contains('BEGIN PRIVATE KEY') && !p.contains('BEGIN RSA PRIVATE KEY')) {
        p = '-----BEGIN RSA PRIVATE KEY-----\n$p\n-----END RSA PRIVATE KEY-----';
      }
    }
    return p;
  }

  /// Verifies a RSA-SHA256 signature
  /// [publicKeyPem] is the PEM formatted public key
  /// [rawBody] is the raw string that was signed
  /// [signatureBase64] is the base64 encoded signature from X-Signature header
  static bool verifySignature(
    String publicKeyPem,
    String rawBody,
    String signatureBase64,
  ) {
    try {
      final pem = normalizePem(publicKeyPem, isPublic: true);
      final parser = RSAKeyParser();
      final RSAPublicKey publicKey = parser.parse(pem) as RSAPublicKey;

      final rsaVerifier = pc_signer.RSASigner(SHA256Digest(), '0609608648016503040201');
      rsaVerifier.init(false, pc.PublicKeyParameter<RSAPublicKey>(publicKey));

      final bodyBytes = Uint8List.fromList(utf8.encode(rawBody));
      final sig = pc.RSASignature(base64.decode(signatureBase64));
      
      return rsaVerifier.verifySignature(bodyBytes, sig);
    } catch (e) {
      debugPrint("RSA_VERIFY_ERROR: $e");
      return false;
    }
  }

  /// Signs data using RSA-SHA256
  /// [privateKeyPem] is the PEM formatted private key
  /// [rawBody] is the raw string to be signed
  static String signBody(String privateKeyPem, String rawBody) {
    try {
      final pem = normalizePem(privateKeyPem, isPublic: false);
      final privKey = RSAKeyParser().parse(pem) as RSAPrivateKey;

      final rsaSigner = pc_signer.RSASigner(SHA256Digest(), '0609608648016503040201');
      rsaSigner.init(true, pc.PrivateKeyParameter<RSAPrivateKey>(privKey));

      final bodyBytes = Uint8List.fromList(utf8.encode(rawBody));
      final signature = rsaSigner.generateSignature(bodyBytes);
      
      return base64.encode(signature.bytes);
    } catch (e) {
      debugPrint("RSA_SIGN_ERROR: $e");
      return "";
    }
  }
}
