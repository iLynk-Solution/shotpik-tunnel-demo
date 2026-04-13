import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;

class TunnelApiService {
  final Set<String> whitelist;
  final String? mainTunnelUrl;
  final Function(String) onLog;
  final Future<void> Function() onStartService;
  final Future<void> Function(List<String> paths) onUpdateWhitelist;
  final Future<void> Function(String token) onUpdateSession;
  final List<String> watchFolders;

  // Rate limiting state (Static to persist across instantiations)
  static final Map<String, List<DateTime>> _endpointRequestHistory = {};
  static const int _maxRequestsPerSecond = 50;

  TunnelApiService({
    required this.whitelist,
    this.mainTunnelUrl,
    required this.onLog,
    required this.onStartService,
    required this.onUpdateWhitelist,
    required this.onUpdateSession,
    required this.watchFolders,
  });

  Future<void> handleRequest(
    HttpRequest request,
    String bodyString, {
    bool isAuthorized = false,
  }) async {
    final requestPath = request.uri.path;
    
    // Apply Rate Limiting
    if (_isRateLimited(requestPath)) {
      onLog("RATE LIMIT: Exceeded for $requestPath (429)");
      return _sendJsonResponse(request, {
        "success": false,
        "message": "Too Many Requests (Limit: $_maxRequestsPerSecond/s)",
      }, status: 429);
    }

    onLog("Routing API: Method=${request.method}, Path=$requestPath");

    if (requestPath == '/healthcheck') {
      if (request.method != 'GET') return _sendMethodNotAllowed(request);
      return _sendJsonResponse(request, {"status": "ok"});
    }

    if (requestPath == '/api/v1/auth/verify') {
      if (request.method != 'POST') return _sendMethodNotAllowed(request);
      await _handleVerifyAuth(request, isAuthorized, bodyString);
      return;
    } else if (requestPath == '/api/v1/auth/callback') {
      if (request.method != 'POST') return _sendMethodNotAllowed(request);
      final body = jsonDecode(bodyString);
      final token = body['token'] as String?;
      if (token != null) {
        onLog("API: Received token update via callback/local-push.");
        await onUpdateSession(token);
        _sendJsonResponse(request, {"success": true, "message": "Token updated"});
      } else {
        _sendJsonResponse(request, {"success": false, "message": "Missing token"}, status: 400);
      }
      return;
    } else if (requestPath == '/api/v1/auth/sign') {
      if (request.method != 'POST') return _sendMethodNotAllowed(request);
      await _handleSignAuth(request, bodyString);
      return;
    }

    if (requestPath == '/api/v1/files') {
      if (request.method != 'POST') return _sendMethodNotAllowed(request);
      await _handleListFiles(request, bodyString);
    } else if (requestPath == '/api/v1/search') {
      if (request.method != 'POST') return _sendMethodNotAllowed(request);
      await _handleSearch(request, bodyString);
    } else if (requestPath == '/api/v1/whitelist') {
      if (request.method != 'POST') return _sendMethodNotAllowed(request);
      if (!isAuthorized) {
        return _sendJsonResponse(request, {
          "success": false,
          "message": "Unauthorized: Missing or invalid signature",
        }, status: 401);
      }
      await _handleWhitelistAdd(request, bodyString);
    } else if (requestPath == '/api/v1/whitelist/list') {
      if (request.method != 'GET') return _sendMethodNotAllowed(request);
      if (!isAuthorized) {
        return _sendJsonResponse(request, {
          "success": false,
          "message": "Unauthorized: Missing or invalid signature",
        }, status: 401);
      }
      await _handleWhitelistList(request);
    } else if (requestPath == '/api/v1/whitelist/delete') {
      if (request.method != 'DELETE' && request.method != 'POST') {
        return _sendMethodNotAllowed(request);
      }
      if (!isAuthorized) {
        return _sendJsonResponse(request, {
          "success": false,
          "message": "Unauthorized: Missing or invalid signature",
        }, status: 401);
      }
      await _handleWhitelistDelete(request, bodyString);
    } else if (requestPath == '/api/v1/whitelist/clear') {
      if (request.method != 'DELETE' && request.method != 'POST') {
        return _sendMethodNotAllowed(request);
      }
      if (!isAuthorized) {
        return _sendJsonResponse(request, {
          "success": false,
          "message": "Unauthorized: Missing or invalid signature",
        }, status: 401);
      }
      await _handleWhitelistClear(request);
    } else if (requestPath == '/api/v1/start-service') {
      if (request.method != 'POST') return _sendMethodNotAllowed(request);
      await _handleStartService(request);
    } else if (requestPath == '/api/v1/status') {
      if (request.method != 'GET') return _sendMethodNotAllowed(request);
      await _handleStatus(request);
    } else if (requestPath.startsWith('/file/')) {
      if (request.method != 'GET') {
        return _sendMethodNotAllowed(request);
      }
      await _handleFileDownload(request);
    } else if (request.method == 'GET') {
      // Direct path access
      final decodedPath = Uri.decodeComponent(requestPath);
      
      String? matchedRoot;
      for (final root in watchFolders) {
        if (decodedPath.startsWith(root)) {
          matchedRoot = root;
          break;
        }
      }

      if (matchedRoot != null) {
        final slug = p.basename(matchedRoot).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
        final isWhitelisted = whitelist.contains(slug) || 
                              whitelist.contains(matchedRoot) || 
                              whitelist.contains(matchedRoot.endsWith('/') ? matchedRoot : '$matchedRoot/');
        if (isWhitelisted) {
          await _serveFile(request, decodedPath);
          return;
        }
      }

      _sendJsonResponse(request, {
        "success": false,
        "message": "Endpoint not found or Access Denied",
      }, status: 404);
    } else {
      _sendJsonResponse(request, {
        "success": false,
        "message": "Endpoint not found",
      }, status: 404);
    }
  }

