import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import '../domain/tunnel_models.dart';

class TunnelApiService {
  final Map<String, SharedFolderData> sharedFolders;
  final Future<String?> Function(String id, String name, String nameUrl, String path) onAddFolder;
  final Future<void> Function() onStartService;
  final Future<void> Function(String token) onUpdateConfig;
  final Function(String) onLog;

  TunnelApiService({
    required this.sharedFolders,
    required this.onLog,
    required this.onAddFolder,
    required this.onStartService,
    required this.onUpdateConfig,
  });

  String _generateUuid() {
    final random = Random();
    String generateByte() => random.nextInt(256).toRadixString(16).padLeft(2, '0');
    return '${generateByte()}${generateByte()}${generateByte()}${generateByte()}-'
        '${generateByte()}${generateByte()}-'
        '4${generateByte().substring(1)}-'
        '${(random.nextInt(4) + 8).toRadixString(16)}${generateByte().substring(1)}-'
        '${generateByte()}${generateByte()}${generateByte()}${generateByte()}${generateByte()}${generateByte()}';
  }

  Future<void> handleRequest(HttpRequest request) async {
    final requestPath = Uri.decodeComponent(request.uri.path);
    
    if (request.method == 'POST' && requestPath == '/api/v1/files') {
      await _handleListFiles(request);
    } else if (requestPath == '/api/v1/tunnel/create') {
      await _handleCreateTunnel(request);
    } else if (requestPath == '/api/v1/tunnel/list') {
      await _handleListTunnels(request);
    } else if (request.method == 'POST' && requestPath == '/api/v1/config') {
      await _handleConfig(request);
    } else if (request.method == 'POST' && requestPath == '/api/v1/start-service') {
      await _handleStartService(request);
    } else if (request.method == 'GET' && requestPath == '/api/v1/status') {
      await _handleStatus(request);
    } else {
      _sendJsonResponse(request, {"success": false, "message": "Endpoint not found"}, status: 404);
    }
  }

  Future<void> _handleStatus(HttpRequest request) async {
    _sendJsonResponse(request, {
      "success": true,
      "service_running": true,
      "shared_count": sharedFolders.length,
    });
  }

  Future<void> _handleStartService(HttpRequest request) async {
    try {
      await onStartService();
      _sendJsonResponse(request, {"success": true, "message": "Service start triggered"});
    } catch (e) {
      _sendJsonResponse(request, {"success": false, "message": e.toString()}, status: 500);
    }
  }

  Future<void> _handleCreateTunnel(HttpRequest request) async {
    try {
      final content = await utf8.decoder.bind(request).join();
      if (content.isEmpty) {
        _sendJsonResponse(request, {"success": false, "message": "Empty body"}, status: 400);
        return;
      }

      final body = jsonDecode(content);
      String? name = body['name'];
      String? nameUrl = body['nameUrl'];
      final String? path = body['path'];

      if (path == null || path.isEmpty) {
        _sendJsonResponse(request, {"success": false, "message": "Missing 'path'"}, status: 400);
        return;
      }

      if (name == null || name.isEmpty) {
        name = "album_${DateTime.now().millisecondsSinceEpoch}";
      }

      if (nameUrl == null || nameUrl.isEmpty) {
        // Fallback to stylized name if nameUrl is missing
        nameUrl = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
        if (nameUrl.isEmpty) nameUrl = "album_${_generateUuid().substring(0, 8)}";
      }

      // nameUrl MUST be unique as it's used for routing
      bool exists = sharedFolders.values.any((f) => f.nameUrl == nameUrl);
      if (exists) {
        _sendJsonResponse(request, {
          "success": false, 
          "message": "Error: nameUrl already exists: $nameUrl"
        }, status: 409);
        return;
      }

      final String id = _generateUuid();
      final result = await onAddFolder(id, name, nameUrl, path);
      if (result != null && result.startsWith("Error:")) {
        _sendJsonResponse(request, {"success": false, "message": result}, status: 400);
      } else {
        String fullUrl = result ?? "";
        // result is the base tunnel URL, we append the nameUrl
        if (fullUrl.isNotEmpty) {
          if (!fullUrl.endsWith("/")) fullUrl += "/";
          fullUrl += "$nameUrl/"; 
        }

        _sendJsonResponse(request, {
          "success": true, 
          "id": id,
          "name": name,
          "nameUrl": nameUrl,
          "url": fullUrl,
          "message": "Tunnel created successfully"
        });
      }
    } catch (e) {
      onLog("API Create Tunnel Error: $e");
      _sendJsonResponse(request, {"success": false, "message": e.toString()}, status: 500);
    }
  }

