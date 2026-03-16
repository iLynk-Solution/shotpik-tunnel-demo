import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';

class AuthManager extends ChangeNotifier {
  String? _authToken;
  Map<String, dynamic>? _userData;
  final _appLinks = AppLinks();
  StreamSubscription? _linkSubscription;

  String? get authToken => _authToken;
  Map<String, dynamic>? get userData => _userData;
  bool get isAuthenticated => _authToken != null && !JwtDecoder.isExpired(_authToken!);

  AuthManager() {
    _initDeepLinks();
  }

  Future<void> loadSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('auth_token');
    if (savedToken != null && !JwtDecoder.isExpired(savedToken)) {
      _authToken = savedToken;
      try {
        _userData = JwtDecoder.decode(savedToken);
      } catch (e) {
        debugPrint("Error decoding saved token: $e");
      }
      notifyListeners();
    }
  }

  Future<void> loginWeb() async {
    final url = Uri(
      scheme: 'https',
      host: 'shotpik.com',
      path: '/login',
      queryParameters: {
        'redirect_uri': 'tunnel://auth',
      },
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    _authToken = null;
    _userData = null;
    notifyListeners();
  }

  void _initDeepLinks() {
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleIncomingLink(uri);
    });

    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri? uri) => _handleIncomingLink(uri),
      onError: (err) => debugPrint("Deep link error: $err"),
    );
  }

  void _handleIncomingLink(Uri? uri) {
    if (uri == null) return;

    bool isAuthLink = (uri.scheme == 'tunnel' && uri.host == 'auth') ||
        (uri.scheme == 'https' && uri.host == 'shotpik.com' && uri.path == '/auth');

    if (isAuthLink) {
      final token = uri.queryParameters['token'];
      if (token != null) {
        _saveToken(token);
        _authToken = token;
        try {
          _userData = JwtDecoder.decode(token);
        } catch (e) {
          debugPrint("Error decoding token: $e");
        }
        notifyListeners();
      }
    }
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }
}
