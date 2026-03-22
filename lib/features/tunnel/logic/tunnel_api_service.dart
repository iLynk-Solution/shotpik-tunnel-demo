import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import '../../../core/rsa_utils.dart';
import '../domain/tunnel_models.dart';

class TunnelApiService {
  final Map<String, SharedFolderData> sharedFolders;
  final String? mainTunnelUrl;
  final Future<String?> Function(String id, String name, String namePath, String path) onAddFolder;
  final Future<void> Function(String id) onRemoveFolder;
  final Future<void> Function() onStartService;
  final Future<void> Function(String id) onRefreshTunnel;
  final Future<void> Function(List<String> paths) onUpdateWhitelist;
  final Set<String> whitelist;
  final Function(String) onLog;

  TunnelApiService({
    required this.sharedFolders,
    required this.whitelist,
    this.mainTunnelUrl,
    required this.onLog,
    required this.onAddFolder,
    required this.onRemoveFolder,
    required this.onStartService,
    required this.onRefreshTunnel,
    required this.onUpdateWhitelist,
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

  Future<void> handleRequest(HttpRequest request, String bodyString) async {
    final requestPath = Uri.decodeComponent(request.uri.path);
    onLog("Routing API: Method=${request.method}, Path=$requestPath");
    
    if (requestPath == '/api/v1/auth/verify') {
      if (request.method != 'POST') return _sendMethodNotAllowed(request);
      await _handleVerifyAuth(request);
      return;
    }

    if (requestPath == '/api/v1/auth/sign') {
      if (request.method != 'POST') return _sendMethodNotAllowed(request);
      await _handleSignAuth(request, bodyString);
      return;
    }

    if (requestPath == '/api/v1/files') {
      if (request.method != 'POST') return _sendMethodNotAllowed(request);
      await _handleListFiles(request, bodyString);
    } else if (requestPath == '/api/v1/create-folder') {
      if (request.method != 'POST') return _sendMethodNotAllowed(request);
      await _handleCreateTunnel(request, bodyString);
    } else if (requestPath == '/api/v1/tunnel/list') {
      if (request.method != 'POST') return _sendMethodNotAllowed(request);
      await _handleListTunnels(request);
    } else if (requestPath == '/api/v1/tunnel/refresh') {
      if (request.method != 'POST') return _sendMethodNotAllowed(request);
      await _handleRefreshTunnel(request, bodyString);
    } else if (requestPath == '/api/v1/tunnel/delete') {
      if (request.method != 'POST' && request.method != 'DELETE') return _sendMethodNotAllowed(request);
      await _handleDeleteTunnel(request, bodyString);
    } else if (requestPath == '/api/v1/whitelist') {
      if (request.method != 'GET') return _sendMethodNotAllowed(request);
      await _handleWhitelist(request);
    } else if (requestPath == '/api/v1/whitelist/add') {
      if (request.method != 'POST') return _sendMethodNotAllowed(request);
      await _handleWhitelistAdd(request, bodyString);
    } else if (requestPath == '/api/v1/whitelist/delete') {
      if (request.method != 'DELETE' && request.method != 'POST') return _sendMethodNotAllowed(request);
      await _handleWhitelistDelete(request, bodyString);
    } else if (requestPath == '/api/v1/whitelist/clear') {
      if (request.method != 'DELETE' && request.method != 'POST') return _sendMethodNotAllowed(request);
      await _handleWhitelistClear(request);
    } else if (requestPath == '/api/v1/start-service') {
      if (request.method != 'POST') return _sendMethodNotAllowed(request);
      await _handleStartService(request);
    } else if (requestPath == '/api/v1/status') {
      if (request.method != 'GET') return _sendMethodNotAllowed(request);
      await _handleStatus(request);
    } else {
      _sendJsonResponse(request, {"success": false, "message": "Endpoint not found"}, status: 404);
    }
  }

  Future<void> _handleVerifyAuth(HttpRequest request) async {
    // If this handler is reached, it means the RSA Signature Verification in TunnelPage.dart has already passed.
    _sendJsonResponse(request, {
      "success": true,
      "message": "RSA Signature is VALID!",
      "details": {
        "status": "Verified",
        "algorithm": "RSA-SHA256",
        "checkpoint": "Backend Server -> Agent Communication OK"
      }
    });
  }

  void _sendMethodNotAllowed(HttpRequest request) {
    _sendJsonResponse(request, {
      "success": false,
      "message": "Method ${request.method} not allowed for this endpoint"
    }, status: 405);
  }

  Future<void> _handleStatus(HttpRequest request) async {
    _sendJsonResponse(request, {
      "success": true,
      "service_running": true,
      "shared_count": sharedFolders.length,
      "whitelist": whitelist.toList(),
    });
  }

  // _handleListFiles was moved here but I will remove this duplicate block

  Future<void> _handleWhitelist(HttpRequest request) async {
    try {
      final List<Map<String, dynamic>> results = [];
      for (final namePathItem in whitelist) {
        // Find the folder data to get its current URL
        SharedFolderData? folder;
        for (var f in sharedFolders.values) {
          if (f.namePath == namePathItem) {
            folder = f;
            break;
          }
        }
        results.add({
          "id": folder?.id ?? "",
          "name": folder?.name ?? "",
          "name_path": namePathItem,
          "url": folder?.tunnelUrl ?? "",
          "created_at": folder?.createdAt.toIso8601String() ?? "",
        });
      }
      
      _sendJsonResponse(request, {
        "success": true,
        "data": results,
      });
    } catch (e) {
      onLog("Whitelist error: $e");
      _sendJsonResponse(request, {"success": false, "message": "Internal Server Error"}, status: 500);
    }
  }

  Future<void> _handleWhitelistAdd(HttpRequest request, String bodyString) async {
    try {
      if (request.method != 'POST') {
        _sendJsonResponse(
          request,
          {"success": false, "message": "Method not allowed"},
          status: 405,
        );
        return;
      }

      final content = bodyString;
      if (content.isEmpty) {
        _sendJsonResponse(
          request,
          {"success": false, "message": "Empty body"},
          status: 400,
        );
        return;
      }

      final body = jsonDecode(content);
      String? id = body['id']?.toString();

      if (id == null || id.isEmpty) {
        _sendJsonResponse(request, {"success": false, "message": "Missing 'id'"}, status: 400);
        return;
      }

      SharedFolderData? foundFolder = sharedFolders[id];

      // 1. Try resolving by URL
      if (foundFolder == null) {
        // Fallback: Check if it's a namePath
        for (var f in sharedFolders.values) {
          if (f.namePath == id) {
            foundFolder = f;
            break;
          }
        }
      }

      if (foundFolder == null) {
        _sendJsonResponse(
          request,
          {"success": false, "message": "Folder/Tunnel not found"},
          status: 404,
        );
        return;
      }

      // Add to current whitelist
      final List<String> currentWhitelist = whitelist.toList();
      
      if (!currentWhitelist.contains(foundFolder.namePath)) {
        currentWhitelist.add(foundFolder.namePath);
        await onUpdateWhitelist(currentWhitelist);

        _sendJsonResponse(request, {
          "success": true,
          "message": "Added to whitelist",
          "data": {
            "id": foundFolder.id,
            "name": foundFolder.name,
            "name_path": foundFolder.namePath,
            "url": foundFolder.tunnelUrl ?? "",
            "created_at": foundFolder.createdAt.toIso8601String(),
          }
        });
      } else {
        _sendJsonResponse(request, {
          "success": true,
          "message": "Folder is already in whitelist",
        });
      }
    } catch (e) {
      onLog("Whitelist Add error: $e");
      _sendJsonResponse(
        request,
        {"success": false, "message": "Internal Server Error"},
        status: 500,
      );
    }
  }

  Future<void> _handleWhitelistDelete(HttpRequest request, String bodyString) async {
    try {
      final content = bodyString;
      if (content.isEmpty) {
        _sendJsonResponse(request, {"success": false, "message": "Empty body"}, status: 400);
        return;
      }
      final body = jsonDecode(content);
      final id = body['id']?.toString();
      
      if (id == null || id.isEmpty) {
        _sendJsonResponse(request, {"success": false, "message": "Missing 'id'"}, status: 400);
        return;
      }

      String namePathToRemove = "";
      
      // 1. Check if it's a folder ID
      SharedFolderData? folder = sharedFolders[id];
      if (folder != null) {
        namePathToRemove = folder.namePath;
      } else {
        // 2. Check if it matches a namePath in whitelist
        if (whitelist.contains(id)) {
          namePathToRemove = id;
        } else {
          // 3. Check if it's a namePath of any folder
          for (var f in sharedFolders.values) {
            if (f.namePath == id) {
              namePathToRemove = f.namePath;
              break;
            }
          }
        }
      }

      if (namePathToRemove.isEmpty || !whitelist.contains(namePathToRemove)) {
        _sendJsonResponse(request, {"success": false, "message": "Item not found in whitelist"}, status: 404);
        return;
      }

      final List<String> currentWhitelist = whitelist.toList();
      currentWhitelist.remove(namePathToRemove);
      await onUpdateWhitelist(currentWhitelist);

      _sendJsonResponse(request, {"success": true, "message": "Removed from whitelist"});
    } catch (e) {
      _sendJsonResponse(request, {"success": false, "message": e.toString()}, status: 500);
    }
  }

  Future<void> _handleWhitelistClear(HttpRequest request) async {
    try {
      await onUpdateWhitelist([]);
      _sendJsonResponse(request, {"success": true, "message": "Whitelist cleared successfully"});
    } catch (e) {
      _sendJsonResponse(request, {"success": false, "message": e.toString()}, status: 500);
    }
  }

  Future<void> _handleStartService(HttpRequest request) async {
    try {
      await onStartService();
      _sendJsonResponse(request, {"success": true, "message": "Service start triggered"});
    } catch (e) {
      _sendJsonResponse(request, {"success": false, "message": e.toString()}, status: 500);
    }
  }

  Future<void> _handleCreateTunnel(HttpRequest request, String bodyString) async {
    try {
      final content = bodyString;
      if (content.isEmpty) {
        _sendJsonResponse(request, {"success": false, "message": "Empty body"}, status: 400);
        return;
      }

      final body = jsonDecode(content);
      String? name = body['name'];
      String? namePath = body['name_path'] ?? body['nameUrl'];
      final String? path = body['path'];

      if (path == null || path.isEmpty) {
        _sendJsonResponse(request, {"success": false, "message": "Missing 'path'"}, status: 400);
        return;
      }

      if (name == null || name.isEmpty) {
        name = "album_${DateTime.now().millisecondsSinceEpoch}";
      }

      if (namePath == null || namePath.isEmpty) {
        // Fallback to stylized name if namePath is missing
        namePath = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
        if (namePath.isEmpty) namePath = "album_${_generateUuid().substring(0, 8)}";
      }

      // namePath MUST be unique as it's used for routing
      bool exists = sharedFolders.values.any((f) => f.namePath == namePath);
      if (exists) {
        _sendJsonResponse(request, {
          "success": false, 
          "message": "Error: name_path already exists: $namePath"
        }, status: 409);
        return;
      }

      final String id = _generateUuid();
      final result = await onAddFolder(id, name, namePath, path);
      if (result != null && result.startsWith("Error:")) {
        _sendJsonResponse(request, {"success": false, "message": result}, status: 400);
      } else {
        String fullUrl = result ?? "";
        
        _sendJsonResponse(request, {
          "success": true, 
          "data": {
            "id": id,
            "name": name,
            "name_path": namePath,
            "type": "folder",
            "method": "POST",
            "url": fullUrl,
            "created_at": DateTime.now().toIso8601String(),
            "message": "Tunnel created successfully"
          }
        });
      }
    } catch (e) {
      onLog("API Create Tunnel Error: $e");
      _sendJsonResponse(request, {"success": false, "message": e.toString()}, status: 500);
    }
  }

  Future<void> _handleSignAuth(HttpRequest request, String bodyString) async {
    try {
      // Robustly minify the JSON before signing to ensure a standard signature
      final dynamic decoded = jsonDecode(bodyString);
      final String minifiedBody = jsonEncode(decoded);
      
      final String signature = RSAUtils.signSHA256(RSAUtils.defaultPrivateKey, minifiedBody);
      
      _sendJsonResponse(request, {
        "success": true,
        "signature": signature,
        "message": "Signature generated for MINIFIED JSON.",
        "signed_body": minifiedBody,
        "received_body": bodyString,
      });
    } catch (e) {
      _sendJsonResponse(request, {
        "success": false, 
        "message": "Invalid JSON in request body: ${e.toString()}"
      }, status: 400);
    }
  }

  Future<void> _handleListTunnels(HttpRequest request) async {
    final list = sharedFolders.values.map((f) => {
      "id": f.id,
      "name": f.name,
      "name_path": f.namePath,
      "type": "folder",
      "method": "POST",
      "path": f.localPath,
      "url": f.tunnelUrl,
      "status": f.isConnecting ? "connecting" : (f.tunnelUrl != null ? "online" : "offline"),
      "created_at": f.createdAt.toIso8601String(),
    }).toList();
    _sendJsonResponse(request, {"success": true, "data": list});
  }

  Future<void> _handleRefreshTunnel(HttpRequest request, String bodyString) async {
    try {
      final content = bodyString;
      if (content.isEmpty) {
        _sendJsonResponse(request, {"success": false, "message": "Empty body"}, status: 400);
        return;
      }
      final body = jsonDecode(content);
      final id = body['id']?.toString();

      if (id == null || id.isEmpty) {
        _sendJsonResponse(request, {"success": false, "message": "Missing 'id'"}, status: 400);
        return;
      }

      SharedFolderData? folder = sharedFolders[id];
      if (folder == null) {
        for (var f in sharedFolders.values) {
          if (f.namePath == id) {
            folder = f;
            break;
          }
        }
      }

      if (folder == null) {
        _sendJsonResponse(request, {"success": false, "message": "Tunnel not found"}, status: 404);
        return;
      }

      await onRefreshTunnel(folder.id);
      _sendJsonResponse(request, {
        "success": true, 
        "message": "Tunnel refresh triggered",
        "data": {
          "id": folder.id,
          "name": folder.name,
          "name_path": folder.namePath,
          "type": "folder",
          "method": "POST",
          "path": folder.localPath,
          "url": folder.tunnelUrl,
        }
      });
    } catch (e) {
      _sendJsonResponse(request, {"success": false, "message": e.toString()}, status: 500);
    }
  }

  Future<void> _handleDeleteTunnel(HttpRequest request, String bodyString) async {
    try {
      final content = bodyString;
      if (content.isEmpty) {
        _sendJsonResponse(request, {"success": false, "message": "Empty body"}, status: 400);
        return;
      }
      final body = jsonDecode(content);
      final id = body['id']?.toString();

      if (id == null || id.isEmpty) {
        _sendJsonResponse(request, {"success": false, "message": "Missing 'id'"}, status: 400);
        return;
      }

      SharedFolderData? folder = sharedFolders[id];
      if (folder == null) {
        // Fallback: search by namePath
        for (var f in sharedFolders.values) {
          if (f.namePath == id) {
            folder = f;
            break;
          }
        }
      }

      if (folder == null) {
        _sendJsonResponse(request, {"success": false, "message": "Tunnel not found"}, status: 404);
        return;
      }

      await onRemoveFolder(folder.id);
      _sendJsonResponse(request, {"success": true, "message": "Tunnel deleted successfully"});
    } catch (e) {
      _sendJsonResponse(request, {"success": false, "message": e.toString()}, status: 404);
    }
  }

  Future<void> _handleListFiles(HttpRequest request, String bodyString) async {
    try {
      final content = bodyString;
      if (content.isEmpty) {
         _sendJsonResponse(request, {"success": false, "message": "Empty body"}, status: 400);
         return;
      }
      
      final body = jsonDecode(content);
      // Support both 'id' and 'path' from body as the source path
      String? id = body['path']?.toString() ?? body['id']?.toString();

      // If still empty, return album list
      if (id == null || id.isEmpty) {
        final list = sharedFolders.values.map((f) => {
          "id": f.id,
          "name": f.name,
          "name_path": f.namePath,
          "type": "folder",
          "path": f.namePath,
          "url": f.tunnelUrl,
          "status": f.isConnecting ? "connecting" : (f.tunnelUrl != null ? "online" : "offline"),
        }).toList();
        _sendJsonResponse(request, {"success": true, "data": list});
        return;
      }

      onLog("API Files: Request for ID/Path: $id");
      onLog("API Files: Currently shared: ${sharedFolders.values.map((f) => f.localPath).toList()}");

      SharedFolderData? foundFolder = sharedFolders[id];
      String subPathInFolder = "";

      // 0. Try resolving by absolute local path
      if (foundFolder == null) {
        for (var f in sharedFolders.values) {
          // Normalize both for comparison
          String local = p.normalize(f.localPath);
          String requested = p.normalize(id!);
          
          if (requested.startsWith(local)) {
            foundFolder = f;
            subPathInFolder = p.relative(requested, from: local);
            if (subPathInFolder == ".") subPathInFolder = "";
            onLog("API Files: Matched by local path! Folder: ${f.name}, SubPath: $subPathInFolder");
            break;
          }
        }
      }

      // 1. Try resolving by URL
      if (foundFolder == null && id.startsWith('http')) {
        for (var f in sharedFolders.values) {
          if (f.tunnelUrl != null) {
            String baseUrl = f.tunnelUrl!;
            if (baseUrl.endsWith('/')) baseUrl = baseUrl.substring(0, baseUrl.length - 1);
            
            if (id.startsWith(baseUrl)) {
              foundFolder = f;
              subPathInFolder = id.substring(baseUrl.length);
              if (subPathInFolder.startsWith('/')) subPathInFolder = subPathInFolder.substring(1);
              break;
            }
          }
        }
      }

      // 2. Try resolving by path logic
      if (foundFolder == null) {
        final segments = p.split(id).where((s) => s != "/" && s.isNotEmpty).toList();
        if (segments.isNotEmpty) {
          final virtualName = segments[0];
          foundFolder = sharedFolders[virtualName];
          if (foundFolder == null) {
            for (var f in sharedFolders.values) {
              if (f.namePath == virtualName || f.name == virtualName) {
                foundFolder = f;
                break;
              }
            }
          }
          if (foundFolder != null) {
            subPathInFolder = p.joinAll(segments.sublist(1));
          }
        }
      }

      if (foundFolder == null) {
        String msg = "Access denied: Folder or Tunnel not found";
        if (id.startsWith('http')) msg = "Tunnel URL not recognized or offline: $id";
        _sendJsonResponse(request, {"success": false, "message": msg}, status: 404);
        return;
      }

      final fullPath = p.join(foundFolder.localPath, subPathInFolder);

      final entityType = FileSystemEntity.typeSync(fullPath);
      if (entityType != FileSystemEntityType.directory) {
        _sendJsonResponse(request, {"success": false, "message": "Directory not found"}, status: 404);
        return;
      }


      final entities = await Directory(fullPath).list(recursive: true).toList();
      final List<Map<String, dynamic>> data = [];

      for (final e in entities) {
        final name = p.basename(e.path);
        if (name.startsWith('.')) continue;

        final stat = FileSystemEntity.typeSync(e.path);
        final isDir = stat == FileSystemEntityType.directory;
        final isFile = stat == FileSystemEntityType.file;
        
        if (!isDir && !isFile) continue;

        // Calculate relative path from the root of the shared folder
        final relPath = p.relative(e.path, from: foundFolder.localPath);
        final fStat = await e.stat();
        
        String typeAttr = isDir ? "folder" : "file";
        if (isFile) {
          final ext = p.extension(e.path).toLowerCase();
          final imageExts = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic'];
          if (imageExts.contains(ext)) {
            typeAttr = "image";
          }
        }

        final item = <String, dynamic>{
          "name": name,
          "type": typeAttr,
          "method": isDir ? "POST" : "GET",
          "path": relPath,
          "size": isDir ? 0 : fStat.size,
          "created_at": fStat.modified.toIso8601String(),
        };

        if (foundFolder.tunnelUrl != null) {
          String url = foundFolder.tunnelUrl!;
          if (!url.endsWith('/')) url += '/';
          item["url"] = url + relPath.replaceAll('\\', '/');
          if (isDir) item["url"] += '/';
        }

        data.add(item);
      }

      _sendJsonResponse(request, {"success": true, "data": data});
    } catch (e) {
      onLog("API Error: $e");
      _sendJsonResponse(request, {"success": false, "message": e.toString()}, status: 500);
    }
  }

  void _sendJsonResponse(HttpRequest request, Map<String, dynamic> response, {int status = 200}) {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    
    // Add CORS headers for web compatibility
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type, Authorization');

    request.response.write(jsonEncode(response));
  }
}
