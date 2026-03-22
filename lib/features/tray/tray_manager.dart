import 'dart:io';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

class AppTrayManager {
  static final AppTrayManager _instance = AppTrayManager._internal();
  factory AppTrayManager() => _instance;
  AppTrayManager._internal();

  final SystemTray _systemTray = SystemTray();
  final Menu _menu = Menu();

  bool _isInitialized = false;
  bool _isRunning = false;
  Function()? _onToggleTunnel;
  Function()? _onExitApp;

  Future<void> init(Function() onExitApp) async {
    if (_isInitialized) return;
    _onExitApp = onExitApp;

    String iconPath = Platform.isWindows
        ? 'assets/app_icon.ico'
        : 'assets/shotpik-agent.png';

    await _systemTray.initSystemTray(iconPath: iconPath);

    _isInitialized = true;

    // Build the menu and set it to the tray
    await updateTrayMenu(isRunning: false);

    // Register click events
    _systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        windowManager.show();
      } else if (eventName == kSystemTrayEventRightClick) {
        _systemTray.popUpContextMenu();
      }
    });
  }

  void setTunnelToggleCallback(Function()? callback) {
    _onToggleTunnel = callback;
  }

  void setExitCallback(Function()? callback) {
    _onExitApp = callback;
  }

  Future<void> updateTrayMenu({
    required bool isRunning,
  }) async {
    _isRunning = isRunning;
    await _buildMenu();
  }

  Future<void> _buildMenu() async {
    await _menu.buildFrom([
      MenuItemLabel(
        label: _isRunning ? 'Status: SERVER ACTIVE' : 'Status: OFFLINE',
        enabled: false,
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: _isRunning ? 'Stop Service' : 'Start Service',
        onClicked: (menuItem) {
          if (_onToggleTunnel != null) {
              _onToggleTunnel!();
          }
        },
      ),
      MenuItemLabel(
        label: 'Show Window',
        onClicked: (menuItem) => windowManager.show(),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Exit',
        onClicked: (menuItem) {
           if (_onExitApp != null) {
              _onExitApp!();
           } else {
              exit(0);
           }
        },
      ),
    ]);
    if (_isInitialized) {
      await _systemTray.setContextMenu(_menu);
    }
  }

  Future<void> destroy() async {
    await _systemTray.destroy();
    _isInitialized = false;
  }
}
