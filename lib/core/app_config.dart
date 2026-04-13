import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';
import 'package:pointycastle/asn1.dart';

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
      final List<String> searchDirs = [];
      
      // In debug mode, prioritize current folder
      if (kDebugMode) {
        try {
          final String cwd = Directory.current.path;
          searchDirs.add(cwd);
        } catch (_) {}
      }

      // On MacOS, safely try to get bundle path
      if (Platform.isMacOS) {
        try {
          final String exePath = Platform.resolvedExecutable;
          if (exePath.isNotEmpty) {
            final String exeDir = p.dirname(exePath);
            searchDirs.add(exeDir);
            
            final String contentsDir = p.dirname(exeDir);
            final String bundleDir = p.dirname(contentsDir);
            if (bundleDir.length > 1) {
              searchDirs.add(p.dirname(bundleDir));
            }
          }
        } catch (_) {}
      }

      // Safe loading defaults
      rsaPublicKey = "";
      rsaPrivateKey = "";

      // 1. Try Assets FIRST (Vì assets luôn an toàn nhất trong bundle)
      try {
        rsaPublicKey = await _loadFromAssets('assets/keys/public_key.pem');
        rsaPrivateKey = await _loadFromAssets('assets/keys/private_key.pem');
      } catch (_) {}

      // 2. ONLY check files if assets failed and we have search dirs
      if (rsaPublicKey.isEmpty) {
        rsaPublicKey = await _findAndReadFile('public_key.pem', searchDirs);
      }
      if (rsaPrivateKey.isEmpty) {
        rsaPrivateKey = await _findAndReadFile('private_key.pem', searchDirs);
      }

      // 3. Nếu vẫn TRỐNG, tự động tạo Key mới cho máy này
      if (rsaPublicKey.isEmpty || rsaPrivateKey.isEmpty) {
        await _generateAndSaveNewKeys();
      }

    } catch (e) {
      // Tuyệt đối không để crash ở đây
      debugPrint("APP_CONFIG_SILENT_ERROR: $e");
    }
  }

  static Future<void> _generateAndSaveNewKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? savedPub = prefs.getString('auto_generated_public_key2');
      String? savedPriv = prefs.getString('auto_generated_private_key2');

      if (savedPub == null || savedPriv == null) {
        debugPrint("APP_CONFIG: Đang khởi tạo mã định danh duy nhất cho máy này (RSA 2048)...");
        
        // Tạo Key Pair 2048 bit
        final keyGen = KeyGenerator('RSA');
        keyGen.init(ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 12),
          _getSecureRandom(),
        ));

        final pair = keyGen.generateKeyPair();
        final myPublic = pair.publicKey as RSAPublicKey;
        final myPrivate = pair.privateKey as RSAPrivateKey;

        // Chuyển sang định dạng PEM
        savedPub = _encodePublicKeyToPem(myPublic);
        savedPriv = _encodePrivateKeyToPem(myPrivate);

        // Lưu lại để dùng cho các lần sau
        await prefs.setString('auto_generated_public_key2', savedPub);
        await prefs.setString('auto_generated_private_key2', savedPriv);
        
        debugPrint("APP_CONFIG: Đã tạo xong mã định danh mới.");
      }

      rsaPublicKey = savedPub;
      rsaPrivateKey = savedPriv;
      
    } catch (e, stack) {
      debugPrint("GENERATE_KEY_ERROR: $e\n$stack");
    }
  }

  static SecureRandom _getSecureRandom() {
    final secureRandom = FortunaRandom();
    final seed = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seed)));
    return secureRandom;
  }

  static String _encodePublicKeyToPem(RSAPublicKey publicKey) {
    // encode to PKCS#1
    final topLevel = ASN1Sequence();
    topLevel.add(ASN1Integer(publicKey.modulus));
    topLevel.add(ASN1Integer(publicKey.exponent));
    final dataBase64 = base64.encode(topLevel.encode());
    return "-----BEGIN RSA PUBLIC KEY-----\n$dataBase64\n-----END RSA PUBLIC KEY-----";
  }

  static String _encodePrivateKeyToPem(RSAPrivateKey privateKey) {
    // encode to PKCS#1
    final topLevel = ASN1Sequence();
    topLevel.add(ASN1Integer(BigInt.from(0))); // version
    topLevel.add(ASN1Integer(privateKey.modulus));
    topLevel.add(ASN1Integer(privateKey.publicExponent));
    topLevel.add(ASN1Integer(privateKey.privateExponent));
    topLevel.add(ASN1Integer(privateKey.p));
    topLevel.add(ASN1Integer(privateKey.q));
    topLevel.add(ASN1Integer(privateKey.privateExponent! % (privateKey.p! - BigInt.from(1))));
    topLevel.add(ASN1Integer(privateKey.privateExponent! % (privateKey.q! - BigInt.from(1))));
    topLevel.add(ASN1Integer(privateKey.q!.modInverse(privateKey.p!)));
    
    final dataBase64 = base64.encode(topLevel.encode());
    return "-----BEGIN RSA PRIVATE KEY-----\n$dataBase64\n-----END RSA PRIVATE KEY-----";
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
