import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';
import 'features/tunnel/presentation/pages/tunnel_page.dart';
import 'features/auth/logic/auth_manager.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/tray/tray_manager.dart';
import 'core/app_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  
  // Load RSA keys from local files (public_key.pem / private_key.pem)
  await AppConfig.loadFromFiles();

  windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(900, 700),
      center: true,
      title: "Shotpik Agent",
      skipTaskbar: true, // Ẩn khỏi taskbar để chạy ngầm
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setMinimumSize(const Size(1024, 600));
      await windowManager.setPreventClose(
        true, // Ngăn chặn thoát App khi bấm X
      );
    },
  );

  await AppTrayManager().init(() {
    exit(0);
  });

  final authManager = AuthManager();
  await authManager.loadSavedSession();

  runApp(TunnelInternalApp(authManager: authManager));
}

class TunnelInternalApp extends StatelessWidget {
  final AuthManager authManager;

  const TunnelInternalApp({super.key, required this.authManager});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Geomanist',
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD93232),
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFFD93232),
          onPrimary: Colors.white,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8F9FD),
      ),
      themeMode: ThemeMode.light,
      home: ListenableBuilder(
        listenable: authManager,
        builder: (context, child) {
          if (authManager.isAuthenticated) {
            return TunnelHome(authManager: authManager);
          } else {
            return LoginPage(authManager: authManager);
          }
        },
      ),
    );
  }
}
