import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

void main() {
  runApp(const TunnelInternalApp());
}

class TunnelInternalApp extends StatelessWidget {
  const TunnelInternalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: TunnelHome(),
    );
  }
}

class TunnelHome extends StatefulWidget {
  const TunnelHome({super.key});

  @override
  State<TunnelHome> createState() => _TunnelHomeState();
}

class _TunnelHomeState extends State<TunnelHome> {
  HttpServer? _server;
  Process? _tunnelProcess;
  StreamSubscription? _tunnelOutSub;
  StreamSubscription? _tunnelErrSub;

  String? _folderPath;
  String? _tunnelUrl;
  String? _error;
  String? _statusMessage;

  bool _isRunning = false;
  bool _isConnecting = false;
  bool _shouldRestart = false; // Flag to control auto-restart

  int _retryCount = 0;
  static const int _maxRetries = 5;
  int? _currentPort; // remember port for restarts

  final List<String> _logs = [];
  final ScrollController _scroll = ScrollController();

  // =========================
  // DEBUG LOG
  // =========================
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

  // =========================
  // START SERVER (AUTO PORT)
  // =========================
  Future<int> _startServer(String folder) async {
    await _server?.close(force: true);

    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0, // auto free port
    );

    final port = _server!.port;

    log("HTTP server started on port $port");

    _server!.listen((HttpRequest request) async {
      try {
        final requestPath = Uri.decodeComponent(request.uri.path);
        // Calculate depth: "/" is 0, "/folder1" is 1, "/folder1/folder2" is 2
        final pathSegments = requestPath
            .split('/')
            .where((s) => s.isNotEmpty)
            .toList();
        final depth = pathSegments.length;

        if (depth > 2) {
          request.response.statusCode = HttpStatus.forbidden;
          request.response.write('403 Forbidden: Maximum depth exceeded.');
          return;
        }

        // Remove leading / to join with folder path
        final relativePath = requestPath.startsWith('/')
            ? requestPath.substring(1)
            : requestPath;
        final fullPath = p.join(folder, relativePath);

        final type = FileSystemEntity.typeSync(fullPath);

        if (type == FileSystemEntityType.file) {
          final file = File(fullPath);
          // Set content type based on extension
          request.response.headers.contentType = _getContentType(fullPath);
          await request.response.addStream(file.openRead());
        } else if (type == FileSystemEntityType.directory) {
          final dir = Directory(fullPath);
          final entities = await dir.list().toList();

          // Sort: directories first, then files
          entities.sort((a, b) {
            if (a is Directory && b is File) return -1;
            if (a is File && b is Directory) return 1;
            return a.path.toLowerCase().compareTo(b.path.toLowerCase());
          });

          request.response.headers.contentType = ContentType.html;

          final buffer = StringBuffer();
          buffer.write('<!DOCTYPE html><html><head><meta charset="utf-8">');
          buffer.write(
            '<meta name="viewport" content="width=device-width, initial-scale=1">',
          );
          buffer.write('<title>Index of $requestPath</title>');
          buffer.write('<style>');
          buffer.write('*{transition: all 0.2s ease-in-out;}');
          buffer.write(
            'body{font-family: "Inter", -apple-system, sans-serif; padding:40px; line-height:1.6; background: linear-gradient(135deg, #f6f7f9 0%, #e2e8f0 100%); min-height: 100vh; margin: 0; color: #1e293b;}',
          );
          buffer.write(
            '.container{max-width:900px; margin:0 auto; background:rgba(255, 255, 255, 0.95); backdrop-filter: blur(10px); padding:40px; border-radius:24px; box-shadow:0 20px 25px -5px rgba(0,0,0,0.05), 0 10px 10px -5px rgba(0,0,0,0.02); border: 1px solid rgba(255, 255, 255, 0.5);}',
          );
          buffer.write(
            'h1{font-size:1.8rem; margin:0 0 8px 0; color:#0f172a; font-weight: 800; letter-spacing: -0.025em;}',
          );
          buffer.write(
            '.depth-info{font-size:0.9rem; color:#64748b; margin-bottom:32px; display: inline-block; padding: 4px 12px; background: #f1f5f9; border-radius: 9999px; font-weight: 500;}',
          );
          buffer.write(
            'ul{list-style:none; padding:0; margin:0; display: grid; gap: 8px;}',
          );
          buffer.write('li{overflow: hidden;}');
          buffer.write(
            'a{display:flex; align-items: center; padding:14px 20px; text-decoration:none; color:#334155; background: #ffffff; border: 1px solid #f1f5f9; font-weight: 500;}',
          );
          buffer.write(
            'a:hover{background:#f8fafc; transform: translateY(-2px); box-shadow: 0 4px 6px -1px rgba(0,0,0,0.05); border-color: #3b82f6; color: #2563eb;}',
          );
          buffer.write(
            '.dir::before{content:"📁"; margin-right: 12px; font-size: 1.2rem;}',
          );
          buffer.write(
            '.file::before{content:"📄"; margin-right: 12px; font-size: 1.2rem;}',
          );
          buffer.write(
            'hr{border:0; border-top:1px solid #e2e8f0; margin:32px 0;}',
          );
          buffer.write(
            '.footer{text-align: center; color:#94a3b8; font-size:0.875rem; font-weight: 500;}',
          );
          buffer.write('</style></head><body>');
          buffer.write('<div class="container">');
          buffer.write('<h1>Index of $requestPath</h1>');
          buffer.write('<p class="depth-info">Level: $depth/2</p><ul>');

          if (requestPath != '/' && requestPath != '') {
            buffer.write(
              '<li><a href=".." style="background: #f1f5f9; color: #64748b;">↩️ .. (Parent Directory)</a></li>',
            );
          }

          for (final entity in entities) {
            final name = p.basename(entity.path);
            final isDir = entity is Directory;

            // If we are at depth 2, don't show subdirectories
            if (isDir && depth >= 2) continue;

            final urlName = Uri.encodeComponent(name) + (isDir ? '/' : '');
            final displayName = isDir ? '$name/' : name;

            buffer.write('<li class="${isDir ? 'dir' : 'file'}">');
            buffer.write('<a href="$urlName">$displayName</a>');
            buffer.write('</li>');
          }

          buffer.write(
            '</ul><hr><p style="color:#6b7280;font-size:0.875rem;">Generated by Tunnel Share Internal (Limited to 2 levels)</p>',
          );
          buffer.write('</div></body></html>');
          request.response.write(buffer.toString());
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('404 Not Found');
        }
      } catch (e) {
        log("Server error: $e");
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('500 Internal Server Error');
      } finally {
        await request.response.close();
      }
    });

