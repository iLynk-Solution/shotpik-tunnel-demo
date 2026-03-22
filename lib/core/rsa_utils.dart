import 'package:encrypt/encrypt.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:flutter/foundation.dart';

class RSAUtils {
  static const String defaultPrivateKey = """-----BEGIN RSA PRIVATE KEY-----
....
-----END RSA PRIVATE KEY-----""";

  /// Verifies a RSA-SHA256 signature
  /// [publicKeyPem] is the PEM formatted public key
  /// [data] is the raw string that was signed
  /// [signatureBase64] is the base64 encoded signature
  static bool verifySHA256Signature(
    String publicKeyPem,
    String data,
    String signatureBase64,
  ) {
    try {
      // 1. Ensure the key has proper PEM headers if missing
      String pem = publicKeyPem;
      if (!pem.contains('-----BEGIN PUBLIC KEY-----')) {
        pem = '-----BEGIN PUBLIC KEY-----\n$pem\n-----END PUBLIC KEY-----';
      }

      final parser = RSAKeyParser();
      final RSAPublicKey publicKey = parser.parse(pem) as RSAPublicKey;

      final signer = Signer(
        RSASigner(RSASignDigest.SHA256, publicKey: publicKey),
      );

      return signer.verify64(data, signatureBase64);
    } catch (e) {
      debugPrint("RSA_VERIFY_ERROR: $e");
      return false;
    }
  }

  /// Signs data using RSA-SHA256
  /// [privateKeyPem] is the PEM formatted private key
  /// [data] is the raw string to be signed
  static String signSHA256(String privateKeyPem, String data) {
    try {
      String pem = privateKeyPem;
      if (!pem.contains('-----BEGIN RSA PRIVATE KEY-----')) {
        pem =
            '-----BEGIN RSA PRIVATE KEY-----\n$pem\n-----END RSA PRIVATE KEY-----';
      }

      final privKey = RSAKeyParser().parse(pem) as RSAPrivateKey;

      // The Signer class in encrypt package is actually for signing.
      final rsaSigner = Signer(
        RSASigner(RSASignDigest.SHA256, privateKey: privKey),
      );
      return rsaSigner.sign(data).base64;
    } catch (e) {
      debugPrint("RSA_SIGN_ERROR: $e");
      return "";
    }
  }
}