  Future<void> _handleVerifyAuth(HttpRequest request, bool isAuthorized, String bodyString) async {
    _sendJsonResponse(request, {
      "success": isAuthorized,
      "authorized": isAuthorized,
      "message": isAuthorized ? "Authorized" : "Unauthorized",
    });
  }

  Future<void> _handleSignAuth(HttpRequest request, String bodyString) async {
    _sendJsonResponse(request, {"success": true, "message": "Sign request received"});
  }

  Future<void> _handleSearch(HttpRequest request, String bodyString) async {
    try {
      final body = jsonDecode(bodyString);
      final query = body['path']?.toString() ?? "";

      if (query.isEmpty) {
        _sendJsonResponse(request, {"success": true, "data": []});
        return;
      }

      final List<Map<String, dynamic>> results = [];

      for (var rootPath in watchFolders) {
        final rootDir = Directory(rootPath);
        if (!rootDir.existsSync()) continue;

        final List<Directory> queue = [rootDir];
        int processedCount = 0;

        while (queue.isNotEmpty && results.length < 50 && processedCount < 1000) {
          final currentDir = queue.removeAt(0);
          processedCount++;

          try {
            await for (final entity in currentDir.list(recursive: false, followLinks: false)) {
              if (entity is Directory) {
                final path = entity.path;
                final name = p.basename(path);

                if (name.startsWith('.') ||
                    name == 'Library' ||
                    name == 'Applications' ||
                    name == 'System' ||
                    name == 'node_modules') {
                  continue;
                }

                if (name.toLowerCase().contains(query.toLowerCase())) {
                  results.add({"path": entity.absolute.path, "type": "folder"});
                }

                if (results.length < 50) {
                  queue.add(entity);
                }
              }
              if (results.length >= 50) {
                break;
              }
            }
          } catch (e) {
            // Ignore access errors for specific directories
          }
        }
        if (results.length >= 50) {
          break;
        }
      }

      _sendJsonResponse(request, {"success": true, "data": results});
    } catch (e) {
      _sendJsonResponse(request, {"success": false, "message": e.toString()}, status: 500);
    }
  }

