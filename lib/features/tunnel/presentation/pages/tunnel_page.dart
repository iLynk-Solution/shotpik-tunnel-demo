import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:http/http.dart' as http;
import 'package:shotpik_agent/features/auth/logic/auth_manager.dart';
import 'package:shotpik_agent/features/tray/tray_manager.dart';
import 'package:shotpik_agent/core/rsa_utils.dart';
import 'package:shotpik_agent/core/app_config.dart';
import 'package:shotpik_agent/features/tunnel/domain/tunnel_models.dart';
import 'package:shotpik_agent/features/tunnel/logic/tunnel_api_service.dart';
import 'package:shotpik_agent/features/tunnel/presentation/widgets/add_album_dialog.dart';
import 'package:shotpik_agent/features/tunnel/presentation/widgets/sidebar.dart';
import 'package:shotpik_agent/features/tunnel/presentation/pages/whitelist_page.dart';
import 'package:shotpik_agent/features/tunnel/presentation/widgets/dashboard_view.dart';
import 'package:shotpik_agent/features/tunnel/presentation/pages/settings_page.dart';

class TunnelHome extends StatefulWidget {
  final AuthManager authManager;
  const TunnelHome({super.key, required this.authManager});

  @override
  State<TunnelHome> createState() => _TunnelHomeState();
}

class _TunnelHomeState extends State<TunnelHome> with WindowListener {
  AuthManager get _authManager => widget.authManager;

  HttpServer? _server;

  final Map<String, SharedFolderData> _sharedFolders = {};
  String? _error;
  String? _statusMessage;

  bool _isRunning = false; // Local Server Status
  bool _isConnecting = false;

  int? _currentPort;
  String? _mainTunnelUrl;
  Process? _mainTunnelProcess;
  final Set<String> _whitelist = {};

  static const int _namedTunnelPort = 8888;

  final List<String> _logs = [];
  final ScrollController _scroll = ScrollController();
  final ScrollController _logScroll = ScrollController();

  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _isSearching = false;


  int _selectedIndex = 0;
  final List<String> _watchFolders = [];

  @override
  void initState() {
    super.initState();
    // Add AppConfig loading logs first
    _logs.addAll(AppConfig.loadLogs);
    windowManager.addListener(this);
    windowManager.setPreventClose(
      true,
    ); // Double-ensure we intercept the close button
    AppTrayManager().setTunnelToggleCallback(() {
      _handleTunnelToggle();
    });
    AppTrayManager().setExitCallback(() {
      _exitApp();
    });
    _authManager.addListener(_onAuthChanged);
    _loadFolders();

    // Log the current RSA key being used
    if (_authManager.authToken != null) {
      log(
        "AUTH_STATUS: App is using Auth Token: ${_authManager.authToken}",
      );
    }

    // Tự động khởi động toàn bộ dịch vụ (Local Server & Cloudflare Tunnel) khi vào Trang chủ
    _startEverything();
  }

  Future<void> _loadFolders() async {
    final prefs = await SharedPreferences.getInstance();
    _mainTunnelUrl = prefs.getString('main_tunnel_url');

    final List<String>? folderList = prefs.getStringList('shared_folders');
    if (folderList != null) {
      setState(() {
        for (var item in folderList) {
          try {
            final data = jsonDecode(item);
            final name = data['name'] as String;
            final namePath =
                data['name_path']?.toString() ??
                data['nameUrl']?.toString() ??
                name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
            final path = data['path'] as String;
            final id = data['id']?.toString() ?? _generateUuid();
            final createdAtStr = data['created_at']?.toString();
            final createdAt = createdAtStr != null
                ? DateTime.tryParse(createdAtStr)
                : null;

            _sharedFolders[id] = SharedFolderData(
              id: id,
              name: name,
              namePath: namePath,
              localPath: path,
              createdAt: createdAt,
              tunnelUrl: data['url']?.toString(), // Restore previous URL
            );
          } catch (e) {
            log("Error loading folder: $e");
          }
        }
      });
    }

    // Load Whitelist
    final List<String>? whitelist = prefs.getStringList('whitelist');
    if (whitelist != null) {
      _whitelist.clear();
      _whitelist.addAll(whitelist);
    }

    // Load Watch Folders for Search API
    final List<String>? watchFolders = prefs.getStringList('watch_folders');
    if (watchFolders != null) {
      _watchFolders.clear();
      _watchFolders.addAll(watchFolders);
    }

    // Initial status info
    setState(() {
      _statusMessage ??= "Local API Ready";
    });
  }

