import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'features/tunnel/presentation/pages/tunnel_page.dart';
import 'features/auth/logic/auth_manager.dart';
import 'features/auth/presentation/pages/login_page.dart';

import 'core/app_config.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    
    // 1. Core window initialization
    await windowManager.ensureInitialized();

    // 2. Load Core Data (Keys & Auth-Session)
    await AppConfig.loadFromFiles();
    final authManager = AuthManager();
    await authManager.loadSavedSession();

    // 3. Setup Window Options
    const windowOptions = WindowOptions(
      size: Size(1200, 700),
      center: true,
      title: "Shotpik Agent",
      skipTaskbar: false,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setMinimumSize(const Size(1200, 600));
      await windowManager.setPreventClose(false);
    });

    // 4. Run the app
    runApp(TunnelInternalApp(authManager: authManager));
  } catch (e, stack) {
    debugPrint("CRITICAL_ERROR: $e\n$stack");
    // Even if error, try to run app to show something
    runApp(MaterialApp(home: Scaffold(body: Center(child: Text("Fatal Error during startup: $e")))));
  }
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
