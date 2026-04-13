import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../../core/rsa_utils.dart';
import '../../../../core/app_config.dart';
import '../widgets/top_bar.dart';

class WhitelistPage extends StatefulWidget {
  final Set<String> whitelist;
  final List<String> logs;
  final ScrollController logScrollController;
  final VoidCallback onClearLogs;
  final String localApiBase;

  const WhitelistPage({
    super.key,
    required this.whitelist,
    required this.logs,
    required this.logScrollController,
    required this.onClearLogs,
    required this.localApiBase,
    required Map sharedFolders,
  });

  @override
  State<WhitelistPage> createState() => _WhitelistPageState();
}

class _WhitelistPageState extends State<WhitelistPage> {
  List<String> _apiItems = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchWhitelist();
  }

  @override
  void didUpdateWidget(WhitelistPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.whitelist != widget.whitelist) {
      _fetchWhitelist();
    }
  }

  Future<void> _fetchWhitelist() async {
    final urlBase = "${widget.localApiBase}/api/v1/whitelist/list";
    final getSignature = RSAUtils.signBody(AppConfig.rsaPrivateKey, "");

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await http.get(
        Uri.parse(urlBase),
        headers: {
          "Content-Type": "application/json",
          "X-Signature": getSignature,
        },
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final data = List<String>.from(json['data'] ?? []);
        setState(() {
          _apiItems = data;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = "API Error (${response.statusCode})";
          _isLoading = false;
        });
      }
    } catch (e) {
      log("Whitelist fetch error: $e");
      setState(() {
        _error = "Không thể kết nối tới server.";
        _isLoading = false;
      });
    }
  }

  Future<void> _clearWhitelist() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text("Xóa hết Whitelist"),
          ],
        ),
        content: const Text("Xóa toàn bộ Whitelist sẽ gỡ quyền truy cập công khai của tất cả thư mục."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Hủy", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, elevation: 0),
            child: const Text("Đồng ý"),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final url = "${widget.localApiBase}/api/v1/whitelist/clear";
      final signature = RSAUtils.signBody(AppConfig.rsaPrivateKey, "");
      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json", "X-Signature": signature},
        body: "",
      );
      if (response.statusCode == 200) {
        _fetchWhitelist();
      } else {
        setState(() {
          _error = "API Clear Error (${response.statusCode})";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = "Lỗi kết nối khi dọn dẹp whitelist.";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _apiItems.isNotEmpty ? _apiItems : widget.whitelist.toList();

    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TopBar(
            subtitle: "Quản lý danh sách thư mục được phép truy cập công khai",
            title: "Danh sách trắng",
            child: Row(
              children: [
                IconButton(
                  onPressed: _isLoading ? null : _fetchWhitelist,
                  icon: _isLoading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.refresh_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
                  style: IconButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1), padding: const EdgeInsets.all(12)),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isLoading ? null : _clearWhitelist,
                  icon: Icon(Icons.delete_sweep_rounded, color: Colors.redAccent.withValues(alpha: 0.8), size: 20),
                  style: IconButton.styleFrom(backgroundColor: Colors.redAccent.withValues(alpha: 0.1), padding: const EdgeInsets.all(12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ),
          Expanded(
            child: items.isEmpty && !_isLoading
                ? const Center(child: Text("Danh sách trắng trống."))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final namePath = items[index];
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade100)),
                        child: Row(
                          children: [
                            Icon(Icons.security_rounded, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 12),
                            Expanded(child: Text(namePath, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline_rounded, size: 18, color: Colors.redAccent),
                              onPressed: () async {
                                final apiUrl = "${widget.localApiBase}/api/v1/whitelist/delete";
                                final body = jsonEncode({"path": namePath});
                                final signature = RSAUtils.signBody(AppConfig.rsaPrivateKey, body);
                                final response = await http.delete(
                                  Uri.parse(apiUrl),
                                  headers: {"Content-Type": "application/json", "X-Signature": signature},
                                  body: body,
                                );
                                if (response.statusCode == 200) _fetchWhitelist();
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