  Future<void> _handleListFiles(HttpRequest request, String bodyString) async {
    try {
      final body = jsonDecode(bodyString);
      String? id = body['path']?.toString();

      if (id == null || id.isEmpty) {
        final list = watchFolders.map((path) => {
          "name": p.basename(path),
          "path": path,
          "type": "folder",
        }).toList();
        _sendJsonResponse(request, {"success": true, "data": list});
        return;
      }

      String? foundRootPath;
      String subPathInFolder = "";

      for (var rootPath in watchFolders) {
        if (id.startsWith(rootPath)) {
          foundRootPath = rootPath;
          subPathInFolder = p.relative(id, from: rootPath);
          if (subPathInFolder == ".") {
            subPathInFolder = "";
          }
          break;
        }
      }

      if (foundRootPath == null) {
        _sendJsonResponse(request, {
          "success": false,
          "message": "Access denied: Folder not found in Watch Folders",
        }, status: 404);
        return;
      }

      final fullPath = p.join(foundRootPath, subPathInFolder);
      final entityType = FileSystemEntity.typeSync(fullPath);
      if (entityType != FileSystemEntityType.directory) {
        _sendJsonResponse(request, {"success": false, "message": "Directory not found"}, status: 404);
        return;
      }

      final entities = await Directory(fullPath).list(recursive: false).toList();
      final List<Map<String, dynamic>> data = [];

      for (final e in entities) {
        final name = p.basename(e.path);
        if (name.startsWith('.')) {
          continue;
        }

        final stat = FileSystemEntity.typeSync(e.path);
        final isDir = stat == FileSystemEntityType.directory;
        final isFile = stat == FileSystemEntityType.file;
        if (!isDir && !isFile) {
          continue;
        }

        final fStat = await e.stat();
        String typeAttr = isDir ? "folder" : "file";
        if (isFile) {
          final ext = p.extension(e.path).toLowerCase();
          if (['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic'].contains(ext)) {
            typeAttr = "image";
          }
        }

        String? extension;
        if (isFile) {
          extension = p.extension(e.path).replaceFirst('.', '').toLowerCase();
        }

        final item = <String, dynamic>{
          "name": name,
          "type": typeAttr,
          "extension": extension,
          "path": e.path,
          "size": isDir ? 0 : fStat.size,
          "created_at": fStat.modified.toIso8601String(),
        };

        final String? publicUrl = _generatePublicUrl(foundRootPath, e.path);
        if (publicUrl != null) {
          item["url"] = publicUrl;
        }
        data.add(item);
      }
      _sendJsonResponse(request, {"success": true, "data": data});
    } catch (e) {
      _sendJsonResponse(request, {"success": false, "message": e.toString()}, status: 500);
    }
  }

  Future<void> _handleWhitelistAdd(HttpRequest request, String bodyString) async {
    try {
      final body = jsonDecode(bodyString);
      final path = body['path']?.toString();
      if (path != null) {
        final current = whitelist.toList();
        if (!current.contains(path)) {
          current.add(path);
          await onUpdateWhitelist(current);
        }
        _sendJsonResponse(request, {"success": true, "message": "Added to whitelist"});
      } else {
        _sendJsonResponse(request, {"success": false, "message": "Path missing"}, status: 400);
      }
    } catch (e) {
      _sendJsonResponse(request, {"success": false, "message": e.toString()}, status: 500);
    }
  }

  Future<void> _handleWhitelistList(HttpRequest request) async {
    _sendJsonResponse(request, {"success": true, "data": whitelist.toList()});
  }

  Future<void> _handleWhitelistDelete(HttpRequest request, String bodyString) async {
    try {
      final body = jsonDecode(bodyString);
      final path = body['path']?.toString();
      if (path != null) {
        final current = whitelist.toList();
        if (current.contains(path)) {
          current.remove(path);
          await onUpdateWhitelist(current);
        }
        _sendJsonResponse(request, {"success": true, "message": "Removed from whitelist"});
      } else {
        _sendJsonResponse(request, {"success": false, "message": "Path missing"}, status: 400);
      }
    } catch (e) {
      _sendJsonResponse(request, {"success": false, "message": e.toString()}, status: 500);
    }
  }

  Future<void> _handleWhitelistClear(HttpRequest request) async {
    await onUpdateWhitelist([]);
    _sendJsonResponse(request, {"success": true, "message": "Whitelist cleared"});
  }

  Future<void> _handleStartService(HttpRequest request) async {
    await onStartService();
    _sendJsonResponse(request, {"success": true, "message": "Service start triggered"});
  }

  Future<void> _handleStatus(HttpRequest request) async {
    _sendJsonResponse(request, {"success": true, "status": "online"});
  }

