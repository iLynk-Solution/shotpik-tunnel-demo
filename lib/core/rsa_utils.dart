import 'package:encrypt/encrypt.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:flutter/foundation.dart';

class RSAUtils {
  static const String defaultPrivateKey = """-----BEGIN RSA PRIVATE KEY-----
MIICWwIBAAKBgG1oJHc0YeN9EzTO69XWcBs95U7aQtCFvuzj8V5cSBI34x/gwtws
BkSahkh0faMzKVXFJjOl+vp46YzVlnq+W3A9Hn1FnxNe3raS0bLNx7Scz3KYM9+p
9xv7cRrwzUx3rlm3QyJXGzhd3eKrHgOeVESsPr2xoRY8G/4E2qod9EJvAgMBAAEC
gYABTw2gn2/MWOKx7wfDNx2ANe1YVCQYeoEeNFve1RvHnAOLjhTGrYAlsfOJSlt2
aFZGQGWEmKe391pT5Po33a8aVIYjEptJFTG8i8e/5Lom1QCm+7e9QSICf/xzWgOJ
1Ud4Z2mbfkgjFpq8zg94Sx3TZhi9cM7KtTW3LoOzhVFagQJBANE4FQfRruXiFVZK
InnhVGMCLdqhzX3h3WqlVxTD8M6flTW1EincBQWPfinfy8YjyLsRyR3NaZSky1uf
sxCIdvUCQQCF3rPA818XacaeZGeuqSHO3kCzieq0KPTFYi92hX1aQ8Te8GExSTPB
gYY0F5Jts5TIo/avLfR9iAy1WaW9dk1TAkApdZ6dRQ0OmwW1as14L5HkaNsjVyr8
hhS1fHxMLiP7Hh6YXQBzcRlBp9TNgX7FDfRKNdUP5dPFU/7EclourYw9AkBdaTKA
ttFpovNm3qTCaV4f3VHEdb4CDHoPqR15VFhNvfAHqDAJlgy5P8oHW1NfnOl6v36I
akapuV80w+M0uvHlAkEAyKxD+PFCt/WnqfqWN0+EmSGFjigURYP1cx6vKCW5lFEq
El+Q0mtBriQNKxZIJvotnHXKb9O2ewnmRo0nSaSvRQ==
-----END RSA PRIVATE KEY-----""";

  /// Verifies a RSA-SHA256 signature
  /// [publicKeyPem] is the PEM formatted public key
  /// [data] is the raw string that was signed
  /// [signatureBase64] is the base64 encoded signature
  static bool verifySHA256Signature(String publicKeyPem, String data, String signatureBase64) {
    try {
      // 1. Ensure the key has proper PEM headers if missing
      String pem = publicKeyPem;
      if (!pem.contains('-----BEGIN PUBLIC KEY-----')) {
         pem = '-----BEGIN PUBLIC KEY-----\n$pem\n-----END PUBLIC KEY-----';
      }

      final parser = RSAKeyParser();
      final RSAPublicKey publicKey = parser.parse(pem) as RSAPublicKey;
      
      final signer = Signer(RSASigner(RSASignDigest.SHA256, publicKey: publicKey));
      
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
        pem = '-----BEGIN RSA PRIVATE KEY-----\n$pem\n-----END RSA PRIVATE KEY-----';
      }

      final privKey = RSAKeyParser().parse(pem) as RSAPrivateKey;
      
      // The Signer class in encrypt package is actually for signing.
      final rsaSigner = Signer(RSASigner(RSASignDigest.SHA256, privateKey: privKey));
      return rsaSigner.sign(data).base64;
    } catch (e) {
      debugPrint("RSA_SIGN_ERROR: $e");
      return "";
    }
  }
}
