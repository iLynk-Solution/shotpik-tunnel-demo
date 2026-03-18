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
  Uri? _lastProcessedUri; // To prevent processing 'sticky' initial links

  String? get authToken => _authToken;
  Map<String, dynamic>? get userData => _userData;
  bool get isAuthenticated => _authToken != null && !JwtDecoder.isExpired(_authToken!);
  String? get userEmail => _userData?['email'] as String?;
  String? get userName => _userData?['name'] as String?;

  AuthManager() {
    _initDeepLinks();
  }

  Future<void> loadSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Load the last handled link to prevent 'sticky' auto-login
    final lastLink = prefs.getString('last_handled_link');
    if (lastLink != null) {
      _lastProcessedUri = Uri.parse(lastLink);
      debugPrint("AUTH_MANAGER: Restored last handled link from storage.");
    }

    // 2. Load the actual session token
    final savedToken = prefs.getString('auth_token');
    debugPrint("AUTH_MANAGER: Loading saved session... Found token: ${savedToken != null}");
    
    if (savedToken != null && !JwtDecoder.isExpired(savedToken)) {
      _authToken = savedToken;
      try {
        _userData = JwtDecoder.decode(savedToken);
        debugPrint("AUTH_MANAGER: Session restored for: ${userEmail ?? 'Unknown'}");
      } catch (e) {
        debugPrint("AUTH_MANAGER: Error decoding saved token: $e");
      }
      notifyListeners();
    } else {
      debugPrint("AUTH_MANAGER: No valid saved session found.");
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
    debugPrint("AUTH_MANAGER: Logging out...");
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    
    _authToken = null;
    _userData = null;
    _lastProcessedUri = null; // Clear this so a new login can happen
    
    notifyListeners();
    debugPrint("AUTH_MANAGER: Logout complete.");
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

    // Prevent processing the exact same URI multiple times (Sticky link issue on macOS)
    if (_lastProcessedUri == uri) {
      debugPrint("AUTH_MANAGER: Ignoring duplicate deep link (sticky): $uri");
      return;
    }
    _lastProcessedUri = uri;
    
    // Persist this URI so we remember it even after restart
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('last_handled_link', uri.toString());
    });

    debugPrint("AUTH_MANAGER: Handling incoming link: $uri");

    bool isAuthLink = (uri.scheme == 'tunnel' && uri.host == 'auth') ||
        (uri.scheme == 'https' && uri.host == 'shotpik.com' && uri.path == '/auth');

    if (isAuthLink) {
      final token = uri.queryParameters['token'];
      if (token != null) {
        debugPrint("AUTH_MANAGER: Valid token received from deep link.");
        _saveToken(token);
        _authToken = token;
        try {
          _userData = JwtDecoder.decode(token);
          debugPrint("AUTH_MANAGER: Login successful for: ${userEmail ?? 'Unknown'}");
        } catch (e) {
          debugPrint("AUTH_MANAGER: Error decoding token: $e");
        }
        notifyListeners();
      } else {
        debugPrint("AUTH_MANAGER: Deep link received but no token found.");
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
