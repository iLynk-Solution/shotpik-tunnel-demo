import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

import '../../../auth/logic/auth_manager.dart';
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
  final SystemTray _systemTray = SystemTray();
  final AppWindow _appWindow = AppWindow();
  final Menu _menu = Menu();
  AuthManager get _authManager => widget.authManager;

  HttpServer? _server;

  final Map<String, SharedFolderData> _sharedFolders = {};
  String? _error;
  String? _statusMessage;

  bool _isRunning = false; // Local Server Status
  bool _isConnecting = false;

  int? _currentPort;
  String? _mainTunnelUrl;
  String? _mainTunnelToken;
  Process? _mainTunnelProcess;

  static const int _namedTunnelPort = 8888;

  final List<String> _logs = [];
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    initSystemTray();
    _authManager.addListener(_onAuthChanged);
    _loadFolders();
    
    // Auto-start local server on app launch
    _startServer(bindPort: _namedTunnelPort).then((port) {
      _currentPort = port;
      setState(() => _isRunning = true);
    }).catchError((e) {
      log("API Server failed to start: $e");
      setState(() => _error = "API Port $_namedTunnelPort is already in use or blocked.");
    });
  }

  Future<void> _loadFolders() async {
    final prefs = await SharedPreferences.getInstance();
    _mainTunnelToken = prefs.getString('main_tunnel_token');
    _mainTunnelUrl = prefs.getString('main_tunnel_url');

    final List<String>? folderList = prefs.getStringList('shared_folders');
    if (folderList != null) {
      setState(() {
        for (var item in folderList) {
          try {
            final data = jsonDecode(item);
            final name = data['name'] as String;
            final nameUrl = data['nameUrl']?.toString() ?? name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
            final path = data['path'] as String;
            final id = data['id']?.toString() ?? _generateUuid();
            _sharedFolders[id] = SharedFolderData(
              id: id,
              name: name,
              nameUrl: nameUrl,
              localPath: path,
              tunnelUrl: data['url']?.toString(), // Restore previous URL
            );
          } catch (e) {
            log("Error loading folder: $e");
          }
        }
      });
    }

    // Auto-start everything if we have a token or previous folders
    if (_sharedFolders.isNotEmpty || _mainTunnelToken != null) {
      _startEverything();
    }
  }

  Future<void> _saveFolders() async {
    final prefs = await SharedPreferences.getInstance();
    if (_mainTunnelToken != null) {
      await prefs.setString('main_tunnel_token', _mainTunnelToken!);
    }
    if (_mainTunnelUrl != null) {
      await prefs.setString('main_tunnel_url', _mainTunnelUrl!);
    }

    final List<String> folderList = _sharedFolders.values.map((f) {
      return jsonEncode({
        'id': f.id, 
        'name': f.name, 
        'nameUrl': f.nameUrl,
        'path': f.localPath,
        'url': f.tunnelUrl, // Persist the URL too
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
        label: _isRunning ? 'Status: SERVER ACTIVE' : 'Status: OFFLINE',
        enabled: false,
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: _isRunning ? 'Stop Service' : 'Start Service',
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
    String generateByte() => random.nextInt(256).toRadixString(16).padLeft(2, '0');
    return '${generateByte()}${generateByte()}${generateByte()}${generateByte()}-'
        '${generateByte()}${generateByte()}-'
        '4${generateByte().substring(1)}-'
        '${(random.nextInt(4) + 8).toRadixString(16)}${generateByte().substring(1)}-'
        '${generateByte()}${generateByte()}${generateByte()}${generateByte()}${generateByte()}${generateByte()}';
  }

  Future<int> _startServer({int bindPort = 0}) async {
    await _server?.close(force: true);
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, bindPort, shared: true);
      final port = _server!.port;
      log("API SERVER STARTED: http://127.0.0.1:$port");
      log("Use this address for LOCAL API calls.");

      _server!.listen((HttpRequest request) async {
        try {
          final authHeader = request.headers.value(
            HttpHeaders.authorizationHeader,
          );
          final urlToken = request.uri.queryParameters['token'];
          bool isAuthorized = false;
          final currentApiToken = _authManager.authToken;

          if (authHeader != null && authHeader.startsWith('Bearer ')) {
            if (authHeader.substring(7) == currentApiToken) isAuthorized = true;
          }
          if (urlToken == currentApiToken) isAuthorized = true;

          if (!isAuthorized) {
            request.response.statusCode = HttpStatus.forbidden;
            request.response.write('403 Forbidden: Token không hợp lệ.');
            await request.response.close();
            return;
          }

          final requestPath = Uri.decodeComponent(request.uri.path);
          log("--> ${request.method} $requestPath");

          final apiService = TunnelApiService(
            sharedFolders: _sharedFolders,
            onLog: log,
            onAddFolder: (id, name, nameUrl, path) async {
              if (!Directory(path).existsSync()) {
                return "Error: Local path does not exist: $path";
              }
              setState(() {
                _sharedFolders[id] = SharedFolderData(
                  id: id,
                  name: name, 
                  nameUrl: nameUrl,
                  localPath: path,
                );
              });
              _saveFolders();
              return await _startTunnelForFolder(id);
            },
            onStartService: _startEverything,
            onUpdateConfig: (token) async {
              setState(() {
                _mainTunnelToken = token;
              });
              await _saveFolders();
              await _startEverything(); // Restart to apply new token
            },
          );

          if (requestPath.startsWith('/api/v1/')) {
            await apiService.handleRequest(request);
            return;
          }

          final pathSegments = requestPath
              .split('/')
              .where((s) => s.isNotEmpty)
              .toList();
          if (pathSegments.isEmpty) {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write('404 Not Found');
            return;
          }

          final virtualName = pathSegments[0];
          SharedFolderData? folderData = _sharedFolders[virtualName]; // Try ID first

          if (folderData == null) {
            // Try searching by nameUrl (Unique identifier)
            for (var f in _sharedFolders.values) {
              if (f.nameUrl == virtualName) {
                folderData = f;
                break;
              }
            }
          }

          if (folderData == null) {
            // Try searching by name (Legacy)
            for (var f in _sharedFolders.values) {
              if (f.name == virtualName) {
                folderData = f;
                break;
              }
            }
          }

          if (folderData == null) {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write('404 Not Found: Folder not shared.');
            return;
          }
          final subPath = p.joinAll(pathSegments.sublist(1));
          final fullPath = p.join(folderData.localPath, subPath);

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
      
      setState(() {
        _isRunning = true;
        _statusMessage = 'Service Ready';
      });
      
      _startMainTunnel(); // Start primary API tunnel

      // Activate all folders
      for (var folderId in _sharedFolders.keys) {
        if (_mainTunnelToken == null || _mainTunnelToken!.isEmpty) {
          // If using Quick Tunnels, add delay to avoid 429
          await Future.delayed(const Duration(seconds: 2));
        }
        _startTunnelForFolder(folderId);
      }
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
      cloudflaredPath = "$appDir/Frameworks/App.framework/Resources/flutter_assets/assets/bin/cloudflared";
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
      '--protocol',
      'http2',
    ];

    if (_mainTunnelToken != null && _mainTunnelToken!.isNotEmpty) {
      args.addAll(['run', '--token', _mainTunnelToken!]);
    } else {
      args.addAll(['--url', 'http://127.0.0.1:$_currentPort']);
    }

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
    
    // Check for random trycloudflare URL
    final match = RegExp(r'https://[a-zA-Z0-9\-]+\.trycloudflare\.com').firstMatch(data);
    if (match != null) {
      setState(() {
        _mainTunnelUrl = match.group(0);
        _isConnecting = false;
        _saveFolders();
      });
      return;
    }

    // Check for named tunnel success (if using token)
    if (_mainTunnelToken != null && (data.contains("Registered tunnel") || data.contains("Connection") && data.contains("established"))) {
      setState(() {
        _mainTunnelUrl = "https://shotpik-tunnel.tuyendev.store";
        _isConnecting = false;
        _saveFolders();
      });
    }
  }

  final Map<String, Completer<String>> _tunnelCompleters = {};

  Future<String?> _startTunnelForFolder(String folderName) async {
    final folderData = _sharedFolders[folderName];
    if (folderData == null) return "Error: Folder not found";

    if (folderData.tunnelUrl != null) {
      return folderData.tunnelUrl;
    }

    // If we have a main domain token, we DON'T start sub-tunnels.
    // We just return the main URL with the folder name as the path.
    if (_mainTunnelToken != null && _mainTunnelToken!.isNotEmpty) {
      final baseUrl = _mainTunnelUrl ?? "https://shotpik-tunnel.tuyendev.store";
      final albumUrl = "$baseUrl/${Uri.encodeComponent(folderData.nameUrl)}/";
      setState(() {
        folderData.tunnelUrl = albumUrl; // Store FULL URL
        folderData.isConnecting = false;
      });
      return albumUrl;
    }

    // Capture existing completer if one is already running
    if (_tunnelCompleters.containsKey(folderName)) {
      return _tunnelCompleters[folderName]!.future;
    }

    // If a process exists but no URL, maybe it's stuck or just starting.
    // For simplicity, if no process, start it.
    if (folderData.process == null) {
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
        final altAppDir = File(exePath).parent.parent.parent.path;
        final altPath = "$altAppDir/Resources/bin/cloudflared";
        if (File(altPath).existsSync()) {
          cloudflaredPath = altPath;
        } else {
          return "Error: cloudflared missing";
        }
      }

      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', cloudflaredPath]);
      }

      final process = await Process.start(cloudflaredPath, [
        'tunnel',
        '--no-autoupdate',
        '--protocol',
        'http2',
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
    }

    final completer = Completer<String>();
    _tunnelCompleters[folderName] = completer;

    // Timeout after 15 seconds if no URL found
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _tunnelCompleters.remove(folderName);
        return "Pending (Starting...)";
      },
    );
  }

  void _processFolderTunnelLog(String folderName, String data) {
    log("[$folderName] $data");
    final folderData = _sharedFolders[folderName];
    if (folderData == null) return;
    final match = RegExp(
      r'https://[a-zA-Z0-9\-]+\.trycloudflare\.com',
    ).firstMatch(data);
    if (match != null) {
      if (mounted) {
        final baseUrl = match.group(0)!;
        final albumUrl = "$baseUrl/${Uri.encodeComponent(folderData.nameUrl)}/";
        setState(() {
          folderData.tunnelUrl = albumUrl; // Store FULL URL
          folderData.isConnecting = false;
        });
        _tunnelCompleters.remove(folderName)?.complete(albumUrl);
      }
    }
  }

  Future<void> _startSharing() async {
    if (!_isRunning) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const AddAlbumDialog(),
    );
    if (result != null) {
      final name = result['name'] as String;
      final path = result['path'] as String;
      final nameUrl = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
      
      final newData = SharedFolderData(
        id: _generateUuid(),
        name: name, 
        nameUrl: nameUrl,
        localPath: path,
      );
      setState(() => _sharedFolders[newData.id] = newData);
      _saveFolders();
      _startTunnelForFolder(newData.id);
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
      final folderData = _sharedFolders[id];
      if (folderData != null) {
        folderData.outSub?.cancel();
        folderData.errSub?.cancel();
        folderData.process?.kill();
      }
      setState(() => _sharedFolders.remove(id));
      _saveFolders();
    }
  }

  ContentType _getContentType(String path) {
    final ext = p.extension(path).toLowerCase();
    if (ext == '.png') return ContentType('image', 'png');
    if (ext == '.jpg' || ext == '.jpeg') return ContentType('image', 'jpeg');
    return ContentType.binary;
  }

  Future<void> _stopEverything({bool clearFolders = false}) async {
    for (final folder in _sharedFolders.values) {
      folder.outSub?.cancel();
      folder.errSub?.cancel();
      folder.process?.kill();
      folder.process = null;
      folder.isConnecting = false;
    }
    _mainTunnelProcess?.kill();
    _mainTunnelProcess = null;
    // We keep the _server (API Server) running to avoid "Socket Hang Up"
    // only close if explicitly needed or during app shutdown.
    // await _server?.close(force: true);
    // _server = null;
    if (mounted) {
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
                          initialToken: _mainTunnelToken,
                          onSaveToken: (token) {
                            setState(() => _mainTunnelToken = token);
                            _saveFolders();
                            _startEverything();
                          },
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

  Widget _buildUserCard(BuildContext context) => Container(
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
                _authManager.userName ?? "User",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Text(
                _authManager.userEmail!,
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
