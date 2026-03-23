import 'dart:io';
import 'package:flutter/foundation.dart';

class AppConfig {
  /// The RSA Public Key used for verification.
  static String rsaPublicKey = const String.fromEnvironment(
    'RSA_PUBLIC_KEY',
    defaultValue: '',
  );

  /// The RSA Private Key used for signing.
  static String rsaPrivateKey = const String.fromEnvironment(
    'RSA_PRIVATE_KEY',
    defaultValue: '',
  );

  /// Automatically attempt to load keys from local files if not provided by environment
  static Future<void> loadFromFiles() async {
    try {
      debugPrint("APP_CONFIG: Current working directory: ${Directory.current.path}");
      if (rsaPublicKey.isEmpty) {
        final pubFile = File('public_key.pem');
        if (await pubFile.exists()) {
          rsaPublicKey = await pubFile.readAsString();
          debugPrint("APP_CONFIG: Loaded RSA Public Key from public_key.pem");
        } else {
          debugPrint("APP_CONFIG: public_key.pem NOT FOUND at ${pubFile.absolute.path}");
        }
      }

      if (rsaPrivateKey.isEmpty) {
        final privFile = File('private_key.pem');
        if (await privFile.exists()) {
          rsaPrivateKey = await privFile.readAsString();
          debugPrint("APP_CONFIG: Loaded RSA Private Key from private_key.pem");
        } else {
          debugPrint("APP_CONFIG: private_key.pem NOT FOUND at ${privFile.absolute.path}");
        }
      }
    } catch (e) {
      debugPrint("APP_CONFIG_LOAD_ERROR: $e");
    }
  }
}
