import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../domain/tunnel_models.dart';
import '../../../../core/rsa_utils.dart';
import '../../../../core/app_config.dart';
import '../widgets/top_bar.dart';
import '../widgets/debug_log_view.dart';

class WhitelistPage extends StatefulWidget {
  final Set<String> whitelist;
  final Map<String, SharedFolderData> sharedFolders;
  final List<String> logs;
  final ScrollController logScrollController;
  final VoidCallback onClearLogs;
  final String localApiBase;

  const WhitelistPage({
    super.key,
    required this.whitelist,
    required this.sharedFolders,
    required this.logs,
    required this.logScrollController,
    required this.onClearLogs,
    required this.localApiBase,
  });

  @override
  State<WhitelistPage> createState() => _WhitelistPageState();
}

class _WhitelistPageState extends State<WhitelistPage> {
  List<Map<String, dynamic>> _apiItems = [];
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
    // Refresh when whitelist changes from parent
    if (oldWidget.whitelist != widget.whitelist) {
      _fetchWhitelist();
    }
  }

  Future<void> _fetchWhitelist() async {
    final urlBase = "${widget.localApiBase}/api/v1/whitelist/list";

    // Since GET doesn't have a body, we sign an empty string
    final getSignature = RSAUtils.signBody(AppConfig.rsaPrivateKey, "");

    log("--- WHITELIST API CURL SAMPLES ---");
    log("1. GET (List):");
    log(
      "curl --location --request GET '$urlBase' --header 'Content-Type: application/json' --header 'X-Signature: $getSignature'",
    );
    log("");
    log("2. POST (Set all):");
    log("curl --location --request POST '${widget.localApiBase}/api/v1/whitelist' \\");
    log("--header 'Content-Type: application/json' \\");
    log("--header 'X-Signature: <SIGNATURE_HERE>' \\");
    log("--data '{\"paths\": [\"folder_a\", \"folder_b\"]}'");
    log("-----------------------------------");

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
        final data = json['data'] as List<dynamic>? ?? [];
        setState(() {
          _apiItems = data.map((e) => Map<String, dynamic>.from(e)).toList();
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
            const Text("Xóa hết Whitelist"),
          ],
        ),
        content: const Text(
          "Bạn có chắc muốn xóa toàn bộ danh sách? Các thư mục trong đây sẽ không thể truy cập công khai nữa.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Hủy", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
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
      // Clear always uses an empty body which we must sign
      final signature = RSAUtils.signBody(AppConfig.rsaPrivateKey, "");

      final response = await http.post(
        Uri.parse(url),
        headers: {
          "Content-Type": "application/json",
          "X-Signature": signature,
        },
        body: "", // Empty string as body
      );

      if (response.statusCode == 200) {
        _fetchWhitelist();
      } else {
        setState(() {
          _error = "API Clear Error (${response.statusCode}): ${response.body}";
          _isLoading = false;
        });
      }
    } catch (e) {
      log("Clear whitelist catch error: $e");
      setState(() {
        _error = "Lỗi kết nối khi dọn dẹp whitelist.";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Fallback to prop whitelist if API hasn't loaded yet
    final items = _apiItems.isNotEmpty
        ? _apiItems
        : widget.whitelist.map((namePath) {
            SharedFolderData? f;
            for (var folder in widget.sharedFolders.values) {
              if (folder.namePath == namePath) {
                f = folder;
                break;
              }
            }
            return <String, dynamic>{
              'name_path': namePath,
              'path': f?.localPath ?? '', // Important: Include absolute path
              'name': f?.name ?? '',
              'url': f?.tunnelUrl ?? '',
            };
          }).toList();

    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TopBar(
            subtitle: "Manage your shared folders",
            title: "Whitelist folders",
            child: Row(
              children: [
                IconButton(
                  onPressed: _isLoading ? null : _fetchWhitelist,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.refresh_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    padding: const EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  tooltip: "Refresh whitelist",
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isLoading ? null : _clearWhitelist,
                  icon: Icon(
                    Icons.delete_sweep_rounded,
                    color: Colors.redAccent.withValues(alpha: 0.8),
                    size: 20,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                    padding: const EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  tooltip: "Clear all whitelist",
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade100),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.redAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: items.isEmpty && !_isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.security_rounded,
                          size: 48,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.1),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Whitelist trống.\nHãy thêm thư mục từ Dashboard.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final namePath = item['name_path'] as String? ?? '';
                      final absolutePath = item['path'] as String? ?? '';
                      final name = item['name'] as String? ?? '';
                      final url = item['url'] as String? ?? '';

                      // Resolve name and folder
                      SharedFolderData? matchingFolder;
                      for (var f in widget.sharedFolders.values) {
                        if (f.namePath == namePath || (absolutePath.isNotEmpty && f.localPath == absolutePath)) {
                          matchingFolder = f;
                          break;
                        }
                      }
                      final displayName = name.isNotEmpty ? name : (matchingFolder?.name ?? namePath);

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade100),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.security_rounded,
                                size: 18,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    matchingFolder?.localPath ??
                                        (url.isNotEmpty
                                            ? url
                                            : "Link tag: $namePath"),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.5),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline_rounded,
                                size: 18,
                                color: Colors.redAccent,
                              ),
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    title: const Row(
                                      children: [
                                        Icon(
                                          Icons.remove_moderator_rounded,
                                          color: Colors.redAccent,
                                        ),
                                        SizedBox(width: 8),
                                        const Text("Gỡ khỏi Whitelist"),
                                      ],
                                    ),
                                    content: Text(
                                      "Bạn có chắc muốn gỡ thư mục '$displayName' khỏi Whitelist?\nLink tunnel của thư mục này sẽ không thể download công khai.",
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text(
                                          "Hủy",
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ),
                                      ElevatedButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.redAccent,
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                        child: const Text("Đồng ý"),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true) return;

                                try {
                                  setState(() {
                                    _isLoading = true;
                                  });
                                  
                                  // Use absolutePath if available, otherwise namePath (fallback)
                                  final deleteTarget = absolutePath.isNotEmpty ? absolutePath : namePath;
                                  final url = "${widget.localApiBase}/api/v1/whitelist/delete";
                                  final body = jsonEncode({"path": deleteTarget});
                                  
                                  final signature = RSAUtils.signBody(
                                    AppConfig.rsaPrivateKey,
                                    body,
                                  );

                                  final response = await http.delete(
                                    Uri.parse(url),
                                    headers: {
                                      "Content-Type": "application/json",
                                      "X-Signature": signature,
                                    },
                                    body: body,
                                  );
                                  
                                  if (response.statusCode == 200) {
                                    _fetchWhitelist(); // Refresh UI
                                  } else {
                                    log("Delete whitelist error: ${response.body}");
                                    setState(() {
                                      _error = "Lỗi khi gỡ whitelist: ${response.statusCode}";
                                      _isLoading = false;
                                    });
                                  }
                                } catch (e) {
                                  log("Delete whitelist catch error: $e");
                                  setState(() {
                                    _error = "Lỗi kết nối khi gỡ whitelist.";
                                    _isLoading = false;
                                  });
                                }
                              },
                              tooltip: "Gỡ khỏi Whitelist",
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 300,
            child: DebugLogView(
              logs: widget.logs,
              scrollController: widget.logScrollController,
              onClearLogs: widget.onClearLogs,
            ),
          ),
        ],
      ),
    );
  }
}
