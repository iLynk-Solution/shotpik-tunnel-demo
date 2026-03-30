import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:http/http.dart' as http;
import 'package:shotpik_agent/features/auth/logic/auth_manager.dart';
import 'package:shotpik_agent/features/tray/tray_manager.dart';
import 'package:shotpik_agent/core/rsa_utils.dart';
import 'package:shotpik_agent/core/app_config.dart';
import 'package:shotpik_agent/features/tunnel/logic/tunnel_api_service.dart';
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
  Process? _tunnelProcess;

  String? _statusMessage;
  bool _isRunning = false;
  bool _isConnecting = false;

  int? _currentPort;
  String? _mainTunnelUrl;
  final Set<String> _whitelist = {};

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
    _logs.addAll(AppConfig.loadLogs);
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    AppTrayManager().setTunnelToggleCallback(() => _handleTunnelToggle());
    AppTrayManager().setExitCallback(() => _exitApp());
    _authManager.addListener(_onAuthChanged);
    _loadFolders();
    _startEverything();
  }

  Future<void> _loadFolders() async {
    final prefs = await SharedPreferences.getInstance();
    _mainTunnelUrl = prefs.getString('main_tunnel_url');

    final List<String>? whitelist = prefs.getStringList('whitelist');
    if (whitelist != null) {
      _whitelist.clear();
      _whitelist.addAll(whitelist);
    }

    final List<String>? watchFolders = prefs.getStringList('watch_folders');
    if (watchFolders != null) {
      _watchFolders.clear();
      _watchFolders.addAll(watchFolders);
    }

    setState(() {
      _statusMessage ??= "Local API Ready";
    });
  }

  Future<void> _saveFolders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('whitelist', _whitelist.toList());
    if (_mainTunnelUrl != null) {
      await prefs.setString('main_tunnel_url', _mainTunnelUrl!);
    }
  }
  void _onAuthChanged() {
    if (_authManager.authToken == null) {
      _stopEverything();
    }
  }

  Future<void> _handleTunnelToggle() async {
    if (_isRunning) {
      await _stopEverything();
    } else {
      await _startEverything();
    }
  }

  Future<void> _startEverything() async {
    if (_isConnecting) return;
    setState(() => _isConnecting = true);
    try {
      final port = await _startServer(bindPort: 8888);
      _currentPort = port;
      _isRunning = true;
      _statusMessage = "Local Server Port: $port";
      
      // Start Cloudflare Tunnel
      await _startTunnelProcess(port);
      
      _updateTrayMenu();
    } catch (e) {
      _statusMessage = "Error: $e";
      _isRunning = false;
    } finally {
      setState(() => _isConnecting = false);
    }
  }

  Future<void> _startTunnelProcess(int port) async {
    try {
      log("SYSTEM: Starting Cloudflare Tunnel for port $port...");
      _tunnelProcess = await Process.start(
        'cloudflared',
        ['tunnel', '--url', 'http://localhost:$port'],
      );

      _tunnelProcess!.stdout.transform(utf8.decoder).listen((data) {
        log("CLOUDFLARED: $data");
      });

      _tunnelProcess!.stderr.transform(utf8.decoder).listen((data) {
        log("CLOUDFLARED ERROR: $data");
        // Look for the URL in stderr (cloudflared outputs the URL there)
        final urlMatch = RegExp(r'https://[a-zA-Z0-9-]+\.trycloudflare\.com').firstMatch(data);
        if (urlMatch != null) {
          final url = urlMatch.group(0);
          if (url != null && _mainTunnelUrl != url) {
            setState(() {
              _mainTunnelUrl = url;
              _statusMessage = "Tunnel Online: $url";
            });
            _saveFolders();
          }
        }
      });

      _tunnelProcess!.exitCode.then((code) {
        log("SYSTEM: Cloudflare Tunnel exited with code $code");
        if (_isRunning) {
          setState(() {
            _isRunning = false;
            _statusMessage = "Tunnel process crashed (Exit: $code)";
          });
        }
      });
    } catch (e) {
      log("SYSTEM: Failed to start cloudflared: $e");
      _statusMessage = "Failed to start cloudflared. Make sure it is installed.";
      rethrow;
    }
  }

  Future<void> _handleSearchAction() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() => _isSearching = true);
    log("UI: Searching for '$query'...");
    
    try {
      final bodyData = jsonEncode({"path": query});
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

  Future<void> _updateTrayMenu() async {
    await AppTrayManager().updateTrayMenu(isRunning: _isRunning);
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
    if (!mounted) return;
    debugPrint("TUNNEL LOG: $message");
    setState(() => _logs.add(message));
  }

  String get _localApiBase => "http://localhost:$_currentPort";

  Future<int> _startServer({int bindPort = 0}) async {
    await _server?.close(force: true);
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, bindPort);
      _server!.listen((HttpRequest request) async {
        final signature = request.headers.value('X-Signature') ?? '';
        final bodyString = await utf8.decodeStream(request);

        bool isAuthorized = false;
        if (signature.isNotEmpty) {
          final publicKeyStr = AppConfig.rsaPublicKey;
          if (publicKeyStr.isNotEmpty) {
            isAuthorized = RSAUtils.verifySignature(publicKeyStr, bodyString, signature);
          }
        }

        final apiService = TunnelApiService(
          whitelist: _whitelist,
          mainTunnelUrl: _mainTunnelUrl,
          onLog: log,
          onUpdateWhitelist: (paths) async {
            setState(() {
              _whitelist.clear();
              _whitelist.addAll(paths);
            });
            await _saveFolders();
          },
          onUpdateSession: (token) async => await _authManager.updateSession(token),
          onStartService: _startEverything,
          watchFolders: _watchFolders,
        );

        await apiService.handleRequest(request, bodyString, isAuthorized: isAuthorized);
      });
      return _server!.port;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _stopEverything({bool isDisposing = false}) async {
    await _server?.close(force: true);
    _tunnelProcess?.kill();
    _tunnelProcess = null;
    
    if (!isDisposing && mounted) {
      setState(() {
        _isRunning = false;
        _isConnecting = false;
        _statusMessage = "Service Stopped";
      });
      _updateTrayMenu();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          TunnelSidebar(
            selectedIndex: _selectedIndex,
            onIndexChanged: (idx) => setState(() => _selectedIndex = idx),
            userName: _authManager.userData?['data']?['name'] ?? 
                      _authManager.userData?['name'] ?? 
                      _authManager.userData?['sub'],
            userEmail: _authManager.userData?['data']?['email'] ?? 
                       _authManager.userData?['email'],
            userAvatar: _authManager.userData?['data']?['avatar_url'],
            onLogout: () => _authManager.logout(),
          ),
          Expanded(
            child: Container(
              color: Colors.white,
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
                      searchResults: _searchResults,
                      onClearSearchResults: () => setState(() => _searchResults = []),
                      watchFolders: _watchFolders,
                      apiToken: _authManager.authToken ?? '',
                      whitelist: _whitelist,
                      localApiBase: _localApiBase,
                    );
                  case 1:
                    return WhitelistPage(
                      whitelist: _whitelist,
                      sharedFolders: {}, 
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
