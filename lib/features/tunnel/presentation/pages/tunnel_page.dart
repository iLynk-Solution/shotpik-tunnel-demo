import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:http/http.dart' as http; // Add http for API call
import '../../../auth/logic/auth_manager.dart';
import '../../../tray/tray_manager.dart';
import '../../../../core/rsa_utils.dart'; // Correct level
import '../widgets/status_config_card.dart';
import '../widgets/folder_list_card.dart';
import '../widgets/add_album_dialog.dart';
import '../../domain/tunnel_models.dart';
import '../../logic/tunnel_api_service.dart';

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

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
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
        "AUTH_STATUS: App is using RSA Public Key: ${_authManager.authToken}",
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
    super.dispose();
  }

  Future<void> _fetchFoldersFromApi() async {
    if (_currentPort == null) return;

    log("UI: Fetching folder list via RSA API...");
    try {
      // Even for a list call, we use POST with empty body to verify RSA signature easily with current filter
      final bodyData = jsonEncode({});
      final signature = RSAUtils.signSHA256(
        RSAUtils.defaultPrivateKey,
        bodyData,
      );

      final response = await http.post(
        Uri.parse("http://127.0.0.1:$_currentPort/api/v1/tunnel/list"),
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
        body: jsonEncode({"tunnel_domain": domain}),
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
    if (!kDebugMode) return;
    if (!mounted) return;
    debugPrint("TUNNEL LOG: $message");
    setState(() => _logs.add(message));
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
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

  Future<int> _startServer({int bindPort = 0}) async {
    await _server?.close(force: true);
    try {
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        bindPort,
        shared: true,
      );
      final port = _server!.port;
      log("API SERVER STARTED: http://0.0.0.0:$port");
      log("Use this address for LOCAL API calls.");

      _server!.listen((HttpRequest request) async {
        try {
          final hostHeader = request.headers.value(HttpHeaders.hostHeader);
          final requestPath = Uri.decodeComponent(request.uri.path);
          log("--> ${request.method} $requestPath (Host: $hostHeader)");

          // Read the entire body to verify signature
          final bodyString = await utf8.decoder.bind(request).join();

          // --- RSA Signature Verification ---
          // Use the EXACT Public Key from assets/md/flow-authen.md
          const publicKey =
              "MIGeMA0GCSqGSIb3DQEBAQUAA4GMADCBiAKBgG1oJHc0YeN9EzTO69XWcBs95U7aQtCFvuzj8V5cSBI34x/gwtwsBkSahkh0faMzKVXFJjOl+vp46YzVlnq+W3A9Hn1FnxNe3raS0bLNx7Scz3KYM9+p9xv7cRrwzUx3rlm3QyJXGzhd3eKrHgOeVESsPr2xoRY8G/4E2qod9EJvAgMBAAE=";

          final String? signature = request.headers.value('X-Signature');

          bool isAuthorized = false;
          if (signature != null && signature.isNotEmpty) {
            try {
              // 1. Initial verification (on raw body exactly as received)
              isAuthorized = RSAUtils.verifySHA256Signature(
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

                  isAuthorized = RSAUtils.verifySHA256Signature(
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
            onAddFolder: (id, name, namePath, path) async {
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
            },
            onRemoveFolder: (id) async {
              final folderData = _sharedFolders[id];
              if (folderData != null) {
                folderData.outSub?.cancel();
                folderData.errSub?.cancel();
                folderData.process?.kill();
                setState(() => _sharedFolders.remove(id));
                _saveFolders();
              }
            },
            onUpdateWhitelist: (paths) async {
              setState(() {
                _whitelist.clear();
                _whitelist.addAll(paths);
              });
              await _saveFolders();
            },
            onStartService: _startEverything,
            onRefreshTunnel: (id) async {
              await _startTunnelForFolder(id);
            },
          );

          // Handle API requests (Always need RSA Auth, except for 'sign' which needs JWT)
          if (requestPath.startsWith('/api/v1/')) {
            final bool isSignRequest = requestPath == '/api/v1/auth/sign';

            if (isSignRequest) {
              final authHeader = request.headers.value(
                HttpHeaders.authorizationHeader,
              );
              final currentToken = _authManager.authToken;

              if (authHeader == null ||
                  !authHeader.startsWith('Bearer ') ||
                  authHeader.substring(7) != currentToken) {
                request.response.statusCode = HttpStatus.unauthorized;
                request.response.write(
                  '401 Unauthorized: Invalid or missing Bearer token.',
                );
                await request.response.close();
                return;
              }
              // If JWT is valid, we can proceed to sign
            } else if (!isAuthorized) {
              request.response.statusCode = HttpStatus.forbidden;
              request.response.write(
                '403 Forbidden: RSA Signature invalid or missing.',
              );
              await request.response.close();
              return;
            }
            await apiService.handleRequest(request, bodyString);
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

          // 2. Fallback to URL path segment (for local access)
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

          if (matchedByDomain) {
            subPath = requestPath;
          } else if (pathSegments.isNotEmpty) {
            subPath = p.joinAll(pathSegments.sublist(1));
          }

          // Strip leading slashes
          while (subPath.startsWith('/')) {
            subPath = subPath.substring(1);
          }

          final fullPath = p.join(folderData.localPath, subPath);
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
          log("Req Error: $e");
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
      'http://127.0.0.1:$_currentPort',
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

      log("UI: Calling local HTTP API to create folder...");

      try {
        final bodyData = jsonEncode({
          "name": name,
          "name_path": nameUrl,
          "path": path,
        });

        final signature = RSAUtils.signSHA256(
          RSAUtils.defaultPrivateKey,
          bodyData,
        );

        final response = await http.post(
          Uri.parse("http://127.0.0.1:$_currentPort/api/v1/create-folder"),
          headers: {
            "Content-Type": "application/json",
            "X-Signature": signature,
          },
          body: bodyData,
        );

        if (response.statusCode == 200) {
          log("API SUCCESS: Folder created via Local API call.");
          log("Output: ${response.body}");
        } else {
          log("API ERROR (${response.statusCode}): ${response.body}");
        }
      } catch (e) {
        log("UI Request Error: $e");
      }
    }
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

    log("UI: Calling local HTTP API to refresh tunnel (ID: $id)...");

    try {
      final bodyData = jsonEncode({"id": id});
      final signature = RSAUtils.signSHA256(
        RSAUtils.defaultPrivateKey,
        bodyData,
      );

      // --- Log Sample CURL for Refresh ---
      log("--- SAMPLE REFRESH CURL ---");
      log(
        "curl --location --request POST 'http://127.0.0.1:$_currentPort/api/v1/tunnel/refresh' \\",
      );
      log("--header 'Content-Type: application/json' \\");
      log("--header 'X-Signature: $signature' \\");
      log("--data '$bodyData'");
      log("---------------------------");

      final response = await http.post(
        Uri.parse("http://127.0.0.1:$_currentPort/api/v1/tunnel/refresh"),
        headers: {
          "Content-Type": "application/json",
          "X-Signature": signature,
        },
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
      log("UI: Calling local HTTP API to delete tunnel (ID: $id)...");
      try {
        final bodyData = jsonEncode({"id": id});
        final signature = RSAUtils.signSHA256(
          RSAUtils.defaultPrivateKey,
          bodyData,
        );

        // --- Log Sample CURL for Delete ---
        log("--- SAMPLE DELETE CURL ---");
        log(
          "curl --location --request POST 'http://127.0.0.1:$_currentPort/api/v1/tunnel/delete' \\",
        );
        log("--header 'Content-Type: application/json' \\");
        log("--header 'X-Signature: $signature' \\");
        log("--data '$bodyData'");
        log("---------------------------");

        final response = await http.post(
          Uri.parse("http://127.0.0.1:$_currentPort/api/v1/tunnel/delete"),
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
          _buildSidebar(context),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(context),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      spacing: 20,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StatusConfigCard(
                          isRunning: _isRunning,
                          isConnecting: _isConnecting,
                          statusMessage: _statusMessage,
                          onToggleTunnel: _handleTunnelToggle,
                          tunnelUrl: _mainTunnelUrl,
                        ),
                        if (_error != null) _buildErrorCard(),
                        Expanded(
                          flex: 3,
                          child: FolderListCard(
                            isRunning: _isRunning,
                            sharedFolders: _sharedFolders,
                            apiToken: _authManager.authToken ?? '',
                            onAddFolder: _startSharing,
                            onRemoveFolder: _removeFolder,
                            onRefreshTunnel: _refreshTunnel,
                          ),
                        ),
                        // if (kDebugMode)
                        //   Expanded(
                        //     child: DebugLogView(
                        //       logs: _logs,
                        //       scrollController: _scroll,
                        //       onClearLogs: () => setState(() => _logs.clear()),
                        //     ),
                        //   ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: Colors.red.shade700,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(
                color: Colors.red.shade700,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(32.0),
            child: Row(
              children: [
                Image.asset('assets/shotpik-agent.png', width: 40, height: 40),
                const SizedBox(width: 16),
                Text(
                  "Shotpik",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          _buildNavSection(context, "MENU"),
          _buildNavItem(context, Icons.dashboard_rounded, "Dashboard", true),
          _buildNavItem(
            context,
            Icons.history_rounded,
            "Shared History",
            false,
          ),
          _buildNavItem(context, Icons.settings_outlined, "Settings", false),
          const Spacer(),
          _buildUserCard(context),
        ],
      ),
    );
  }

  Widget _buildNavSection(BuildContext context, String title) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
        letterSpacing: 1.2,
      ),
    ),
  );

  Widget _buildNavItem(
    BuildContext context,
    IconData icon,
    String label,
    bool active,
  ) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: ListTile(
      leading: Icon(
        icon,
        size: 20,
        color: active
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: active ? FontWeight.bold : FontWeight.w500,
          color: active
              ? Theme.of(context).colorScheme.onSurface
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      selected: active,
      selectedTileColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: 0.1),
      onTap: () {},
    ),
  );

  Widget _buildUserCard(BuildContext context) {
    final email = _authManager.userData?['email'] ?? "agent@shotpik.com";
    final name =
        _authManager.userData?['name'] ??
        _authManager.userData?['sub'] ??
        "Agent User";

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.1),
            child: Icon(
              Icons.person_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Text(
                  email,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.logout_rounded,
              size: 18,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            onPressed: () => _authManager.logout(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) => Container(
    height: 80,
    padding: const EdgeInsets.symmetric(horizontal: 32),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border(
        bottom: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.05),
        ),
      ),
    ),
    child: Row(
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Tunnel Dashboard",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            Text(
              "Manage your secure album shares",
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
