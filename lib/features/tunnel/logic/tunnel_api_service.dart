import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'package:shotpik_agent/core/rsa_utils.dart';
import 'package:shotpik_agent/core/app_config.dart';
import 'package:shotpik_agent/features/tunnel/domain/tunnel_models.dart';

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
  final List<String> watchFolders;

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
    required this.watchFolders,
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
        _sendJsonResponse(
          request,
          {"success": false, "message": "Missing 'path' query"},
          status: 400,
        );
        return;
      }

      if (watchFolders.isEmpty) {
        onLog("API Search Warning: 'watch_folders' is empty in server.");
        _sendJsonResponse(request, {"success": true, "data": []});
        return;
      }

      final List<Map<String, String>> results = [];
      onLog(
        "API: Searching for matching folders in ${watchFolders.length} roots...",
      );

      for (final rootPath in watchFolders) {
        final rootDir = Directory(rootPath);
        if (!rootDir.existsSync()) {
          onLog("API Search: Root $rootPath does not exist, skipping.");
          continue;
        }

        // Perform safe manual recursive search for each root
        final List<Directory> queue = [rootDir];
        int processedCount = 0;

        while (queue.isNotEmpty && results.length < 50 && processedCount < 1000) {
          final currentDir = queue.removeAt(0);
          processedCount++;

          try {
            await for (final entity in currentDir.list(
              recursive: false,
              followLinks: false,
            )) {
              if (entity is Directory) {
                final path = entity.path;
                final name = p.basename(path);

                // Skip hidden folders and system/protected folders
                if (name.startsWith('.') ||
                    name == 'Library' ||
                    name == 'Applications' ||
                    name == 'System' ||
                    name == 'node_modules') continue;

                if (name.toLowerCase().contains(query.toLowerCase())) {
                  results.add({"path": entity.absolute.path, "type": "folder"});
                }

                // Add to queue if results not full yet
                if (results.length < 50) {
                  queue.add(entity);
                }
              }
              if (results.length >= 50) break;
            }
          } catch (e) {
            // Ignore individual listing errors
          }
        }
        if (results.length >= 50) break;
      }

      _sendJsonResponse(request, {"success": true, "data": results});
    } catch (e) {
      onLog("API Search Error: $e");
      _sendJsonResponse(
        request,
        {"success": false, "message": e.toString()},
        status: 500,
      );
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
        String publicUrl = "";
        if (mainTunnelUrl != null && folder != null) {
          final cleanMain = mainTunnelUrl!.endsWith('/')
              ? mainTunnelUrl!.substring(0, mainTunnelUrl!.length - 1)
              : mainTunnelUrl;
          publicUrl = "$cleanMain${folder.localPath}/";
        }

        results.add({
          "name": folder?.name ?? "",
          "path": folder?.localPath ?? namePathItem,
          "name_path": namePathItem, // Added name_path explicitly
          "type": "folder",
          "url": folder?.tunnelUrl ?? "",
          "public_url": publicUrl, // Direct gateway access
          "status": (folder?.isConnecting ?? false)
              ? "connecting"
              : (folder != null && folder.tunnelUrl != null ? "online" : "offline"),
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
        // Enforce identification by ABSOLUTE Physical Local Path only
        if (p.canonicalize(f.localPath) == p.canonicalize(path)) {
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
            "path": foundFolder.localPath,
            "url": foundFolder.tunnelUrl ?? "",
            "public_url": mainTunnelUrl != null
                ? "${mainTunnelUrl!.endsWith('/') ? mainTunnelUrl!.substring(0, mainTunnelUrl!.length - 1) : mainTunnelUrl}${foundFolder.localPath}/"
                : "",
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

      // Enforce identification by ABSOLUTE Physical Local Path only
      for (var f in sharedFolders.values) {
        if (p.canonicalize(f.localPath) == p.canonicalize(path)) {
          folder = f;
          namePathToRemove = f.namePath;
          break;
        }
      }

      if (folder == null || !whitelist.contains(namePathToRemove)) {
        _sendJsonResponse(request, {
          "success": false,
          "message": "Whitelisted Folder not found by absolute path: $path",
        }, status: 404);
        return;
      }

      final List<String> currentWhitelist = whitelist.toList();
      currentWhitelist.remove(namePathToRemove);
      onLog("API: Updating whitelist in app state...");
      await onUpdateWhitelist(currentWhitelist);
      onLog("API: App state whitelist updated. Sending response...");

      _sendJsonResponse(request, {
        "success": true,
        "message": "Removed from whitelist",
        "data": {
          "name": folder.name,
          "path": folder.localPath, // Absolute local path
          "url": folder.tunnelUrl ?? "",
          "public_url": mainTunnelUrl != null
              ? "${mainTunnelUrl!.endsWith('/') ? mainTunnelUrl!.substring(0, mainTunnelUrl!.length - 1) : mainTunnelUrl}${folder.localPath}/"
              : "",
          "created_at": folder.createdAt.toIso8601String(),
        },
      });
      onLog("API: Response sent to response buffer.");
      onLog(
        "API: DELETE /api/v1/whitelist/delete - Done: $namePathToRemove",
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
      final String? destPath = body['path']; // 'path' is now the destination
      final List<dynamic>? filesInput = body['files'];

      if (destPath == null || destPath.isEmpty) {
        _sendJsonResponse(request, {
          "success": false,
          "message": "Missing 'path' (destination folder)",
        }, status: 400);
        return;
      }

      // Convert dynamic list to String list of absolute paths
      final List<String> filesToProcess = (filesInput ?? []).map((e) => e.toString()).toList();

      if (filesToProcess.isEmpty) {
         _sendJsonResponse(request, {
          "success": false,
          "message": "Files list is empty. Provide full absolute paths to whitelisted files.",
        }, status: 400);
        return;
      }

      // 1. Whitelist Check for EVERY file
      for (final filePath in filesToProcess) {
        bool isWhitelisted = false;
        // Check if filePath starts with any whitelisted folder's localPath
        for (var f in sharedFolders.values) {
          if (filePath.startsWith(f.localPath) && whitelist.contains(f.namePath)) {
            isWhitelisted = true;
            break;
          }
        }

        if (!isWhitelisted) {
          _sendJsonResponse(request, {
            "success": false,
            "message": "Forbidden: File '$filePath' is not within any whitelisted shared folder.",
          }, status: 403);
          onLog("API: Create-folder REJECTED. File not whitelisted: $filePath");
          return;
        }
      }

      // 2. Create destination folder (Ensure parent exists)
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

      // 3. Create shortcut (symlink) into destination folder
      for (final filePath in filesToProcess) {
        final sourceFile = File(filePath);
        if (await sourceFile.exists()) {
          final fileName = p.basename(sourceFile.path);
          // Preserve relative structure? If we want session-001/sub/a.jpg
          // The user example had "public/uploads/a.pdf".
          // If the input was absolute, we'll just use the filename for now.
          final targetLinkPath = p.join(dir.path, fileName);
          final link = Link(targetLinkPath);

          if (await link.exists()) {
             await link.delete();
          }
          await link.create(sourceFile.absolute.path);
          onLog("API: Created symlink for $fileName -> ${sourceFile.absolute.path}");
        } else {
          onLog("API: Warning - Source file not found: $filePath");
        }
      }

      // 4. Send successful response
      _sendJsonResponse(request, {
        "success": true,
        "path": destPath,
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
            "path": path, // Absolute local path
            "name_path": namePath, // Added name_path explicitly
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
            "path": f.localPath,
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

      // 1. Try matching by absolute localPath (Check if 'id' starts with any localPath)
      for (var f in sharedFolders.values) {
        if (id.startsWith(f.localPath)) {
          foundFolder = f;
          subPathInFolder = p.relative(id, from: f.localPath);
          if (subPathInFolder == ".") subPathInFolder = "";
          break;
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

        if (foundFolder.tunnelUrl != null) {
          String url = foundFolder.tunnelUrl!;
          if (url.endsWith('/')) url = url.substring(0, url.length - 1);
          
          final String fullPathForUrl = e.path.startsWith('/') ? e.path : '/${e.path}';
          item["url"] = url + fullPathForUrl.replaceAll('\\', '/');
          if (isDir && !item["url"].endsWith('/')) item["url"] += '/';
        }

        // Add Public Gateway URL only if this folder is whitelisted
        if (whitelist.contains(foundFolder.namePath) && mainTunnelUrl != null) {
          String gateway = mainTunnelUrl!;
          if (gateway.endsWith('/')) gateway = gateway.substring(0, gateway.length - 1);
          
          final String fullPathForGateway = e.path.startsWith('/') ? e.path : '/${e.path}';
          item["public_url"] = gateway + fullPathForGateway.replaceAll('\\', '/');
          if (isDir && !item["public_url"].endsWith('/')) item["public_url"] += '/';
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
