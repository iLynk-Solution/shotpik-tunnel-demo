import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import '../../../core/rsa_utils.dart';
import '../../../core/app_config.dart';
import '../domain/tunnel_models.dart';

class TunnelApiService {
  final Map<String, SharedFolderData> sharedFolders;
  final Set<String> whitelist;
  final String? mainTunnelUrl;
  final Function(String) onLog;
  final Future<String?> Function(
    String id,
    String name,
    String namePath,
    String path,
  ) onAddFolder;
  final Future<void> Function(String id) onRemoveFolder;
  final Future<void> Function() onStartService;
  final Future<void> Function(String id) onRefreshTunnel;
  final Future<void> Function(List<String> paths) onUpdateWhitelist;
  final Future<void> Function(String token) onUpdateSession;

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
    required this.onUpdateSession,
  });

  String _generateUuid() {
    final random = Random();
    String generateByte() =>
        random.nextInt(256).toRadixString(16).padLeft(2, '0');
    return '${generateByte()}${generateByte()}${generateByte()}${generateByte()}-'
        '${generateByte()}${generateByte()}-'
        '4${generateByte().substring(1)}-'
        '${(random.nextInt(4) + 8).toRadixString(16)}${generateByte().substring(1)}-'
        '${generateByte()}${generateByte()}${generateByte()}${generateByte()}${generateByte()}${generateByte()}';
  }

  Future<void> handleRequest(
    HttpRequest request,
    String bodyString, {
    bool isAuthorized = false,
  }) async {
    final requestPath = request.uri.path;
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
      // This is a special push-token endpoint to fallback from deep link
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
    } else if (requestPath == '/api/v1/tunnel/create') {
      if (request.method != 'POST') return _sendMethodNotAllowed(request);
      await _handleCreateTunnel(request, bodyString);
    } else if (requestPath == '/api/v1/create-folder') {
      if (request.method != 'POST') return _sendMethodNotAllowed(request);
      await _handleCreateFolderShortcut(request, bodyString);
    } else if (requestPath == '/api/v1/tunnel/list') {
      if (request.method != 'POST') return _sendMethodNotAllowed(request);
      await _handleListTunnels(request);
    } else if (requestPath == '/api/v1/tunnel/refresh') {
      if (request.method != 'POST') return _sendMethodNotAllowed(request);
      await _handleRefreshTunnel(request, bodyString);
    } else if (requestPath == '/api/v1/tunnel/delete') {
      if (request.method != 'POST' && request.method != 'DELETE') {
        return _sendMethodNotAllowed(request);
      }
      await _handleDeleteTunnel(request, bodyString);
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
      // Enforce Signature Check
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
      if (request.method != 'GET') return _sendMethodNotAllowed(request);
      await _handleFileDownload(request);
    } else {
      _sendJsonResponse(request, {
        "success": false,
        "message": "Endpoint not found",
      }, status: 404);
    }
  }

  Future<void> _handleSearch(HttpRequest request, String bodyString) async {
    try {
      final body = jsonDecode(bodyString);
      final String? query = body['path'];
      if (query == null || query.isEmpty) {
        _sendJsonResponse(request, {
          "success": false,
          "message": "Missing 'path' query",
        }, status: 400);
        return;
      }

      final List<Map<String, String>> results = [];
      final String? basePath = body['base_path'];
      final rootDir = basePath != null
          ? Directory(basePath)
          : Directory.current;

      if (!rootDir.existsSync()) {
        _sendJsonResponse(request, {
          "success": false,
          "message": "Base path does not exist: $basePath",
        }, status: 400);
        return;
      }

      onLog(
        "API: Searching for folders matching '$query' in ${rootDir.path}...",
      );

      // Perform recursive search (limited depth for safety)
      await for (final entity in rootDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is Directory) {
          final name = p.basename(entity.path);
          if (name.toLowerCase().contains(query.toLowerCase())) {
            results.add({"path": entity.absolute.path, "type": "folder"});
          }
        }
        // Limit results to 50 for performance
        if (results.length >= 50) break;
      }

      _sendJsonResponse(request, {"success": true, "data": results});
    } catch (e) {
      onLog("API Search Error: $e");
      _sendJsonResponse(request, {
        "success": false,
        "message": e.toString(),
      }, status: 500);
    }
  }

  Future<void> _handleVerifyAuth(
    HttpRequest request,
    bool isAuthorized,
    String rawBody,
  ) async {
    if (isAuthorized) {
      _sendJsonResponse(request, {
        "success": true,
        "message": "RSA Signature is VALID!",
        "details": {
          "status": "Verified",
          "algorithm": "RSA-SHA256",
          "checkpoint":
              "Signature verification successfully passed via Middleware.",
        },
      });
    } else {
      _sendJsonResponse(request, {
        "success": false,
        "message": "RSA Signature VERIFICATION FAILED!",
        "received_body": rawBody,
        "details": {
          "status": "Unauthorized",
          "algorithm": "RSA-SHA256",
          "reason":
              "Middleware indicated isAuthorized = false. Check body content and signature base.",
          "help":
              "Ensure your body payload matches EXACTLY what you signed. Check for invisible characters or different line endings.",
          "normalization_hint":
              "Try signing a minified JSON (no spaces, no newlines) and sending that.",
        },
      }, status: 403);
    }
  }

  void _sendMethodNotAllowed(HttpRequest request) {
    _sendJsonResponse(request, {
      "success": false,
      "message": "Method ${request.method} not allowed for this endpoint",
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



  Future<void> _handleFileDownload(HttpRequest request) async {
    try {
      final pathSegments = request.uri.pathSegments;
      if (pathSegments.length < 2) {
        _sendJsonResponse(request, {"success": false, "message": "Invalid file path format. Use /file/{name_path}/{sub_path}"}, status: 400);
        return;
      }

      // Format: /file/summer2024/sub/photo.jpg
      // segments: ["file", "summer2024", "sub", "photo.jpg"]
      final String folderNamePath = pathSegments[1];
      final List<String> subPathSegments = pathSegments.sublist(2);

      // 1. Verify whitelist
      if (!whitelist.contains(folderNamePath)) {
        onLog("API Download: Forbidden. Folder '$folderNamePath' not whitelisted.");
        _sendJsonResponse(request, {"success": false, "message": "Access denied: Folder not whitelisted"}, status: 403);
        return;
      }

      // 2. Find folder details
      SharedFolderData? folder;
      for (var f in sharedFolders.values) {
        if (f.namePath == folderNamePath) {
          folder = f;
          break;
        }
      }

      if (folder == null) {
        _sendJsonResponse(request, {"success": false, "message": "Folder metadata not found"}, status: 404);
        return;
      }

      // 3. Construct absolute file path
      String relativePath = p.joinAll(subPathSegments);
      // Security: Prevent Directory Traversal
      if (relativePath.contains("..") || relativePath.startsWith("/") || relativePath.contains("\\")) {
         _sendJsonResponse(request, {"success": false, "message": "Invalid relative path"}, status: 400);
         return;
      }

      final String fullPath = p.join(folder.localPath, relativePath);
      final file = File(fullPath);

      // 4. Verify file exists and is not a directory
      if (!await file.exists()) {
         _sendJsonResponse(request, {"success": false, "message": "File not found"}, status: 404);
         return;
      }
      
      if (await FileSystemEntity.isDirectory(fullPath)) {
         _sendJsonResponse(request, {"success": false, "message": "Access denied: Cannot download a directory"}, status: 403);
         return;
      }

      // ENFORCE: Must be a Shortcut (Link)
      // This ensures we only serve files that were explicitly "published" via create-folder symlinks
      if (!await FileSystemEntity.isLink(fullPath)) {
         onLog("API Download: REJECTED. File is not a shortcut: $fullPath");
         _sendJsonResponse(request, {"success": false, "message": "Access denied: File is not a shortcut (not published)"}, status: 403);
         return;
      }

      // 5. Build the public Tunnel URL
      String publicUrl = "";
      if (folder.tunnelUrl != null && folder.tunnelUrl!.isNotEmpty) {
        String baseUrl = folder.tunnelUrl!;
        if (baseUrl.endsWith("/")) baseUrl = baseUrl.substring(0, baseUrl.length - 1);
        
        // Ensure relativePath doesn't have leading slash for join
        String cleanRelativePath = relativePath;
        if (cleanRelativePath.startsWith("/")) cleanRelativePath = cleanRelativePath.substring(1);
        
        publicUrl = "$baseUrl/$cleanRelativePath";
      }

      onLog("API Download: Generated link for $fullPath -> $publicUrl");

      _sendJsonResponse(request, {
        "success": true,
        "url": publicUrl,
      });

    } catch (e) {
      onLog("API Download Error: $e");
      try {
        _sendJsonResponse(request, {"success": false, "message": "Internal Server Error"}, status: 500);
      } catch (_) {}
    }
  }

  Future<void> _handleWhitelistList(HttpRequest request) async {
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
          "name": folder?.name ?? "",
          "path": namePathItem,
          "url": folder?.tunnelUrl ?? "",
          "created_at": folder?.createdAt.toIso8601String() ?? "",
        });
      }

      _sendJsonResponse(request, {"success": true, "data": results});
      onLog(
        "API: GET /api/v1/whitelist/list - Success (found ${results.length} items): ${jsonEncode(results)}",
      );
    } catch (e) {
      onLog("Whitelist error: $e");
      _sendJsonResponse(request, {
        "success": false,
        "message": "Internal Server Error",
      }, status: 500);
    }
  }



  Future<void> _handleWhitelistAdd(
    HttpRequest request,
    String bodyString,
  ) async {
    try {
      if (request.method != 'POST') {
        _sendJsonResponse(request, {
          "success": false,
          "message": "Method not allowed",
        }, status: 405);
        return;
      }

      final content = bodyString;
      if (content.isEmpty) {
        _sendJsonResponse(request, {
          "success": false,
          "message": "Empty body",
        }, status: 400);
        return;
      }

      final body = jsonDecode(content);
      String? path = body['path']?.toString();

      if (path == null || path.isEmpty) {
        _sendJsonResponse(request, {
          "success": false,
          "message": "Missing 'path'",
        }, status: 400);
        return;
      }

      SharedFolderData? foundFolder;
      for (var f in sharedFolders.values) {
        if (f.namePath == path) {
          foundFolder = f;
          break;
        }
      }

      if (foundFolder == null) {
        _sendJsonResponse(request, {
          "success": false,
          "message": "Folder/Tunnel not found",
        }, status: 404);
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
            "name": foundFolder.name,
            "path": foundFolder.namePath,
            "url": foundFolder.tunnelUrl ?? "",
            "created_at": foundFolder.createdAt.toIso8601String(),
          },
        });
        onLog(
          "API: POST /api/v1/whitelist/add - Success: ${foundFolder.namePath} (Path: ${foundFolder.localPath})",
        );
      } else {
        _sendJsonResponse(request, {
          "success": true,
          "message": "Folder is already in whitelist",
        });
        onLog(
          "API: POST /api/v1/whitelist/add - Already in whitelist: ${foundFolder.namePath}",
        );
      }
    } catch (e) {
      onLog("Whitelist Add error: $e");
      _sendJsonResponse(request, {
        "success": false,
        "message": "Internal Server Error",
      }, status: 500);
    }
  }

  Future<void> _handleWhitelistDelete(
    HttpRequest request,
    String bodyString,
  ) async {
    try {
      final content = bodyString;
      if (content.isEmpty) {
        _sendJsonResponse(request, {
          "success": false,
          "message": "Empty body",
        }, status: 400);
        return;
      }
      final body = jsonDecode(content);
      final path = body['path']?.toString();

      if (path == null || path.isEmpty) {
        _sendJsonResponse(request, {
          "success": false,
          "message": "Missing 'path'",
        }, status: 400);
        return;
      }

      String namePathToRemove = "";
      SharedFolderData? folder;

      // Try finding by namePath (slug)
      for (var f in sharedFolders.values) {
        if (f.namePath == path) {
          folder = f;
          namePathToRemove = f.namePath;
          break;
        }
      }

      if (folder == null) {
        // Final fallback: check if the string itself is in the whitelist (for generic namePaths)
        if (whitelist.contains(path)) {
          namePathToRemove = path;
        }
      }

      if (namePathToRemove.isEmpty || !whitelist.contains(namePathToRemove)) {
        _sendJsonResponse(request, {
          "success": false,
          "message": "Item not found in whitelist",
        }, status: 404);
        return;
      }

      final List<String> currentWhitelist = whitelist.toList();
      currentWhitelist.remove(namePathToRemove);
      await onUpdateWhitelist(currentWhitelist);

      _sendJsonResponse(request, {
        "success": true,
        "message": "Removed from whitelist",
        "data": {
          "name": folder?.name ?? "",
          "path": namePathToRemove,
          "url": folder?.tunnelUrl ?? "",
          "created_at": folder?.createdAt.toIso8601String() ?? "",
        },
      });
      onLog(
        "API: DELETE /api/v1/whitelist/delete - Success: $namePathToRemove (Path: ${folder?.localPath ?? ''})",
      );
    } catch (e) {
      _sendJsonResponse(request, {
        "success": false,
        "message": e.toString(),
      }, status: 500);
    }
  }

  Future<void> _handleWhitelistClear(HttpRequest request) async {
    try {
      await onUpdateWhitelist([]);
      _sendJsonResponse(request, {
        "success": true,
        "message": "Whitelist cleared successfully",
      });
    } catch (e) {
      _sendJsonResponse(request, {
        "success": false,
        "message": e.toString(),
      }, status: 500);
    }
  }

  Future<void> _handleStartService(HttpRequest request) async {
    try {
      await onStartService();
      _sendJsonResponse(request, {
        "success": true,
        "message": "Service start triggered",
      });
    } catch (e) {
      _sendJsonResponse(request, {
        "success": false,
        "message": e.toString(),
      }, status: 500);
    }
  }

  Future<void> _handleCreateFolderShortcut(
    HttpRequest request,
    String bodyString,
  ) async {
    try {
      final body = jsonDecode(bodyString);
      final String? destPath = body['location'];
      final String? sourcePath = body['path'];
      final List<dynamic>? files = body['files'];

      if (destPath == null || destPath.isEmpty) {
        _sendJsonResponse(request, {
          "success": false,
          "message": "Missing 'location'",
        }, status: 400);
        return;
      }

      // --- Whitelist Check for sourcePath ---
      if (sourcePath != null && sourcePath.isNotEmpty) {
        bool isWhitelisted = false;
        
        // Find folder by localPath, namePath, or ID
        SharedFolderData? found;
        for (var f in sharedFolders.values) {
          if (f.localPath == sourcePath || f.namePath == sourcePath || f.id == sourcePath) {
            found = f;
            break;
          }
        }

        if (found != null && whitelist.contains(found.namePath)) {
          isWhitelisted = true;
        }

        if (!isWhitelisted) {
          _sendJsonResponse(request, {
            "success": false,
            "message": "Forbidden: Source path '$sourcePath' is not in whitelist.",
          }, status: 403);
          onLog("API: Create-folder REJECTED. Path not whitelisted: $sourcePath");
          return;
        }
      }
      // --------------------------------------

      // 1. Create folder if not exists, or CLEAN it if it does
      final dir = Directory(destPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        onLog("API: Created directory: ${dir.absolute.path}");
      } else {
        // Clean existing contents for a fresh sync
        onLog("API: Cleaning existing contents in ${dir.absolute.path}...");
        try {
          final List<FileSystemEntity> entities = await dir.list().toList();
          for (final entity in entities) {
            await entity.delete(recursive: true);
          }
        } catch (e) {
          onLog("API: Warning - could not clean directory: $e");
        }
      }

      // 2. Determine files to process
      List<String> filesToProcess = [];
      if (files != null) {
        filesToProcess = files.map((e) => e.toString()).toList();
      }

      // 3. "Nếu file rỗng tức là lấy hết" - Take all files from sourcePath if provided
      if (filesToProcess.isEmpty &&
          sourcePath != null &&
          sourcePath.isNotEmpty) {
        final sourceDir = Directory(sourcePath);
        if (await sourceDir.exists()) {
          final entities = await sourceDir.list(recursive: true).toList();
          filesToProcess = entities
              .whereType<File>()
              .map((e) => e.path)
              .toList();
          onLog(
            "API: Taking all ${filesToProcess.length} files (recursive) from $sourcePath",
          );
        }
      }

      // 4. Create shortcut (symlink) into folder
      for (final filePath in filesToProcess) {
        final sourceFile = File(filePath);

        if (await sourceFile.exists()) {
          final fileName = p.basename(sourceFile.path);
          final targetLinkPath = p.join(dir.path, fileName);
          final link = Link(targetLinkPath);

          // If link already exists, remove it first
          if (await link.exists()) {
            await link.delete();
          }

          // Create symlink
          await link.create(sourceFile.absolute.path);
          onLog(
            "API: Created symlink for $fileName -> ${sourceFile.absolute.path}",
          );
        } else {
          onLog("API: File not found for symlink: $filePath");
        }
      }

      // 5. Automatically Add to Shared Folders and Whitelist the destination
      String? destNamePath;
      try {
        final destFolderName = p.basename(destPath);
        // Create a namePath slug that preserves casing
        final slug = destFolderName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
        destNamePath = slug;

        // Register the folder (this will add it to the global sharedFolders map in the App state)
        final newId = _generateUuid();
        await onAddFolder(newId, destFolderName, slug, destPath);

        final List<String> currentWhitelist = whitelist.toList();
        if (!currentWhitelist.contains(destNamePath)) {
          currentWhitelist.add(destNamePath);
          await onUpdateWhitelist(currentWhitelist);
          onLog("API: Automatically whitelisted destination folder: $destNamePath");
        }
      } catch (e) {
        onLog("API: Warning - Could not automatically register/whitelist destination folder: $e");
      }

      _sendJsonResponse(request, {
        "success": true,
        "location": destPath,
        "folder": sourcePath,
        "name_path": destNamePath, // Inform client of the exact namePath (preserving case)
      });
    } catch (e) {
      onLog("API Create Folder Shortcut Error: $e");
      _sendJsonResponse(request, {
        "success": false,
        "message": e.toString(),
      }, status: 500);
    }
  }

  Future<void> _handleCreateTunnel(
    HttpRequest request,
    String bodyString,
  ) async {
    try {
      final content = bodyString;
      if (content.isEmpty) {
        _sendJsonResponse(request, {
          "success": false,
          "message": "Empty body",
        }, status: 400);
        return;
      }

      final body = jsonDecode(content);
      String? name = body['name'];
      String? namePath = body['name_path'] ?? body['nameUrl'];
      final String? path = body['path'];

      if (path == null || path.isEmpty) {
        _sendJsonResponse(request, {
          "success": false,
          "message": "Missing 'path'",
        }, status: 400);
        return;
      }

      if (name == null || name.isEmpty) {
        name = "album_${DateTime.now().millisecondsSinceEpoch}";
      }

      if (namePath == null || namePath.isEmpty) {
        // Fallback to stylized name if namePath is missing
        namePath = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
        if (namePath.isEmpty) {
          namePath = "album_${_generateUuid().substring(0, 8)}";
        }
      }

      // 1. namePath MUST be unique as it's used for routing
      final existingByNamePath = sharedFolders.values
          .cast<SharedFolderData?>()
          .firstWhere((f) => f?.namePath == namePath, orElse: () => null);
      if (existingByNamePath != null) {
        _sendJsonResponse(request, {
          "success": false,
          "message":
              "Error: Link '$namePath' đã được sử dụng bởi thư mục: ${existingByNamePath.localPath}",
        }, status: 409);
        return;
      }

      // 2. Physical localPath MUST be unique to avoid duplicate tunnels
      final existingByPath = sharedFolders.values
          .cast<SharedFolderData?>()
          .firstWhere(
            (f) =>
                f != null &&
                p.canonicalize(f.localPath) == p.canonicalize(path),
            orElse: () => null,
          );
      if (existingByPath != null) {
        _sendJsonResponse(request, {
          "success": false,
          "message":
              "Error: Thư mục này đã được chia sẻ với link: ${existingByPath.namePath}",
        }, status: 409);
        return;
      }

      final String id = _generateUuid();
      final result = await onAddFolder(id, name, namePath, path);
      if (result != null && result.startsWith("Error:")) {
        _sendJsonResponse(request, {
          "success": false,
          "message": result,
        }, status: 400);
      } else {
        String fullUrl = result ?? "";

        _sendJsonResponse(request, {
          "success": true,
          "data": {
            "name": name,
            "path": namePath,
            "type": "folder",
            "url": fullUrl,
            "created_at": DateTime.now().toIso8601String(),
            "message": "Tunnel created successfully",
          },
        });
      }
    } catch (e) {
      onLog("API Create Tunnel Error: $e");
      _sendJsonResponse(request, {
        "success": false,
        "message": e.toString(),
      }, status: 500);
    }
  }

  Future<void> _handleSignAuth(HttpRequest request, String bodyString) async {
    try {
      // Robustly minify the JSON before signing to ensure a standard signature
      final dynamic decoded = jsonDecode(bodyString);
      final String minifiedBody = jsonEncode(decoded);

      final String signature = RSAUtils.signBody(
        AppConfig.rsaPrivateKey,
        minifiedBody,
      );

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
        "message": "Invalid JSON in request body: ${e.toString()}",
      }, status: 400);
    }
  }

  Future<void> _handleListTunnels(HttpRequest request) async {
    final list = sharedFolders.values
        .map(
          (f) => {
            "name": f.name,
            "path": f.namePath,
            "type": "folder",
            "url": f.tunnelUrl ?? "",
            "status": f.isConnecting
                ? "connecting"
                : (f.tunnelUrl != null ? "online" : "offline"),
            "whitelisted": whitelist.contains(f.namePath),
            "created_at": f.createdAt.toIso8601String(),
          },
        )
        .toList();
    _sendJsonResponse(request, {"success": true, "data": list});
  }

  Future<void> _handleRefreshTunnel(
    HttpRequest request,
    String bodyString,
  ) async {
    try {
      final content = bodyString;
      if (content.isEmpty) {
        _sendJsonResponse(request, {
          "success": false,
          "message": "Empty body",
        }, status: 400);
        return;
      }
      final body = jsonDecode(content);
      final path = body['path']?.toString();

      if (path == null || path.isEmpty) {
        _sendJsonResponse(request, {
          "success": false,
          "message": "Missing 'path'",
        }, status: 400);
        return;
      }

      SharedFolderData? folder;
      // 1. Resolve by local path (canonicalize for robustness)
      for (var f in sharedFolders.values) {
        if (p.canonicalize(f.localPath) == p.canonicalize(path)) {
          folder = f;
          break;
        }
      }

      // 2. Fallback to namePath if not found by local path
      if (folder == null) {
        for (var f in sharedFolders.values) {
          if (f.namePath == path || f.id == path) {
            folder = f;
            break;
          }
        }
      }

      if (folder == null) {
        _sendJsonResponse(request, {
          "success": false,
          "message": "Tunnel not found",
        }, status: 404);
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
        },
      });
    } catch (e) {
      _sendJsonResponse(request, {
        "success": false,
        "message": e.toString(),
      }, status: 500);
    }
  }

  Future<void> _handleDeleteTunnel(
    HttpRequest request,
    String bodyString,
  ) async {
    try {
      final content = bodyString;
      if (content.isEmpty) {
        _sendJsonResponse(request, {
          "success": false,
          "message": "Empty body",
        }, status: 400);
        return;
      }
      final body = jsonDecode(content);
      final path = body['path']?.toString();

      if (path == null || path.isEmpty) {
        _sendJsonResponse(request, {
          "success": false,
          "message": "Missing 'path'",
        }, status: 400);
        return;
      }

      SharedFolderData? folder;
      // 1. Resolve by local path
      for (var f in sharedFolders.values) {
        if (p.canonicalize(f.localPath) == p.canonicalize(path)) {
          folder = f;
          break;
        }
      }

      // 2. Fallback to namePath or id
      if (folder == null) {
        for (var f in sharedFolders.values) {
          if (f.namePath == path || f.id == path) {
            folder = f;
            break;
          }
        }
      }

      if (folder == null) {
        _sendJsonResponse(request, {
          "success": false,
          "message": "Tunnel not found",
        }, status: 404);
        return;
      }

      // Also remove from whitelist if it was there
      if (whitelist.contains(folder.namePath)) {
        final List<String> currentWhitelist = whitelist.toList();
        currentWhitelist.remove(folder.namePath);
        await onUpdateWhitelist(currentWhitelist);
      }

      await onRemoveFolder(folder.id);
      _sendJsonResponse(request, {
        "success": true,
        "message": "Tunnel deleted successfully",
      });
    } catch (e) {
      _sendJsonResponse(request, {
        "success": false,
        "message": e.toString(),
      }, status: 404);
    }
  }

  Future<void> _handleListFiles(HttpRequest request, String bodyString) async {
    try {
      final content = bodyString;
      if (content.isEmpty) {
        _sendJsonResponse(request, {
          "success": false,
          "message": "Empty body",
        }, status: 400);
        return;
      }

      final body = jsonDecode(content);
      // Support both 'id' and 'path' from body as the source path
      String? id = body['path']?.toString();

      // If still empty, return album list
      if (id == null || id.isEmpty) {
        final list = sharedFolders.values
            .map(
              (f) => {
                "name": f.name,
                "path": f.namePath,
                "type": "folder",
                "url": f.tunnelUrl ?? "",
                "status": f.isConnecting
                    ? "connecting"
                    : (f.tunnelUrl != null ? "online" : "offline"),
              },
            )
            .toList();
        _sendJsonResponse(request, {"success": true, "data": list});
        return;
      }

      onLog("API Files: Request for virtual path: $id");

      SharedFolderData? foundFolder;
      String subPathInFolder = "";

      // Split identifier from possible sub-path (e.g., "album1/subfolder")
      final segments = p.split(id).where((s) => s != "/" && s.isNotEmpty).toList();
      
      if (segments.isNotEmpty) {
        final virtualName = segments[0];
        // Only resolve by namePath (slug)
        for (var f in sharedFolders.values) {
          if (f.namePath == virtualName) {
            foundFolder = f;
            break;
          }
        }
        
        if (foundFolder != null) {
          subPathInFolder = p.joinAll(segments.sublist(1));
        }
      }

      if (foundFolder == null) {
        String msg = "Access denied: Folder or Tunnel not found";
        if (id.startsWith('http')) {
          msg = "Tunnel URL not recognized or offline: $id";
        }
        _sendJsonResponse(request, {
          "success": false,
          "message": msg,
        }, status: 404);
        return;
      }

      final fullPath = p.join(foundFolder.localPath, subPathInFolder);

      final entityType = FileSystemEntity.typeSync(fullPath);
      if (entityType != FileSystemEntityType.directory) {
        _sendJsonResponse(request, {
          "success": false,
          "message": "Directory not found",
        }, status: 404);
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
          final imageExts = [
            '.jpg',
            '.jpeg',
            '.png',
            '.gif',
            '.webp',
            '.bmp',
            '.heic',
          ];
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
      _sendJsonResponse(request, {
        "success": false,
        "message": e.toString(),
      }, status: 500);
    }
  }

  void _sendJsonResponse(
    HttpRequest request,
    Map<String, dynamic> response, {
    int status = 200,
  }) {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;

    // Add CORS headers for web compatibility
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add(
      'Access-Control-Allow-Methods',
      'GET, POST, OPTIONS',
    );
    request.response.headers.add(
      'Access-Control-Allow-Headers',
      'Content-Type, Authorization',
    );

    request.response.write(jsonEncode(response));
  }
}
