# shotpik_tunnel_demo

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

# shotpik-tunnel-demo
```
flutter clean && flutter pub get && flutter build macos --release && cp -R "build/macos/Build/Products/Release/Shotpik Agent.app" dmg/ && create-dmg \
  --volname "ShotpikAgent" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "Shotpik Agent.app" 200 190 \
  --hide-extension "Shotpik Agent.app" \
  --app-drop-link 600 185 \
  "ShotpikAgent.dmg" \
  "dmg/"
```