  Future<void> _saveFolders() async {
    final prefs = await SharedPreferences.getInstance();
    if (_mainTunnelUrl != null) {
      await prefs.setString('main_tunnel_url', _mainTunnelUrl!);
    }

    await prefs.setStringList('whitelist', _whitelist.toList());

    final List<String> folderList = _sharedFolders.values.map((f) {
      return jsonEncode({
        'id': f.id,
        'name': f.name,
        'name_path': f.namePath,
        'path': f.localPath,
        'url': f.tunnelUrl, // Persist the URL too
        'created_at': f.createdAt.toIso8601String(),
      });
    }).toList();
    await prefs.setStringList('shared_folders', folderList);
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _authManager.removeListener(_onAuthChanged);
    _stopEverything(isDisposing: true);
    _server?.close(force: true);
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }



  Future<void> _handleSearchAction() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    if (_currentPort == null) return;

    setState(() => _isSearching = true);

    log("UI: Searching for '$query'...");
    
    try {
      final bodyData = jsonEncode({
        "path": query,
      });
      final signature = RSAUtils.signBody(AppConfig.rsaPrivateKey, bodyData);

      final response = await http.post(
        Uri.parse("$_localApiBase/api/v1/search"),
        headers: {"Content-Type": "application/json", "X-Signature": signature},
        body: bodyData,
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        final List<dynamic> data = body['data'] ?? [];
        setState(() {
          _searchResults = data;
          _isSearching = false;
        });
      } else {
        log("API SEARCH ERROR (${response.statusCode}): ${response.body}");
        setState(() => _isSearching = false);
      }
    } catch (e) {
      log("UI Search Request Error: $e");
      setState(() => _isSearching = false);
    }
  }

  Future<void> _startSharingForPath(String path) async {
    // If relative, make absolute relative to current dir
    String fullPath = path;
    if (!p.isAbsolute(path)) {
      fullPath = p.normalize(p.join(Directory.current.path, path));
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AddAlbumDialog(initialPath: fullPath),
    );

    if (result != null) {
      final name = result['name'] as String;
      final pathResult = result['path'] as String;
      final nameUrl = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');

      log(
        "UI: Calling local HTTP API to create tunnel for searched path (customized)...",
      );
      try {
        final bodyData = jsonEncode({
          "name": name,
          "name_path": nameUrl,
          "path": pathResult,
        });
        final signature = RSAUtils.signBody(AppConfig.rsaPrivateKey, bodyData);

        final response = await http.post(
          Uri.parse("$_localApiBase/api/v1/tunnel/create"),
          headers: {
            "Content-Type": "application/json",
            "X-Signature": signature,
          },
          body: bodyData,
        );

        if (response.statusCode == 200) {
          log("API SUCCESS: Tunnel created via Search Result.");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "Đã thêm Album thành công!",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                backgroundColor: Colors.green,
              ),
            );
            setState(() {
              _searchResults = [];
              _searchController.clear();
            });
          }
        } else {
          log("API ERROR (${response.statusCode}): ${response.body}");
          if (mounted) {
            final json = jsonDecode(response.body);
            final msg = json['message'] ?? "Lỗi không xác định";
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  msg.toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        }
      } catch (e) {
        log("UI Request Error: $e");
      }
    }
  }

  Future<void> _fetchFoldersFromApi() async {
    if (_currentPort == null) return;

    log("UI: Fetching folder list via RSA API...");
    try {
      // Even for a list call, we use POST with empty body to verify RSA signature easily with current filter
      final bodyData = jsonEncode({});
      final signature = RSAUtils.signBody(AppConfig.rsaPrivateKey, bodyData);

      final response = await http.post(
        Uri.parse("$_localApiBase/api/v1/tunnel/list"),
        headers: {"Content-Type": "application/json", "X-Signature": signature},
        body: bodyData,
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        final List<dynamic> data = body['data'];

        setState(() {
          for (var folderJson in data) {
            final String id = folderJson['id'];
            final String name = folderJson['name'];
            final String namePath = folderJson['name_path'];
            final String localPath = folderJson['path'];
            final String? tunnelUrl = folderJson['url'];

            if (_sharedFolders.containsKey(id)) {
              // Update only metadata, keep existing process/subs
              final existing = _sharedFolders[id]!;
              _sharedFolders[id] = SharedFolderData(
                id: id,
                name: name,
                namePath: namePath,
                localPath: localPath,
                tunnelUrl: tunnelUrl,
                createdAt: existing.createdAt,
                process: existing.process,
                outSub: existing.outSub,
                errSub: existing.errSub,
                isConnecting: existing.isConnecting,
              );
            } else {
              // New folder from API
              _sharedFolders[id] = SharedFolderData(
                id: id,
                name: name,
                namePath: namePath,
                localPath: localPath,
                tunnelUrl: tunnelUrl,
                createdAt: DateTime.parse(folderJson['created_at']),
              );
            }
          }
        });
        log("UI: Folders synchronized with API successfully.");
      }
    } catch (e) {
      log("UI Fetch API Error: $e");
    }
  }

  Future<void> _updateTunnelOnServer(String domain) async {
    final token = _authManager.authToken;
    if (token == null) return;

    try {
      log("API: Updating tunnel domain on server: $domain");

      final response = await http.put(
        Uri.parse("https://shotpik.com/api/v1/update-tunnel-domain"),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "tunnel_domain": domain,
          "local_ip": _localIp,
          "local_port": _currentPort,
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        log(
          "API SUCCESS from https://shotpik.com/api/v1/update-tunnel-domain: Tunnel domain updated.",
        );
        log("Response Body: ${response.body}");
      } else {
        log(
          "API ERROR from https://shotpik.com/api/v1/update-tunnel-domain. Status: ${response.statusCode}",
        );
        log("Response Body: ${response.body}");
      }
    } catch (e) {
      log("API EXCEPTION: $e");
    }
  }

  Future<void> _updateTrayMenu() async {
    await AppTrayManager().updateTrayMenu(isRunning: _isRunning);
  }

  Future<void> _exitApp() async {
    log("Exiting application gracefully...");
    await _stopEverything();
    exit(0);
  }

  @override
  void onWindowClose() async {
    log("Handling window close: Hiding to tray.");
    await windowManager.hide();
  }

  void log(String message) {
    // if (!kDebugMode) return;
    if (!mounted) return;
    debugPrint("TUNNEL LOG: $message");
    setState(() => _logs.add(message));
  }

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

  String? _localIp;

  Future<String> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return "localhost";
  }

  String get _localApiBase => "http://${_localIp ?? 'localhost'}:$_currentPort";

  Future<int> _startServer({int bindPort = 0}) async {
    await _server?.close(force: true);
    try {
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        bindPort,
        shared: true,
      );
      final port = _server!.port;
      _currentPort = port; // Sync with state
      _localIp = await _getLocalIp();
      log("API SERVER STARTED: http://$_localIp:$port (Local Network)");
      log("Use this address for LOCAL API calls.");

      _server!.listen((HttpRequest request) async {
        try {
          final hostHeader = request.headers.value(HttpHeaders.hostHeader);
          final requestPath = Uri.decodeComponent(request.uri.path);
          log("--> ${request.method} $requestPath (Host: $hostHeader)");

          // Read the entire body to verify signature
          final bodyString = await utf8.decoder.bind(request).join();

          // Use the Public Key from AppConfig or Environment
          final String publicKey = AppConfig.rsaPublicKey;

          final String? signature = request.headers.value('X-Signature');

          bool isAuthorized = false;
          if (signature != null && signature.isNotEmpty) {
            try {
              // 1. Initial verification (on raw body exactly as received)
              isAuthorized = RSAUtils.verifySignature(
                publicKey,
                bodyString,
                signature,
              );

              // 2. Fallback: Robust verification for formatted JSON
              if (!isAuthorized) {
                try {
                  // Attempt to decode and re-encode in MINIFIED (compact) format
                  final dynamic decoded = jsonDecode(bodyString);
                  final minifiedBody = jsonEncode(decoded);

                  isAuthorized = RSAUtils.verifySignature(
                    publicKey,
                    minifiedBody,
                    signature,
                  );
                  if (isAuthorized) {
                    log("RSA: SUCCESS using Minified JSON normalization.");
                  }
                } catch (_) {
                  // Not valid JSON or can't minify, no problem
                }
              }

              if (isAuthorized) {
                log("API: RSA Signature verified successfully.");
              } else {
                log("API: RSA Signature INVALID.");
                log("DEBUG Path: $requestPath");
                log("DEBUG Signature Received: $signature");
                log(
                  "DEBUG Body Received (Len: ${bodyString.length}): |$bodyString|",
                );
              }
            } catch (e) {
              log("API RSA Error: $e");
            }
          }

          final apiService = TunnelApiService(
            sharedFolders: _sharedFolders,
            whitelist: _whitelist,
            mainTunnelUrl: _mainTunnelUrl,
            onLog: log,
            onAddFolder: _registerLocalFolder,
            onUpdateWhitelist: (paths) async {
              log("UI Callback: onUpdateWhitelist - Start (New length: ${paths.length})");
              setState(() {
                _whitelist.clear();
                _whitelist.addAll(paths);
              });
              log("UI Callback: onUpdateWhitelist - State set. Saving...");
              await _saveFolders();
              log("UI Callback: onUpdateWhitelist - Done.");
            },
            onUpdateSession: (token) async {
              await _authManager.updateSession(token);
            },
            onRemoveFolder: (id) async {
              final folderData = _sharedFolders[id];
              if (folderData != null) {
                folderData.outSub?.cancel();
                folderData.errSub?.cancel();
                folderData.process?.kill();
                setState(() {
                  _whitelist.remove(folderData.namePath);
                  _sharedFolders.remove(id);
                });
                _saveFolders();
              }
            },
            onStartService: _startEverything,
            onRefreshTunnel: (id) async {
              await _startTunnelForFolder(id);
            },
            watchFolders: _watchFolders,
          );

          // Handle API requests (Always need RSA Auth, except for 'sign' which needs JWT and 'verify' which can report its own fail)
          // /file/ is a public endpoint handled by apiService
          if (requestPath == '/healthcheck' ||
              requestPath.startsWith('/api/v1/') ||
              requestPath.startsWith('/file/')) {
            final bool isSignRequest = requestPath == '/api/v1/auth/sign';
            final bool isVerifyRequest = requestPath == '/api/v1/auth/verify';
            final bool isCallbackRequest = requestPath == '/api/v1/auth/callback';
            final bool isFileRequest = requestPath.startsWith('/file/');

            if (isSignRequest) {
              final authHeader = request.headers.value(
                HttpHeaders.authorizationHeader,
              );

              if (authHeader == null || !authHeader.startsWith('Bearer ')) {
                log("API: auth/sign - Refused: Missing Bearer token.");
                request.response.statusCode = HttpStatus.unauthorized;
                request.response.write(
                  '401 Unauthorized: Invalid or missing Bearer token.',
                );
                await request.response.close();
                return;
              }
              // If we have a Bearer token, we allow signing.
              // We don't strictly match currentToken to allow sessions to sync/refresh.
            } else if (!isAuthorized &&
                !isVerifyRequest &&
                !isCallbackRequest &&
                !isFileRequest &&
                requestPath != '/healthcheck') {
              request.response.statusCode = HttpStatus.forbidden;
              request.response.write(
                '403 Forbidden: RSA Signature invalid or missing.',
              );
              await request.response.close();
              return;
            }
            await apiService.handleRequest(
              request,
              bodyString,
              isAuthorized: isAuthorized,
            );
            return;
          }

          final pathSegments = requestPath
              .split('/')
              .where((s) => s.isNotEmpty)
              .toList();

          SharedFolderData? folderData;

          // 1. Identify folder by matching the random domain from Host Header
          if (hostHeader != null && hostHeader.isNotEmpty) {
            final hostOnly = hostHeader.split(':')[0].toLowerCase();

            // First, check if it's the main tunnel for API Gateway
            bool isMainTunnel = false;
            if (_mainTunnelUrl != null && _mainTunnelUrl!.contains(hostOnly)) {
              isMainTunnel = true;
            }

            if (!isMainTunnel) {
              for (var f in _sharedFolders.values) {
                if (f.tunnelUrl != null && f.tunnelUrl!.contains(hostOnly)) {
                  folderData = f;
                  break;
                }
              }
            }
          }

          // 2. Fallback to URL path segment (for local access or slug-based URL)
          if (folderData == null && pathSegments.isNotEmpty) {
            final virtualName = pathSegments[0];
            folderData = _sharedFolders[virtualName];
            if (folderData == null) {
              for (var f in _sharedFolders.values) {
                if (f.namePath == virtualName || f.name == virtualName) {
                  folderData = f;
                  break;
                }
              }
            }
          }

          // 3. Fallback: Match by absolute localPath prefix (for Direct Absolute Path access)
          if (folderData == null) {
            for (var f in _sharedFolders.values) {
              if (requestPath.startsWith(f.localPath)) {
                folderData = f;
                break;
              }
            }
          }

          if (folderData == null) {
            // Check if it's the main tunnel (API gateway) but no subpath
            bool isMain =
                _mainTunnelUrl != null &&
                hostHeader != null &&
                _mainTunnelUrl!.contains(hostHeader.split(':')[0]);

            if (isMain && pathSegments.isEmpty) {
              request.response.statusCode = HttpStatus.ok;
              request.response.write('API Gateway Online');
              await request.response.close();
              return;
            }

            request.response.statusCode = HttpStatus.notFound;
            request.response.write(
              '404 Not Found: Album not found or link expired.',
            );
            await request.response.close();
            return;
          }

          // Resolve subPath within the folder
          String subPath = "";
          final hostOnly = hostHeader?.split(':')[0].toLowerCase();
          bool matchedByDomain =
              hostOnly != null &&
              folderData.tunnelUrl != null &&
              folderData.tunnelUrl!.contains(hostOnly);

          bool matchedByAbsolutePath = false;
          for (var f in _sharedFolders.values) {
            if (requestPath.startsWith(f.localPath)) {
              matchedByAbsolutePath = true;
              break;
            }
          }

          if (matchedByDomain || matchedByAbsolutePath) {
            subPath = requestPath;
          } else if (pathSegments.isNotEmpty) {
            subPath = p.joinAll(pathSegments.sublist(1));
          }

          // Strip leading slashes ONLY for relative paths (to avoid p.join issues)
          // But preserve it if it's potentially an absolute path we want to match
          if (subPath.startsWith('/') && !subPath.startsWith(folderData.localPath)) {
            subPath = subPath.substring(1);
          }

          // Resolve the physical absolute path on disk
          String fullPath;
          if (subPath.startsWith(folderData.localPath)) {
            fullPath = subPath; // User requested absolute path via URL
          } else {
             fullPath = p.join(folderData.localPath, subPath); // User requested relative path via slug
          }
          
          final entityType = FileSystemEntity.typeSync(fullPath);
          final bool isFileRequest = entityType == FileSystemEntityType.file;

          // AUTH CHECK:
          // Bypass ONLY for FILES if folder namePath is in whitelist.
          // Folders (directory listing) ALWAYS REQUIRE Authorization.
          bool canAccess =
              isAuthorized ||
              (isFileRequest && _whitelist.contains(folderData.namePath));

          if (!canAccess) {
            request.response.statusCode = HttpStatus.forbidden;
            request.response.write(
              '403 Forbidden: Token không hợp lệ hoặc không có quyền truy cập thư mục.',
            );
            await request.response.close();
            return;
          }

          log(
            "Matched: ${folderData.name} - File: $isFileRequest - Auth Bypassed: ${!isAuthorized}",
          );

          if (isFileRequest) {
            final file = File(fullPath);
            request.response.headers.contentType = _getContentType(fullPath);
            await request.response.addStream(file.openRead());
          } else if (entityType == FileSystemEntityType.directory) {
            if (!request.uri.path.endsWith('/')) {
              await request.response.redirect(
                Uri.parse('${request.uri.path}/'),
              );
              return;
            }
            await _renderFolderContent(request, folderData, pathSegments);
          } else {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write('404 Not Found');
          }
        } catch (e) {
          log("Local Server Error: $e");
        } finally {
          try {
            await request.response.close();
          } catch (_) {}
        }
      });
      return port;
    } catch (e) {
      log("ERROR starting server: $e");
      rethrow;
    }
  }

  Future<void> _renderFolderContent(
    HttpRequest request,
    SharedFolderData folder,
    List<String> segments,
  ) async {
    final relPathInFolder = p.joinAll(segments.sublist(1));
    final fullPath = p.join(folder.localPath, relPathInFolder);
    final entities = (await Directory(fullPath).list().toList())
        .where((e) => !p.basename(e.path).startsWith('.'))
        .toList();

    final currentToken = request.uri.queryParameters['token'];
    final tokenSuffix = currentToken != null ? '?token=$currentToken' : '';

    final buffer = StringBuffer();
    buffer.write(
      '<!DOCTYPE html><html><head><meta charset="utf-8"><title>${folder.name}</title>',
    );
    buffer.write(_getSharedStyles());
    buffer.write(
      '</head><body><div class="header"><h1>${folder.name}</h1></div><div class="gallery-grid">',
    );

    for (final entity in entities) {
      final name = p.basename(entity.path);
      final isDir = entity is Directory;
      final urlName = Uri.encodeComponent(name) + (isDir ? '/' : '');
      buffer.write('<a href="$urlName$tokenSuffix" class="card">');
      buffer.write('<div class="info"><div class="name">$name</div></div></a>');
    }
    buffer.write('</div></body></html>');

    request.response.headers.contentType = ContentType.html;
    request.response.write(buffer.toString());
  }

  String _getSharedStyles() =>
      '<style>body{font-family:sans-serif;background:#f8fafc;padding:20px;}.gallery-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:20px;}.card{background:white;padding:15px;border-radius:12px;text-decoration:none;color:inherit;border:1px solid #e2e8f0;}</style>';

  Future<void> _handleTunnelToggle() async {
    if (_isRunning || _isConnecting) {
      await _stopEverything(clearFolders: false);
    } else {
      await _startEverything();
    }
  }

  Future<void> _startEverything() async {
    setState(() {
      _isConnecting = true;
      _statusMessage = 'Starting Service...';
    });
    try {
      // Proactively kill any zombie cloudflared processes from previous crashes
      if (Platform.isMacOS) {
        await Process.run('killall', ['cloudflared']);
      }

      if (_server == null) {
        final port = await _startServer(bindPort: _namedTunnelPort);
        _currentPort = port;
      }

      await _fetchFoldersFromApi();

      setState(() {
        _isRunning = true;
        _statusMessage = 'Service Ready';
      });

      _startMainTunnel(); // Start primary API tunnel

      // We do NOT auto-start all folder tunnels here anymore to avoid 429
      // They will start when needed or manually.
      _updateTrayMenu();
    } catch (e) {
      setState(() {
        _error = "Service fail: $e";
        _isConnecting = false;
        _isRunning = false;
      });
    }
  }

  Future<void> _startMainTunnel() async {
    final String exePath = Platform.resolvedExecutable;
    String cloudflaredPath;
    if (Platform.isMacOS) {
      final appDir = File(exePath).parent.parent.path;
      cloudflaredPath =
          "$appDir/Frameworks/App.framework/Resources/flutter_assets/assets/bin/cloudflared";
    } else {
      final appDir = File(exePath).parent.path;
      cloudflaredPath = "$appDir/data/flutter_assets/assets/bin/cloudflared";
      if (Platform.isWindows) cloudflaredPath += ".exe";
    }

    if (!File(cloudflaredPath).existsSync()) return;

    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', cloudflaredPath]);
    }

    final List<String> args = [
      'tunnel',
      '--no-autoupdate',
      '--url',
      'http://localhost:$_currentPort',
    ];

    _mainTunnelProcess = await Process.start(cloudflaredPath, args);

    _mainTunnelProcess!.stdout
        .transform(SystemEncoding().decoder)
        .listen((data) => _processMainTunnelLog(data));
    _mainTunnelProcess!.stderr
        .transform(SystemEncoding().decoder)
        .listen((data) => _processMainTunnelLog(data));
  }

  void _processMainTunnelLog(String data) {
    log("[GATEWAY] $data");

    if (data.contains("429 Too Many Requests") ||
        data.contains("error code: 1015")) {
      setState(() {
        _error = "Cloudflare Rate Limit: Vui lòng đợi 5-10 phút rồi thử lại.";
        _isConnecting = false;
        _isRunning = false;
      });
      _mainTunnelProcess?.kill();
      return;
    }

    // Check for random trycloudflare URL
    final match = RegExp(
      r'https://[a-zA-Z0-9\-]+\.trycloudflare\.com',
    ).firstMatch(data);
    if (match != null) {
      setState(() {
        _mainTunnelUrl = match.group(0);
        _isConnecting = false;
        _saveFolders();

        // Notify Shotpik Server
        _updateTunnelOnServer(match.group(0)!);
      });
      return;
    }
  }

  final Map<String, Completer<String>> _tunnelCompleters = {};

  Future<String?> _startTunnelForFolder(String folderName) async {
    final folderData = _sharedFolders[folderName];
    if (folderData == null) return "Error: Folder not found";

    // If we already have a process running, just return the current URL or future
    if (folderData.process != null) {
      if (folderData.tunnelUrl != null) {
        return folderData.tunnelUrl;
      }
      if (_tunnelCompleters.containsKey(folderName)) {
        return _tunnelCompleters[folderName]!.future;
      }
    }

    // Stop existing process if any before starting new one (Regenerate)
    folderData.outSub?.cancel();
    folderData.errSub?.cancel();
    folderData.process?.kill();
    folderData.process = null;

    setState(() {
      folderData.isConnecting = true;
      folderData.tunnelUrl = null;
    });

    final String exePath = Platform.resolvedExecutable;
    String cloudflaredPath;
    if (Platform.isMacOS) {
      final appDir = File(exePath).parent.parent.path;
      cloudflaredPath =
          "$appDir/Frameworks/App.framework/Resources/flutter_assets/assets/bin/cloudflared";
    } else {
      final appDir = File(exePath).parent.path;
      cloudflaredPath = "$appDir/data/flutter_assets/assets/bin/cloudflared";
      if (Platform.isWindows) cloudflaredPath += ".exe";
    }

    if (!File(cloudflaredPath).existsSync()) {
      setState(() => folderData.isConnecting = false);
      return "Error: cloudflared missing";
    }

    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', cloudflaredPath]);
    }

    final process = await Process.start(cloudflaredPath, [
      'tunnel',
      '--no-autoupdate',
      '--url',
      '$_localApiBase',
    ]);

    folderData.process = process;
    folderData.outSub = process.stdout
        .transform(SystemEncoding().decoder)
        .listen((data) => _processFolderTunnelLog(folderName, data));
    folderData.errSub = process.stderr
        .transform(SystemEncoding().decoder)
        .listen((data) => _processFolderTunnelLog(folderName, data));

    final completer = Completer<String>();
    _tunnelCompleters[folderName] = completer;

    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        _tunnelCompleters.remove(folderName);
        if (mounted) setState(() => folderData.isConnecting = false);
        return "Timeout (Cloudflare Busy)";
      },
    );
  }

  void _processFolderTunnelLog(String folderName, String data) {
    log("[$folderName] $data");
    final folderData = _sharedFolders[folderName];
    if (folderData == null) return;

    if (data.contains("429 Too Many Requests") ||
        data.contains("error code: 1015")) {
      if (mounted) {
        setState(() {
          folderData.isConnecting = false;
          folderData.tunnelUrl = "IP bị giới hạn (Đợi 5p)";
        });
      }
      _tunnelCompleters.remove(folderName)?.complete("Rate Limited");
      return;
    }

    final match = RegExp(
      r'https://[a-zA-Z0-9\-]+\.trycloudflare\.com',
    ).firstMatch(data);
    if (match != null) {
      if (mounted) {
        final baseUrl = match.group(0)!;
        setState(() {
          folderData.tunnelUrl = "$baseUrl/";
          folderData.isConnecting = false;
        });
        _saveFolders();
        _tunnelCompleters.remove(folderName)?.complete("$baseUrl/");
      }
    }
  }

  Future<void> _startSharing() async {
    if (!_isRunning) return;
    if (_currentPort == null) {
      log("Error: Server port not available.");
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const AddAlbumDialog(),
    );

    if (result != null) {
      final name = result['name'] as String;
      final path = result['path'] as String;
      final nameUrl = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');

      log("UI: Calling local HTTP API to create tunnel...");
      try {
        final bodyData = jsonEncode({
          "name": name,
          "name_path": nameUrl,
          "path": path,
        });

        final signature = RSAUtils.signBody(AppConfig.rsaPrivateKey, bodyData);

        final response = await http.post(
          Uri.parse("$_localApiBase/api/v1/tunnel/create"),
          headers: {
            "Content-Type": "application/json",
            "X-Signature": signature,
          },
          body: bodyData,
        );

        if (response.statusCode == 200) {
          log("API SUCCESS: Tunnel created via Local API call.");
        } else {
          log("API ERROR (${response.statusCode}): ${response.body}");
          if (mounted) {
            String errorMessage = "Lỗi khi tạo tunnel (${response.statusCode})";
            try {
              final json = jsonDecode(response.body);
              if (json['message'] != null) {
                errorMessage = json['message'].toString().replaceFirst(
                  "Error: ",
                  "",
                );
              }
            } catch (_) {}

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  errorMessage,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                backgroundColor: Colors.redAccent,
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.all(20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          }
        }
      } catch (e) {
        log("UI Request Error: $e");
      }
    }
  }

  Future<String?> _registerLocalFolder(
    String id,
    String name,
    String namePath,
    String path,
  ) async {
    if (!Directory(path).existsSync()) {
      return "Error: Local path does not exist: $path";
    }
    setState(() {
      _sharedFolders[id] = SharedFolderData(
        id: id,
        name: name,
        namePath: namePath,
        localPath: path,
      );
    });
    _saveFolders();
    return await _startTunnelForFolder(id);
  }

  Future<void> _refreshTunnel(String id) async {
    if (_currentPort == null) return;

    // Set connecting status locally first for immediate UI feedback
    setState(() {
      final folder = _sharedFolders[id];
      if (folder != null) {
        folder.isConnecting = true;
        folder.tunnelUrl = null;
      }
    });

    final folder = _sharedFolders[id];
    if (folder == null) return;
    final folderPath = folder.localPath;

    log("UI: Calling local HTTP API to refresh tunnel (Path: $folderPath)...");

    try {
      final bodyData = jsonEncode({"path": folderPath});
      final signature = RSAUtils.signBody(AppConfig.rsaPrivateKey, bodyData);

      // --- Log Sample CURL for Refresh ---
      log("--- SAMPLE REFRESH CURL ---");
      log(
        "curl --location --request POST '$_localApiBase/api/v1/tunnel/refresh' \\",
      );
      log("--header 'Content-Type: application/json' \\");
      log("--header 'X-Signature: $signature' \\");
      log("--data '$bodyData'");
      log("---------------------------");

      final response = await http.post(
        Uri.parse("$_localApiBase/api/v1/tunnel/refresh"),
        headers: {"Content-Type": "application/json", "X-Signature": signature},
        body: bodyData,
      );

      if (response.statusCode == 200) {
        log("API SUCCESS: Tunnel refresh triggered via Local API.");
      } else {
        log("API ERROR (${response.statusCode}): ${response.body}");
        // Revert status on error
        setState(() {
          final folder = _sharedFolders[id];
          if (folder != null) {
            folder.isConnecting = false;
          }
        });
      }
    } catch (e) {
      log("UI Refresh Request Error: $e");
    }
  }

  void _removeFolder(String id) async {
    final folder = _sharedFolders[id];
    if (folder == null) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Xác nhận xóa"),
        content: Text(
          "Bạn có chắc chắn muốn ngừng chia sẻ thư mục '${folder.name}'? Link này sẽ không thể truy cập được nữa.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Hủy", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text("Xóa"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      log(
        "UI: Calling local HTTP API to delete tunnel (Path: ${folder.localPath})...",
      );
      try {
        final bodyData = jsonEncode({"path": folder.localPath});
        final signature = RSAUtils.signBody(AppConfig.rsaPrivateKey, bodyData);

        // --- Log Sample CURL for Delete ---
        log("--- SAMPLE DELETE CURL ---");
        log(
          "curl --location --request POST '$_localApiBase/api/v1/tunnel/delete' \\",
        );
        log("--header 'Content-Type: application/json' \\");
        log("--header 'X-Signature: $signature' \\");
        log("--data '$bodyData'");
        log("---------------------------");

        final response = await http.post(
          Uri.parse("$_localApiBase/api/v1/tunnel/delete"),
          headers: {
            "Content-Type": "application/json",
            "X-Signature": signature,
          },
          body: bodyData,
        );

        if (response.statusCode == 200) {
          log("API SUCCESS: Tunnel deleted via Local API call.");
          // Update the UI after successful API call
          setState(() {
            _sharedFolders.remove(id);
          });
          _saveFolders();
        } else {
          log("API DELETE ERROR (${response.statusCode}): ${response.body}");
        }
      } catch (e) {
        log("UI Delete Request Error: $e");
      }
    }
  }

  ContentType _getContentType(String path) {
    final ext = p.extension(path).toLowerCase();
    if (ext == '.png') return ContentType('image', 'png');
    if (ext == '.jpg' || ext == '.jpeg') return ContentType('image', 'jpeg');
    return ContentType.binary;
  }

  Future<void> _stopEverything({
    bool clearFolders = false,
    bool isDisposing = false,
  }) async {
    for (final folder in _sharedFolders.values) {
      folder.outSub?.cancel();
      folder.errSub?.cancel();
      folder.process?.kill();
      folder.process = null;
      folder.isConnecting = false;
    }
    _mainTunnelProcess?.kill();
    _mainTunnelProcess = null;

    if (!isDisposing && mounted) {
      setState(() {
        _isRunning = false;
        _isConnecting = false;
        if (clearFolders) _sharedFolders.clear();
      });
      _updateTrayMenu();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Row(
        children: [
          TunnelSidebar(
            selectedIndex: _selectedIndex,
            onIndexChanged: (idx) => setState(() => _selectedIndex = idx),
            userName:
                _authManager.userData?['name'] ?? _authManager.userData?['sub'],
            userEmail: _authManager.userData?['email'],
            onLogout: () => _authManager.logout(),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(color: Colors.white),
              clipBehavior: Clip.antiAlias,
              child: () {
                switch (_selectedIndex) {
                  case 0:
                    return DashboardView(
                      scrollController: _scroll,
                      logScrollController: _logScroll,
                      logs: _logs,
                      onClearLogs: () => setState(() => _logs.clear()),
                      searchController: _searchController,
                      onSearch: _handleSearchAction,
                      isSearching: _isSearching,
                      onClearSearch: () {
                        _searchController.clear();
                        setState(() => _searchResults = []);
                      },
                      isRunning: _isRunning,
                      error: _error,
                      searchResults: _searchResults,
                      onClearSearchResults: () =>
                          setState(() => _searchResults = []),
                      onStartSharingForPath: _startSharingForPath,
                      sharedFolders: _sharedFolders,
                      apiToken: _authManager.authToken ?? '',
                      whitelist: _whitelist,
                      onAddFolder: _startSharing,
                      onRemoveFolder: _removeFolder,
                      onRefreshTunnel: _refreshTunnel,
                      localApiBase: _localApiBase,
                    );
                  case 1:
                    return WhitelistPage(
                      whitelist: _whitelist,
                      sharedFolders: _sharedFolders,
                      logs: _logs,
                      logScrollController: _logScroll,
                      onClearLogs: () => setState(() => _logs.clear()),
                      localApiBase: _localApiBase,
                    );
                  case 2:
                    return SettingsPage(
                      isRunning: _isRunning,
                      isConnecting: _isConnecting,
                      statusMessage: _statusMessage,
                      onToggleTunnel: _handleTunnelToggle,
                      tunnelUrl: _mainTunnelUrl,
                      onWatchFoldersChanged: (folders) {
                        _watchFolders.clear();
                        _watchFolders.addAll(folders);
                      },
                    );
                  default:
                    return const Center(child: Text("Page Not Found"));
                }
              }(),
            ),
          ),
        ],
      ),
    );
  }
}
