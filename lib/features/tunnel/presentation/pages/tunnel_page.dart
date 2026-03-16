import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

import '../../../auth/logic/auth_manager.dart';
import '../widgets/status_config_card.dart';
import '../widgets/folder_list_card.dart';
import '../widgets/debug_log_view.dart';

class TunnelHome extends StatefulWidget {
  const TunnelHome({super.key});

  @override
  State<TunnelHome> createState() => _TunnelHomeState();
}

class _TunnelHomeState extends State<TunnelHome> with WindowListener {
  final SystemTray _systemTray = SystemTray();
  final AppWindow _appWindow = AppWindow();
  final Menu _menu = Menu();
  final AuthManager _authManager = AuthManager();

  HttpServer? _server;
  Process? _tunnelProcess;
  StreamSubscription? _tunnelOutSub;
  StreamSubscription? _tunnelErrSub;

  final Map<String, String> _sharedFolders = {}; // {VirtualName: LocalPath}
  String? _tunnelUrl;
  String? _error;
  String? _statusMessage;

  bool _isRunning = false;
  bool _isConnecting = false;
  bool _shouldRestart = false;

  int _retryCount = 0;
  static const int _maxRetries = 5;
  int? _currentPort;

  // ── Named tunnel config ──────────────────────────────────────────────
  static const String _tunnelToken =
      'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJodHRwczovL3Nob3RwaWsuY29tL2FwaS92MS9hdXRoL2xvZ2luIiwiaWF0IjoxNzczNjMzMTMyLCJleHAiOjE3NzQyMzc5MzIsIm5iZiI6MTc3MzYzMzEzMiwianRpIjoidkExeGh4M1BzbTEzVlBNaiIsInN1YiI6IjE0MzQ5IiwicHJ2IjoiMjNiZDVjODk0OWY2MDBhZGIzOWU3MDFjNDAwODcyZGI3YTU5NzZmNyIsImVtYWlsIjoidHV5ZW50Yi5naXRsYWJAZ21haWwuY29tIn0.NzqHWLT9_SMurtr2tA6rM_q1VKWhdX8_w4XWTXzKHYI';
  static const String _tunnelDomain = 'https://shotpik-tunnel.tuyendev.store';
  static const int _namedTunnelPort = 8080;

  // Thông tin bảo mật (Bearer Token)
  static const String _apiToken = _tunnelToken;
  // ─────────────────────────────────────────────────────────────────────

