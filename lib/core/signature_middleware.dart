import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'rsa_utils.dart';

/// Middleware to verify RSA-SHA256 signature from X-Signature header
Middleware signatureVerification(String publicKeyPem) {
  return (Handler innerHandler) {
    return (Request request) async {
      // 1. Skip verification for OPTIONS requests (CORS)
      if (request.method == 'OPTIONS') {
        return innerHandler(request);
      }

      // 2. Get signature from header
      final signature = request.headers['x-signature'];
      if (signature == null || signature.isEmpty) {
        return Response(
          401,
          body: jsonEncode({
            "success": false,
            "error": "UNAUTHORIZED",
            "message": "Missing X-Signature header"
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // 3. Read raw body
      final bodyString = await request.readAsString();
      
      // 4. Verify signature
      bool isValid = RSAUtils.verifySignature(
        publicKeyPem,
        bodyString,
        signature,
      );

      // Robust fallback: if verification fails, try minifying the JSON body
      if (!isValid) {
        try {
          final dynamic decoded = jsonDecode(bodyString);
          final minifiedBody = jsonEncode(decoded);
          isValid = RSAUtils.verifySignature(
            publicKeyPem,
            minifiedBody,
            signature,
          );
        } catch (_) {
          // If not valid JSON, ignore fallback
        }
      }

      if (!isValid) {
        return Response(
          401,
          body: jsonEncode({
            "success": false,
            "error": "UNAUTHORIZED"
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // 5. Recreate request with the body we already read so handlers can use it
      final updatedRequest = request.change(
        body: bodyString,
      );

      return innerHandler(updatedRequest);
    };
  };
}
