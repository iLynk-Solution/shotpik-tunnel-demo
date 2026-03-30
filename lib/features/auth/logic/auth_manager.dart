import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'package:jwt_decoder/jwt_decoder.dart'; 
import 'package:http/http.dart' as http;

class AuthManager extends ChangeNotifier {
  String? _authToken;
  Map<String, dynamic>? _userData;
  final _appLinks = AppLinks();
  StreamSubscription? _linkSubscription;
  Uri? _lastProcessedUri; // To prevent processing 'sticky' initial links

  String? get authToken => _authToken;
  Map<String, dynamic>? get userData => _userData;

  bool get isAuthenticated {
    return _authToken != null && _authToken!.isNotEmpty;
  }

  AuthManager() {
    // We don't call _initDeepLinks here because it's async and depends on loadSavedSession
  }

  Future<void> loadSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Load the last handled link to prevent 'sticky' auto-login
    final lastLink = prefs.getString('last_handled_link');
    if (lastLink != null) {
      _lastProcessedUri = Uri.parse(lastLink);
      debugPrint("AUTH_MANAGER: Restored last handled link from storage.");
    }

    // 2. Load the actual session token (Public Key)
    final savedToken = prefs.getString('auth_token');
    debugPrint("AUTH_MANAGER: Loading saved session... Found token: ${savedToken != null}");

    if (savedToken != null) {
      _authToken = savedToken;
      try {
        if (!JwtDecoder.isExpired(savedToken)) {
          _userData = JwtDecoder.decode(savedToken);
          debugPrint("AUTH_MANAGER: User info restored from JWT.");
        }
      } catch (e) {
        debugPrint("AUTH_MANAGER: Token is not a JWT, using as raw token.");
      }
      notifyListeners();
      debugPrint("AUTH_MANAGER: Session restored.");
      // Fetch fresh profile info
      fetchProfile();
    } else {
      debugPrint("AUTH_MANAGER: No saved session found.");
    }

    _initDeepLinks();
  }

  Future<void> fetchProfile() async {
    if (_authToken == null) return;
    
    debugPrint("AUTH_MANAGER: Fetching latest profile from server...");
    try {
      final response = await http.get(
        Uri.parse("https://shotpik.com/api/v1/profile"),
        headers: {
          'Authorization': 'Bearer $_authToken',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _userData = data;
        notifyListeners();
        debugPrint("AUTH_MANAGER: Profile fetched and updated: ${_userData?['data']?['name']}");
      } else {
        debugPrint("AUTH_MANAGER: Failed to fetch profile (${response.statusCode}): ${response.body}");
      }
    } catch (e) {
      debugPrint("AUTH_MANAGER: Error fetching profile: $e");
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
    // We KEEP 'last_handled_link' in SharedPreferences to prevent 'sticky' re-login.
    // We also KEEP it in _lastProcessedUri for this session.
    
    _authToken = null;
    _userData = null;
    
    notifyListeners();
    debugPrint("AUTH_MANAGER: Logout complete (Saved link preserved to avoid auto-relogin).");
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

  Future<void> updateSession(String token) async {
    debugPrint("AUTH_MANAGER: Updating session via internal API.");
    await _saveToken(token);
    _authToken = token;
    
    try {
      _userData = JwtDecoder.decode(token);
      debugPrint("AUTH_MANAGER: User info decoded: $_userData");
    } catch (e) {
      debugPrint("AUTH_MANAGER: Received token is not a JWT, UI will show default user.");
      _userData = null;
    }

    notifyListeners();
    // Fetch fresh profile info
    fetchProfile();
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
          debugPrint("AUTH_MANAGER: User info decoded: $_userData");
        } catch (e) {
          debugPrint("AUTH_MANAGER: Received token is not a JWT, UI will show default user.");
          _userData = null;
        }

        debugPrint("AUTH_MANAGER: Login successful.");
        notifyListeners();
        // Fetch fresh profile info
        fetchProfile();
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