    return port;
  }

  // =========================
  // START TUNNEL
  // =========================
  Future<void> _startTunnel(int port) async {
    final String exePath = Platform.resolvedExecutable;
    String cloudflaredPath;

    if (Platform.isMacOS) {
      // Path for Flutter assets in macOS app bundle
      final appDir = File(exePath).parent.parent.path; // Contents
      cloudflaredPath =
          "$appDir/Frameworks/App.framework/Resources/flutter_assets/assets/bin/cloudflared";
    } else {
      // Windows / Linux paths
      final appDir = File(exePath).parent.path;
      cloudflaredPath = "$appDir/data/flutter_assets/assets/bin/cloudflared";
      if (Platform.isWindows) cloudflaredPath += ".exe";
    }

    if (!File(cloudflaredPath).existsSync()) {
      // Fallback check for standard macOS bundle location
      final altAppDir = File(exePath).parent.parent.parent.path;
      final altPath = "$altAppDir/Resources/bin/cloudflared";
      if (File(altPath).existsSync()) {
        cloudflaredPath = altPath;
      } else {
        throw Exception(
          "cloudflared not found in app bundle.\nChecked: $cloudflaredPath",
        );
      }
    }

    // Ensure executable permission on macOS/Linux
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', cloudflaredPath]);
    }

    _tunnelProcess = await Process.start(cloudflaredPath, [
      'tunnel',
      '--url',
      'http://127.0.0.1:$port',
      '--no-autoupdate',
      '--protocol',
      'h2mux', // Use legacy h2mux to force connection over port 443
    ]);

    void handleData(String data) {
      log(data);

      final match = RegExp(
        r'https://[a-zA-Z0-9\-]+\.trycloudflare\.com',
      ).firstMatch(data);

      if (match != null) {
        if (!mounted) return;
        setState(() {
          _tunnelUrl = match.group(0);
          _isConnecting = false;
          _isRunning = true;
          _retryCount = 0;
          _statusMessage = null;
          _error = null;
        });
      }
    }

    _tunnelOutSub = _tunnelProcess!.stdout
        .transform(SystemEncoding().decoder)
        .listen(handleData);

    _tunnelErrSub = _tunnelProcess!.stderr
        .transform(SystemEncoding().decoder)
        .listen(handleData);

    // Watch process exit and auto-restart
    _tunnelProcess!.exitCode.then((exitCode) async {
      if (!mounted || !_shouldRestart) return;
      log('⚠️ Tunnel disconnected (exit: $exitCode). Retrying...');

      if (_retryCount >= _maxRetries) {
        if (!mounted) return;
        setState(() {
          _error = 'Tunnel thất bại sau $_maxRetries lần thử lại.';
          _isRunning = false;
          _isConnecting = false;
          _shouldRestart = false;
        });
        return;
      }

      _retryCount++;
      final waitSec = _retryCount * 2;

      if (!mounted) return;
      setState(() {
        _tunnelUrl = null;
        _isConnecting = true;
        _statusMessage =
            'Kết nối lại... (lần $_retryCount/$_maxRetries, chờ ${waitSec}s)';
      });

      await Future.delayed(Duration(seconds: waitSec));
      if (!mounted || !_shouldRestart) return;

      try {
        await _startTunnel(_currentPort!);
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = e.toString();
            _isConnecting = false;
          });
        }
      }
    });

    // Timeout: nếu sau 20s chưa có link → báo lỗi
    Future.delayed(const Duration(seconds: 20), () {
      if (_tunnelUrl == null && _isConnecting && mounted) {
        setState(() {
          _error = 'Timeout: Không thể kết nối tới Cloudflare. Kiểm tra mạng.';
          _isConnecting = false;
        });
      }
    });
  }

  // =========================
  // START SHARE
  // =========================
  Future<void> _startShare() async {
    final folder = await getDirectoryPath(
      confirmButtonText: 'Chọn thư mục share',
    );

    if (folder == null) return;

    await _stopShare();

    setState(() {
      _folderPath = folder;
      _error = null;
      _tunnelUrl = null;
      _isConnecting = true;
      _retryCount = 0;
      _shouldRestart = true;
      _statusMessage = 'Đang khởi động tunnel...';
    });

    try {
      final port = await _startServer(folder);
      _currentPort = port;
      await _startTunnel(port);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isConnecting = false;
        _shouldRestart = false;
      });
    }
  }

  // =========================
  // STOP SHARE (CLEAN SAFE)
  // =========================
  Future<void> _stopShare() async {
    _shouldRestart = false; // Prevent auto-restart

    await _tunnelOutSub?.cancel();
    await _tunnelErrSub?.cancel();

    _tunnelProcess?.kill(ProcessSignal.sigterm);
    await _server?.close(force: true);

    _tunnelProcess = null;
    _server = null;

    if (!mounted) return;

    setState(() {
      _isRunning = false;
      _isConnecting = false;
      _tunnelUrl = null;
      _statusMessage = null;
      _retryCount = 0;
    });
  }

  ContentType _getContentType(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.html':
        return ContentType.html;
      case '.json':
        return ContentType.json;
      case '.txt':
        return ContentType.text;
      case '.jpg':
      case '.jpeg':
        return ContentType('image', 'jpeg');
      case '.png':
        return ContentType('image', 'png');
      case '.gif':
        return ContentType('image', 'gif');
      case '.pdf':
        return ContentType('application', 'pdf');
      case '.css':
        return ContentType('text', 'css');
      case '.js':
        return ContentType('application', 'javascript');
      default:
        return ContentType.binary;
    }
  }

  @override
  void dispose() {
    _stopShare();
    _scroll.dispose();
    super.dispose();
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F2F7),
      appBar: AppBar(
        title: const Text("Tunnel Share Internal v2"),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder, color: Colors.indigo),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _folderPath ?? "Chưa chọn thư mục",
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      if (_isRunning)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            "ONLINE",
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (_isConnecting && _retryCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            "RETRY $_retryCount/$_maxRetries",
                            style: TextStyle(
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "LINK CHIA SẺ CÔNG KHAI:",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_isConnecting)
                    Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _statusMessage ?? "Đang tạo link...",
                            style: const TextStyle(color: Colors.black87),
                          ),
                        ),
                      ],
                    ),

                  if (_tunnelUrl != null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F0FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              _tunnelUrl!,
                              style: const TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: _tunnelUrl!),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Đã copy link")),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isRunning ? null : _startShare,
                    child: const Text("▶ Bắt đầu Share"),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isRunning ? _stopShare : null,
                    child: const Text("■ Dừng"),
                  ),
                ),
              ],
            ),

            if (kDebugMode) ...[
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "DEBUG LOG",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          if (_logs.isEmpty) return;
                          Clipboard.setData(
                            ClipboardData(text: _logs.join('\n')),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Đã copy toàn bộ log"),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_all, size: 18),
                        label: const Text("Copy"),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.indigo,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          setState(() => _logs.clear());
                        },
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        label: const Text("Clear"),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red.shade400,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.builder(
                    controller: _scroll,
                    itemCount: _logs.length,
                    itemBuilder: (_, i) => Text(
                      _logs[i],
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