  Future<void> _handleFileDownload(HttpRequest request) async {
    try {
      final requestPath = request.uri.path.replaceFirst('/file/', '');
      final segments = requestPath.split('/');
      if (segments.isEmpty) {
        _sendJsonResponse(request, {"success": false, "message": "Invalid path"}, status: 400);
        return;
      }

      final slug = segments[0];
      final relativePath = segments.skip(1).join('/');
      final decodedRelativePath = Uri.decodeComponent(relativePath);

      String? matchedRoot;
      for (final root in watchFolders) {
        final rootSlug = p.basename(root).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
        if (rootSlug == slug) {
          matchedRoot = root;
          break;
        }
      }

      if (matchedRoot == null) {
        // Fallback: check if the slug is actually part of an absolute path in the whitelist
        for (final root in watchFolders) {
          if (slug == root || (root.endsWith('/') && slug == root.substring(0, root.length - 1))) {
            matchedRoot = root;
            break;
          }
        }
      }

      if (matchedRoot == null) {
        _sendJsonResponse(request, {"success": false, "message": "Folder mapping not found"}, status: 404);
        return;
      }

      final slugForWhitelist = p.basename(matchedRoot).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
      final isWhitelisted = whitelist.contains(slugForWhitelist) || 
                            whitelist.contains(matchedRoot) || 
                            whitelist.contains(matchedRoot.endsWith('/') ? matchedRoot : '$matchedRoot/');

      if (!isWhitelisted) {
        _sendJsonResponse(request, {"success": false, "message": "Access denied: Folder not whitelisted"}, status: 403);
        return;
      }

      final fullPath = p.join(matchedRoot, decodedRelativePath);
      await _serveFile(request, fullPath);
    } catch (e) {
      _sendJsonResponse(request, {"success": false, "message": e.toString()}, status: 500);
    }
  }

  Future<void> _serveFile(HttpRequest request, String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      request.response.statusCode = 404;
      request.response.write("File not found");
      await request.response.close();
      return;
    }

    final contentType = _getContentType(filePath);
    final widthStr = request.uri.queryParameters['w'];
    final width = widthStr != null ? int.tryParse(widthStr) : null;

    if (width != null && contentType.primaryType == 'image') {
      try {
        final bytes = await file.readAsBytes();
        final image = img.decodeImage(bytes);
        if (image != null) {
          img.Image resized;
          if (image.width > width) {
            resized = img.copyResize(image, width: width);
          } else {
            resized = image;
          }
          final resizedBytes = img.encodeJpg(resized);
          request.response.headers.contentType = ContentType('image', 'jpeg');
          request.response.add(resizedBytes);
          await request.response.close();
          return;
        }
      } catch (e) {
        onLog("RESIZE ERROR: $e");
        // Fallback to original file
      }
    }

    request.response.headers.contentType = contentType;
    await file.openRead().pipe(request.response);
  }

  ContentType _getContentType(String path) {
    final ext = p.extension(path).toLowerCase();
    if (ext == '.jpg' || ext == '.jpeg') {
      return ContentType('image', 'jpeg');
    }
    if (ext == '.png') {
      return ContentType('image', 'png');
    }
    if (ext == '.gif') {
      return ContentType('image', 'gif');
    }
    if (ext == '.webp') {
      return ContentType('image', 'webp');
    }
    return ContentType.binary;
  }

  String? _generatePublicUrl(String rootPath, String filePath) {
    if (mainTunnelUrl == null) {
      return null;
    }
    final namePath = p.basename(rootPath).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
    if (!whitelist.contains(namePath)) {
      return null;
    }
    String baseUrl = mainTunnelUrl!;
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    String finalUrl = "$baseUrl${filePath.replaceAll('\\', '/')}";
    if (FileSystemEntity.isDirectorySync(filePath) && !finalUrl.endsWith('/')) {
      finalUrl += '/';
    }
    return finalUrl;
  }

  void _sendJsonResponse(HttpRequest request, Map<String, dynamic> data, {int status = 200}) {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(data));
    request.response.close();
  }

  void _sendMethodNotAllowed(HttpRequest request) {
    _sendJsonResponse(request, {"success": false, "message": "Method not allowed"}, status: 405);
  }

  bool _isRateLimited(String path) {
    final now = DateTime.now();
    final oneSecondAgo = now.subtract(const Duration(seconds: 1));

    // Get history for this specific endpoint
    final history = _endpointRequestHistory.putIfAbsent(path, () => []);

    // Remove old entries
    history.removeWhere((timestamp) => timestamp.isBefore(oneSecondAgo));

    if (history.length >= _maxRequestsPerSecond) {
      return true;
    }

    history.add(now);
    return false;
  }
}