  Future<void> _handleListTunnels(HttpRequest request) async {
    final list = sharedFolders.values.map((f) => {
      "id": f.id,
      "name": f.name,
      "nameUrl": f.nameUrl,
      "path": f.localPath,
      "url": f.tunnelUrl,
      "status": f.isConnecting ? "connecting" : (f.tunnelUrl != null ? "online" : "offline"),
    }).toList();
    _sendJsonResponse(request, {"success": true, "data": list});
  }

  Future<void> _handleListFiles(HttpRequest request) async {
    try {
      final content = await utf8.decoder.bind(request).join();
      if (content.isEmpty) {
         _sendJsonResponse(request, {"success": false, "message": "Empty body"}, status: 400);
         return;
      }
      
      final body = jsonDecode(content);
      final String targetPath = body['path'] ?? "";

      if (targetPath.isEmpty || targetPath == "/") {
        final list = sharedFolders.values.map((f) => {
          "id": f.id,
          "name": f.name,
          "nameUrl": f.nameUrl,
          "type": "folder",
          "path": f.nameUrl,
        }).toList();
        _sendJsonResponse(request, {"success": true, "data": list});
        return;
      }

      final segments = p.split(targetPath).where((s) => s != "/" && s.isNotEmpty).toList();
      final virtualName = segments[0];

      if (!sharedFolders.containsKey(virtualName)) {
        _sendJsonResponse(request, {"success": false, "message": "Album not found: $virtualName"}, status: 404);
        return;
      }

      final folder = sharedFolders[virtualName]!;
      final subPathInFolder = p.joinAll(segments.sublist(1));
      final fullPath = p.join(folder.localPath, subPathInFolder);

      final entityType = FileSystemEntity.typeSync(fullPath);
      if (entityType != FileSystemEntityType.directory) {
        _sendJsonResponse(request, {"success": false, "message": "Directory not found"}, status: 404);
        return;
      }

      final entities = await Directory(fullPath).list().toList();
      final data = entities.map((e) {
        final name = p.basename(e.path);
        final isDir = e is Directory;
        final relPath = p.join(targetPath, name);
        final item = <String, dynamic>{
          "name": name,
          "type": isDir ? "folder" : "file",
          "path": relPath,
        };
        if (!isDir && e is File) {
          item["size"] = e.lengthSync();
        }
        return item;
      }).where((item) => !item["name"].toString().startsWith('.')).toList();

      _sendJsonResponse(request, {"success": true, "data": data});
    } catch (e) {
      onLog("API Error: $e");
      _sendJsonResponse(request, {"success": false, "message": e.toString()}, status: 500);
    }
  }

  Future<void> _handleConfig(HttpRequest request) async {
    try {
      // 1. Try to get token from Header (Safer)
      String? token = request.headers.value('X-Main-Tunnel-Token');
      
      // 2. Fallback to Body (for compatibility)
      if (token == null) {
        final content = await utf8.decoder.bind(request).join();
        if (content.isNotEmpty) {
          final body = jsonDecode(content);
          token = body['main_tunnel_token']?.toString();
        }
      }

      if (token != null && token.isNotEmpty) {
        onLog("Config updated: New Main Tunnel Token received via ${request.headers.value('X-Main-Tunnel-Token') != null ? 'Header' : 'Body'}.");
        await onUpdateConfig(token);
        _sendJsonResponse(request, {"success": true, "message": "Config updated successfully"});
      } else {
        _sendJsonResponse(request, {"success": false, "message": "Missing token. Use Header 'X-Main-Tunnel-Token' or Body 'main_tunnel_token'"}, status: 400);
      }
    } catch (e) {
      onLog("Config update error: Internal Failure");
      _sendJsonResponse(request, {"success": false, "message": "Internal Server Error"}, status: 500);
    }
  }

  void _sendJsonResponse(HttpRequest request, Map<String, dynamic> json, {int status = 200}) {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(json));
  }
}
