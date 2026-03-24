import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

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

  /// Log of the key loading process to help debugging in release builds
  static List<String> loadLogs = [];

  /// Automatically attempt to load keys from local files or assets if not provided by environment
  static Future<void> loadFromFiles() async {
    loadLogs.clear();
    try {
      final String cwd = Directory.current.path;
      loadLogs.add("APP_CONFIG: CWD: $cwd");

      // Potential locations for the .pem files (prioritize external files)
      final List<String> searchDirs = [
        cwd, // Current working directory
      ];

      // On MacOS, if we're in a bundle, look next to the .app bundle as well
      if (Platform.isMacOS) {
        final String exePath = Platform.resolvedExecutable;
        final String exeDir = p.dirname(exePath);
        searchDirs.add(exeDir); // ShotpikAgent.app/Contents/MacOS/

        // ShotpikAgent.app is usually 3 levels up from the binary
        final String bundleDir = p.dirname(p.dirname(p.dirname(exePath)));
        final String bundleParentDir = p.dirname(bundleDir);
        searchDirs.add(bundleParentDir); // The folder containing ShotpikAgent.app
        loadLogs.add("APP_CONFIG: Bundle Parent: $bundleParentDir");
      }

      // --- PUBLIC KEY ---
      if (rsaPublicKey.isEmpty) {
        // 1. Check external files first
        rsaPublicKey = await _findAndReadFile('public_key.pem', searchDirs);
        
        // 2. Fallback to assets if not found externally
        if (rsaPublicKey.isEmpty) {
          rsaPublicKey = await _loadFromAssets('assets/keys/public_key.pem');
          if (rsaPublicKey.isNotEmpty) {
            loadLogs.add("APP_CONFIG: Loaded Public Key from App Assets");
          }
        } else {
          loadLogs.add("APP_CONFIG: Loaded Public Key from File System");
        }

        if (rsaPublicKey.isEmpty) {
          loadLogs.add("APP_CONFIG: WARNING - Public Key NOT FOUND anywhere");
        }
      } else {
        loadLogs.add("APP_CONFIG: Public Key provided via dart-define");
      }

      // --- PRIVATE KEY ---
      if (rsaPrivateKey.isEmpty) {
        // 1. Check external files first
        rsaPrivateKey = await _findAndReadFile('private_key.pem', searchDirs);

        // 2. Fallback to assets if not found externally
        if (rsaPrivateKey.isEmpty) {
          rsaPrivateKey = await _loadFromAssets('assets/keys/private_key.pem');
          if (rsaPrivateKey.isNotEmpty) {
            loadLogs.add("APP_CONFIG: Loaded Private Key from App Assets");
          }
        } else {
          loadLogs.add("APP_CONFIG: Loaded Private Key from File System");
        }

        if (rsaPrivateKey.isEmpty) {
          loadLogs.add("APP_CONFIG: WARNING - Private Key NOT FOUND anywhere");
        }
      } else {
        loadLogs.add("APP_CONFIG: Private Key provided via dart-define");
      }
    } catch (e) {
      loadLogs.add("APP_CONFIG_LOAD_ERROR: $e");
      debugPrint("APP_CONFIG_LOAD_ERROR: $e");
    }
  }

  static Future<String> _findAndReadFile(String filename, List<String> dirs) async {
    for (var dir in dirs) {
      final file = File(p.join(dir, filename));
      if (await file.exists()) {
        loadLogs.add("APP_CONFIG: Found external $filename at ${file.path}");
        return await file.readAsString();
      }
    }
    return '';
  }

  static Future<String> _loadFromAssets(String assetPath) async {
    try {
      // Use rootBundle to read bundled asset
      return await rootBundle.loadString(assetPath);
    } catch (e) {
      loadLogs.add("APP_CONFIG: Asset not found or error: $assetPath");
      return '';
    }
  }
}
