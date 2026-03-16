import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'features/tunnel/presentation/pages/tunnel_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(900, 700),
      center: true,
      title: "Shotpik Agent",
      skipTaskbar: true,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setPreventClose(true); // QUAN TRỌNG: Ngăn chặn thoát App khi bấm X
    },
  );

  runApp(const TunnelInternalApp());
}

class TunnelInternalApp extends StatelessWidget {
  const TunnelInternalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Geomanist',
        useMaterial3: true,
      ),
      home: const TunnelHome(),
    );
  }
}