  final List<String> _logs = [];
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    initSystemTray();
    _authManager.loadSavedSession();
    _authManager.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _authManager.removeListener(_onAuthChanged);
    _authManager.dispose();
    _stopEverything();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> initSystemTray() async {
    String iconPath = Platform.isWindows
        ? 'assets/app_icon.ico'
        : 'assets/shotpik-agent.png';

    await _systemTray.initSystemTray(iconPath: iconPath);
    await _updateTrayMenu();

    _systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        _appWindow.show();
      } else if (eventName == kSystemTrayEventRightClick) {
        _systemTray.popUpContextMenu();
      }
    });
  }

  Future<void> _updateTrayMenu() async {
    await _menu.buildFrom([
      MenuItemLabel(
        label: _isRunning ? 'Status: ONLINE' : 'Status: OFFLINE',
        enabled: false,
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: _isRunning ? 'Stop Tunnel' : 'Start Tunnel',
        onClicked: (menuItem) => _handleTunnelToggle(),
      ),
      MenuItemLabel(
        label: 'Show Window',
        onClicked: (menuItem) => windowManager.show(),
      ),
      MenuSeparator(),
      MenuItemLabel(label: 'Exit', onClicked: (menuItem) => _exitApp()),
    ]);
    await _systemTray.setContextMenu(_menu);
  }

  Future<void> _exitApp() async {
    await _stopEverything();
    exit(0);
  }

  @override
  void onWindowClose() async {
    await windowManager.hide();
  }

  void log(String message) {
    if (!kDebugMode) return;
    if (!mounted) return;
    setState(() => _logs.add(message));
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<int> _startServer({int bindPort = 0}) async {
    await _server?.close(force: true);
    _server = await HttpServer.bind(InternetAddress.anyIPv4, bindPort);
    final port = _server!.port;
    log("SERVER BIND (HTTP): http://localhost:$port");

    _server!.listen((HttpRequest request) async {
      try {
        final authHeader = request.headers.value(HttpHeaders.authorizationHeader);
        final urlToken = request.uri.queryParameters['token'];

        bool isAuthorized = false;
        if (authHeader != null && authHeader.startsWith('Bearer ')) {
          if (authHeader.substring(7) == _apiToken) isAuthorized = true;
        }
        if (urlToken == _apiToken) isAuthorized = true;

        if (!isAuthorized) {
          request.response.statusCode = HttpStatus.forbidden;
          final isJson = request.headers.value('accept')?.contains('application/json') ?? false;
          if (isJson) {
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({"error": "Forbidden: Invalid Token"}));
          } else {
            request.response.write('403 Forbidden: Token không hợp lệ.');
          }
          await request.response.close();
          return;
        }

        final requestPath = Uri.decodeComponent(request.uri.path);
        log("--> [${request.connectionInfo?.remoteAddress.address}] ${request.method} $requestPath");

        final pathSegments = requestPath.split('/').where((s) => s.isNotEmpty).toList();

        if (pathSegments.isEmpty) {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('404 Not Found');
          return;
        }

        final virtualName = pathSegments[0];
        final isApiRequest = request.headers.value('accept')?.contains('application/json') ?? false;

        if (!_sharedFolders.containsKey(virtualName)) {
          request.response.statusCode = HttpStatus.notFound;
          if (isApiRequest) {
            request.response.write('{"error": "Folder not shared"}');
          } else {
            request.response.write('404 Not Found: Folder not shared.');
          }
          return;
        }

        if (pathSegments.length == 1 && !request.uri.path.endsWith('/')) {
          await request.response.redirect(Uri.parse('${request.uri.path}/'));
          return;
        }

        final localBasePath = _sharedFolders[virtualName]!;
        final subPath = p.joinAll(pathSegments.sublist(1));
        final fullPath = p.join(localBasePath, subPath);

        if (pathSegments.length > 3) {
          request.response.statusCode = HttpStatus.forbidden;
          request.response.write('403 Forbidden: Độ sâu thư mục vượt quá giới hạn (tối đa 2 tầng).');
          return;
        }

        final entityType = FileSystemEntity.typeSync(fullPath);
        if (entityType == FileSystemEntityType.file) {
          final file = File(fullPath);
          request.response.headers.contentType = _getContentType(fullPath);
          await request.response.addStream(file.openRead());
        } else if (entityType == FileSystemEntityType.directory) {
          if (!request.uri.path.endsWith('/')) {
            await request.response.redirect(Uri.parse('${request.uri.path}/'));
            return;
          }
          await _renderFolderContent(request, virtualName, localBasePath, pathSegments);
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
  }

  Future<List<Map<String, dynamic>>> _buildJsonTree(
    Directory dir,
    String virtualPath,
    int currentDepth,
    int maxDepth,
    String tokenSuffix,
  ) async {
    if (currentDepth >= maxDepth) return [];

    final List<Map<String, dynamic>> items = [];
    try {
      final entities = await dir.list().toList();
      entities.sort((a, b) {
        if (a is Directory && b is File) return -1;
        if (a is File && b is Directory) return 1;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });

      for (final e in entities) {
        final name = p.basename(e.path);
        if (name.startsWith('.')) continue;

        final isDir = e is Directory;
        final pathPrefix = virtualPath.endsWith('/') ? '' : '/';
        final itemVirtualPath = "$virtualPath$pathPrefix${Uri.encodeComponent(name)}";
        final publicUrl = "$_tunnelDomain$itemVirtualPath${isDir ? '/' : ''}$tokenSuffix";

        final item = {
          "name": name,
          "isDir": isDir,
          "size": e is File ? e.lengthSync() : 0,
          "ext": p.extension(e.path).replaceAll('.', ''),
          "url": publicUrl,
        };

        if (isDir && (currentDepth + 1) < maxDepth) {
          item["children"] = await _buildJsonTree(e, "$itemVirtualPath/", currentDepth + 1, maxDepth, tokenSuffix);
        }
        items.add(item);
      }
    } catch (_) {}
    return items;
  }

  Future<void> _renderFolderContent(
    HttpRequest request,
    String virtualName,
    String localBasePath,
    List<String> segments,
  ) async {
    final relPathInFolder = p.joinAll(segments.sublist(1));
    final fullPath = p.join(localBasePath, relPathInFolder);
    final entities = (await Directory(fullPath).list().toList())
        .where((e) => !p.basename(e.path).startsWith('.'))
        .toList();

    final currentToken = request.uri.queryParameters['token'];
    final tokenSuffix = currentToken != null ? '?token=$currentToken' : '';

    final isApiRequest = request.headers.value('accept')?.contains('application/json') ?? false;
    if (isApiRequest) {
      final jsonTree = await _buildJsonTree(Directory(fullPath), request.uri.path, segments.length, 3, tokenSuffix);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(jsonTree));
      return;
    }

    entities.sort((a, b) {
      if (a is Directory && b is File) return -1;
      if (a is File && b is Directory) return 1;
      return a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });

    final buffer = StringBuffer();
    buffer.write('<!DOCTYPE html><html lang="vi"><head><meta charset="utf-8">');
    buffer.write('<meta name="viewport" content="width=device-width, initial-scale=1">');
    buffer.write('<title>Gallery - $virtualName</title>');
    buffer.write('<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600&display=swap" rel="stylesheet">');
    buffer.write(_getSharedStyles());
    buffer.write('</head><body>');
    buffer.write('<div class="header">');
    buffer.write('  <div class="breadcrumb">');
    buffer.write('    <a href="..$tokenSuffix">📁 Thư mục gốc</a><span>/$virtualName${relPathInFolder.isEmpty ? '' : '/$relPathInFolder'}</span>');
    buffer.write('  </div>');
    buffer.write('  <h1>Bộ sưu tập Media</h1>');
    buffer.write('</div>');

    if (relPathInFolder.isNotEmpty) {
      buffer.write('<div class="back-navigation">');
      buffer.write('  <a href="..$tokenSuffix" class="btn-back">');
      buffer.write('    <span class="btn-icon">↩️</span>');
      buffer.write('    <span class="btn-text">Quay lại thư mục cha</span>');
      buffer.write('  </a>');
      buffer.write('</div>');
    }

    buffer.write('<div class="gallery-grid">');

    for (final entity in entities) {
      final name = p.basename(entity.path);
      final isDir = entity is Directory;
      final ext = p.extension(entity.path).toLowerCase();
      final urlName = Uri.encodeComponent(name) + (isDir ? '/' : '');
      final fullLink = "$urlName$tokenSuffix";

      final subSegments = relPathInFolder.split(p.separator).where((s) => s.isNotEmpty).toList();
      final isAtMaxDepth = isDir && subSegments.length >= 2;

      bool isImage = ['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext);
      bool isVideo = ['.mp4', '.mov', '.avi', '.mkv'].contains(ext);

      if (isAtMaxDepth) {
        buffer.write('<div class="card disabled-card">');
      } else {
        buffer.write('<a href="$fullLink" class="card ${isDir ? 'dir-card' : ''}">');
      }

      if (isImage) {
        buffer.write('  <div class="media-preview" style="background-image: url(\'$urlName$tokenSuffix\')"></div>');
      } else if (isVideo) {
        buffer.write('  <div class="media-preview video-overlay">📽️</div>');
      } else if (isDir) {
        buffer.write('  <div class="media-preview dir-preview">📂</div>');
      } else {
        buffer.write('  <div class="media-preview file-preview">📄</div>');
      }

      buffer.write('  <div class="info">');
      buffer.write('    <div class="name">$name</div>');
      if (isDir) {
        if (isAtMaxDepth) {
          buffer.write('    <div class="size locked-badge">🔒 Giới hạn 2 tầng</div>');
        } else {
          buffer.write('    <div class="size">Thư mục</div>');
        }
      } else {
        final size = (entity as File).lengthSync();
        buffer.write('    <div class="size">${(size / 1024).toStringAsFixed(1)} KB</div>');
      }
      buffer.write('  </div>');
      if (isAtMaxDepth) {
        buffer.write('</div>');
      } else {
        buffer.write('</a>');
      }
    }

    buffer.write('</div>');
    buffer.write('<div class="footer">Cung cấp bởi Shotpik Agent</div>');
    buffer.write('</body></html>');

    request.response.headers.contentType = ContentType.html;
    request.response.write(buffer.toString());
  }

  String _getSharedStyles() {
    return '''<style>
      :root { --primary: #6366f1; --bg: #f8fafc; --card: #ffffff; }
      body { font-family: 'Inter', sans-serif; background: var(--bg); margin: 0; padding: 20px; color: #1e293b; }
      .header { max-width: 1200px; margin: 0 auto 30px; }
      .breadcrumb { font-size: 14px; color: #64748b; margin-bottom: 8px; }
      .breadcrumb a { color: var(--primary); text-decoration: none; }
      h1 { margin: 0; font-size: 28px; font-weight: 600; }
      
      .gallery-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 20px; max-width: 1200px; margin: 0 auto; }
      
      .back-navigation { max-width: 1200px; margin: 0 auto 20px; }
      .btn-back { display: inline-flex; align-items: center; padding: 10px 24px; background: #fff; border: 1px solid #e2e8f0; 
                  border-radius: 14px; text-decoration: none; color: #475569; font-weight: 600; font-size: 14px; 
                  transition: all 0.2s; gap: 10px; }
      .btn-back:hover { background: #f1f5f9; border-color: var(--primary); color: var(--primary); box-shadow: 0 4px 6px -1px rgba(0,0,0,0.05); }
      .btn-icon { font-size: 18px; }

      .card { background: var(--card); border-radius: 16px; overflow: hidden; text-decoration: none; color: inherit; 
              transition: transform 0.2s, box-shadow 0.2s; border: 1px solid #e2e8f0; display: flex; flex-direction: column; }
      .card:hover { transform: translateY(-4px); box-shadow: 0 12px 20px -5px rgba(0,0,0,0.1); border-color: var(--primary); }
      
      .media-preview { height: 180px; background-size: cover; background-position: center; background-color: #f1f5f9; 
                       display: flex; align-items: center; justify-content: center; font-size: 50px; }
      .back-preview { background: #e2e8f0; color: #475569; }
      .video-overlay { position: relative; color: #fff; background: #1e293b; }
      .dir-preview { color: #f59e0b; background: #fffbeb; }
      .file-preview { color: #94a3b8; }
      
      .info { padding: 12px; }
      .name { font-weight: 600; font-size: 14px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
      .size { font-size: 12px; color: #64748b; margin-top: 4px; }

      .disabled-card { opacity: 0.6; cursor: not-allowed; position: relative; }
      .disabled-card:hover { transform: none; box-shadow: none; border-color: #e2e8f0; }
      .locked-badge { color: #ef4444; font-weight: 600; display: flex; align-items: center; gap: 4px; }
      
      .footer { text-align: center; margin-top: 50px; color: #94a3b8; font-size: 13px; }
    </style>''';
  }

  Future<void> _handleTunnelToggle() async {
    if (_isRunning || _isConnecting) {
      await _stopEverything(clearFolders: false);
    } else {
      await _startEverything();
    }
  }

  Future<void> _startEverything() async {
    await _stopEverything(clearFolders: false);
    setState(() {
      _isConnecting = true;
      _statusMessage = 'Initializing...';
      _shouldRestart = true;
    });
    try {
      final bindPort = _tunnelToken.isNotEmpty ? _namedTunnelPort : 0;
      final port = await _startServer(bindPort: bindPort);
      _currentPort = port;
      await _startTunnelExec(port);
    } catch (e) {
      setState(() {
        _error = "Init Fail: $e";
        _isConnecting = false;
      });
    }
  }

  Future<void> _startTunnelExec(int port) async {
    final String exePath = Platform.resolvedExecutable;
    String cloudflaredPath;
    if (Platform.isMacOS) {
      final appDir = File(exePath).parent.parent.path;
      cloudflaredPath = "$appDir/Frameworks/App.framework/Resources/flutter_assets/assets/bin/cloudflared";
    } else {
      final appDir = File(exePath).parent.path;
      cloudflaredPath = "$appDir/data/flutter_assets/assets/bin/cloudflared";
      if (Platform.isWindows) cloudflaredPath += ".exe";
    }

    if (!File(cloudflaredPath).existsSync()) {
      final altAppDir = File(exePath).parent.parent.parent.path;
      final altPath = "$altAppDir/Resources/bin/cloudflared";
      if (File(altPath).existsSync()) {
        cloudflaredPath = altPath;
      } else {
        throw Exception("cloudflared binary missing.");
      }
    }

    if (!Platform.isWindows) await Process.run('chmod', ['+x', cloudflaredPath]);

    _tunnelProcess = await Process.start(cloudflaredPath, [
      'tunnel', '--no-autoupdate', '--protocol', 'http2',
      if (_tunnelToken.isNotEmpty) ...['run', '--token', _tunnelToken, '--no-tls-verify']
      else ...['--url', 'http://127.0.0.1:$port'],
    ]);

    _tunnelOutSub = _tunnelProcess!.stdout.transform(SystemEncoding().decoder).listen(_processTunnelLog);
    _tunnelErrSub = _tunnelProcess!.stderr.transform(SystemEncoding().decoder).listen(_processTunnelLog);

    _tunnelProcess!.exitCode.then((exitCode) async {
      if (!mounted || !_shouldRestart) return;
      if (_retryCount >= _maxRetries) {
        setState(() {
          _error = 'Tunnel crashed.';
          _isRunning = false;
          _isConnecting = false;
          _shouldRestart = false;
        });
        return;
      }
      _retryCount++;
      setState(() {
        _isConnecting = true;
        _statusMessage = 'Reconnect #$_retryCount...';
      });
      await Future.delayed(Duration(seconds: _retryCount * 2));
      if (mounted && _shouldRestart) _startTunnelExec(_currentPort!);
    });

    Future.delayed(const Duration(seconds: 90), () {
      if (!_isRunning && _isConnecting && mounted) {
        setState(() => _error = 'Slow connection. Still trying...');
      }
    });
  }

  void _processTunnelLog(String data) {
    log(data);
    final match = RegExp(r'https://[a-zA-Z0-9\-]+\.trycloudflare\.com').firstMatch(data);
    if (match != null) setState(() => _tunnelUrl = match.group(0));

    if (data.contains('timeout') || data.contains('7844')) {
      _retryCount++;
      if (_retryCount > 6) setState(() => _error = "Network restriction: Port 7844 blocked.");
    }

    bool isRegistered = data.contains('Registered tunnel connection') ||
        data.contains('Connected to') ||
        data.contains('Updated to new configuration');

    if (isRegistered && !_isRunning) {
      setState(() {
        _tunnelUrl = _tunnelToken.isNotEmpty ? _tunnelDomain : _tunnelUrl;
        _isRunning = true;
        _isConnecting = false;
        _retryCount = 0;
        _error = null;
        _statusMessage = null;
      });
      _updateTrayMenu();
    }
  }

  Future<void> _startSharing() async {
    if (!_isRunning) return;
    final folder = await getDirectoryPath(confirmButtonText: 'Select Share Folder');
    if (folder == null) return;
    final folderName = p.basename(folder);
    if (_sharedFolders.containsKey(folderName)) return;
    setState(() => _sharedFolders[folderName] = folder);
  }

  void _removeFolder(String name) async {
    setState(() => _sharedFolders.remove(name));
  }

  ContentType _getContentType(String path) {
    final ext = p.extension(path).toLowerCase();
    if (ext == '.html') return ContentType.html;
    if (ext == '.png') return ContentType('image', 'png');
    if (ext == '.jpg' || ext == '.jpeg') return ContentType('image', 'jpeg');
    return ContentType.binary;
  }

  Future<void> _stopEverything({bool clearFolders = true}) async {
    _shouldRestart = false;
    await _tunnelOutSub?.cancel();
    await _tunnelErrSub?.cancel();
    _tunnelProcess?.kill();
    _tunnelProcess = null;
    await _server?.close(force: true);
    _server = null;

    if (mounted) {
      setState(() {
        _isRunning = false;
        _isConnecting = false;
        if (clearFolders) _sharedFolders.clear();
        _tunnelUrl = null;
      });
      _updateTrayMenu();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F2F7),
      appBar: AppBar(
        title: const Text("Shotpik Tunnel Multi-Share"),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            StatusConfigCard(
              isRunning: _isRunning,
              isConnecting: _isConnecting,
              statusMessage: _statusMessage,
              onToggleTunnel: _handleTunnelToggle,
              authToken: _authManager.authToken,
              userData: _authManager.userData,
              onLogout: _authManager.logout,
              onLoginWeb: _authManager.loginWeb,
              tunnelUrl: _tunnelUrl,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 11)),
              ),
            const SizedBox(height: 20),
            FolderListCard(
              isRunning: _isRunning,
              sharedFolders: _sharedFolders,
              tunnelUrl: _tunnelUrl,
              apiToken: _apiToken,
              onAddFolder: _startSharing,
              onRemoveFolder: _removeFolder,
            ),
            if (kDebugMode)
              DebugLogView(
                logs: _logs,
                scrollController: _scroll,
                onClearLogs: () => setState(() => _logs.clear()),
              ),
          ],
        ),
      ),
    );
  }
}
