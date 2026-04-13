import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'features/tunnel/presentation/pages/tunnel_page.dart';
import 'features/auth/logic/auth_manager.dart';
import 'features/auth/presentation/pages/login_page.dart';

import 'core/app_config.dart';

void main() {
  debugPrint("--- APP STARTING ---");
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TunnelInternalApp());
}

class TunnelInternalApp extends StatefulWidget {
  const TunnelInternalApp({super.key});

  @override
  State<TunnelInternalApp> createState() => _TunnelInternalAppState();
}

class _TunnelInternalAppState extends State<TunnelInternalApp> {
  bool _isInitialized = false;
  String? _initError;
  AuthManager? _authManager;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    debugPrint("STEP: Starting initialization...");
    try {
      debugPrint("STEP: Initializing Window Manager...");
      await windowManager.ensureInitialized();
      
      // Cấu hình kích thước cửa sổ ngay lập tức để tránh hiệu ứng "nhảy" kích thước
      await windowManager.setSize(const Size(1200, 700));
      await windowManager.setMinimumSize(const Size(1000, 600));
      await windowManager.center();
      await windowManager.setTitle("Shotpik Agent");

      debugPrint("STEP: Loading App Config...");
      await AppConfig.loadFromFiles();
      
      debugPrint("STEP: Initializing Auth Manager...");
      final manager = AuthManager();
      await manager.loadSavedSession();
      
      debugPrint("STEP: Auth Manager Ready.");
      if (mounted) {
        setState(() {
          _authManager = manager;
          _isInitialized = true;
        });
      }

      // Chỉ trì hoãn việc HIỆN cửa sổ để đảm bảo UI đã sẵn sàng
      Future.delayed(const Duration(milliseconds: 400), () async {
        debugPrint("STEP: Showing Window...");
        try {
          await windowManager.show();
          await windowManager.focus();
        } catch (e) {
          debugPrint("WINDOW_SHOW_ERROR: $e");
        }
      });
    } catch (e, stack) {
      debugPrint("CRITICAL_INITIALIZATION_ERROR: $e\n$stack");
      if (mounted) {
        setState(() {
          _initError = "$e\n$stack";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Shotpik Agent",
      theme: ThemeData(
        fontFamily: 'Geomanist',
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD93232),
        ).copyWith(
          primary: const Color(0xFFD93232),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8F9FD),
      ),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_initError != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 80),
                  const SizedBox(height: 24),
                  const Text(
                    "LỖI KHỞI ĐỘNG HỆ THỐNG", 
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black)
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: SelectableText(
                      _initError!, 
                      style: const TextStyle(fontFamily: 'Courier', fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: () => exit(0),
                    icon: const Icon(Icons.exit_to_app),
                    label: const Text("Đóng ứng dụng"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (!_isInitialized || _authManager == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FD),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
               const CircularProgressIndicator(color: Color(0xFFD93232)),
               const SizedBox(height: 24),
               const Text(
                 "Đang khởi động Shotpik Agent...", 
                 style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD93232))
               ),
               const SizedBox(height: 8),
               Text(
                 "Vui lòng đợi trong giây lát", 
                 style: TextStyle(color: Colors.grey.shade600, fontSize: 13)
               ),
            ],
          ),
        ),
      );
    }

    return ListenableBuilder(
      listenable: _authManager!,
      builder: (context, child) {
        if (_authManager!.isAuthenticated) {
          return TunnelHome(authManager: _authManager!);
        } else {
          return LoginPage(authManager: _authManager!);
        }
      },
    );
  }
}
