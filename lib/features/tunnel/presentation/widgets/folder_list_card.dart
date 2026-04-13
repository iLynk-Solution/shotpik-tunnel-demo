import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shotpik_agent/core/app_config.dart';
import 'package:shotpik_agent/core/rsa_utils.dart';

class FolderListCard extends StatelessWidget {
  final String localApiBase;
  final bool isRunning;
  final List<String> watchFolders;
  final Set<String> whitelist;

  const FolderListCard({
    super.key,
    required this.localApiBase,
    required this.isRunning,
    required this.watchFolders,
    required this.whitelist,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context),
        const SizedBox(height: 16),
        if (watchFolders.isEmpty)
          _buildEmptyState(
            context,
            "Chưa có thư mục nào được thêm. Hãy vào Cài đặt để thêm.",
            Icons.folder_open_rounded,
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: watchFolders.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final path = watchFolders[index];
              final name = p.basename(path);
              final namePath = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
              
              return _FolderItem(
                localApiBase: localApiBase,
                name: name,
                path: path,
                namePath: namePath,
                isRunning: isRunning,
                isWhitelisted: whitelist.contains(namePath) || whitelist.contains(path) || whitelist.contains(path.endsWith('/') ? path : '$path/'),
              );
            },
          ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(
              Icons.folder_copy_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              "THƯ MỤC THEO DÕI",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              "${watchFolders.length}",
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, String message, IconData icon) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 48,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderItem extends StatelessWidget {
  final String localApiBase;
  final String name;
  final String path;
  final String namePath;
  final bool isRunning;
  final bool isWhitelisted;

  const _FolderItem({
    required this.localApiBase,
    required this.name,
    required this.path,
    required this.namePath,
    required this.isRunning,
    required this.isWhitelisted,
  });

  @override
  Widget build(BuildContext context) {
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
              Icons.folder_rounded,
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
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  path,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Whitelist Toggle
          IconButton(
            onPressed: isRunning
                ? () async {
                    final isAdding = !isWhitelisted;
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        title: Row(
                          children: [
                            Icon(
                              isAdding ? Icons.security_rounded : Icons.remove_moderator_rounded,
                              color: isAdding ? Colors.blueAccent : Colors.redAccent,
                            ),
                            const SizedBox(width: 8),
                            Text(isAdding ? "Xác nhận Whitelist" : "Gỡ khỏi Whitelist"),
                          ],
                        ),
                        content: Text(
                          isAdding
                              ? "Cho phép công khai thư mục '$name'?\nMọi người có thể download file từ link Public Portal."
                              : "Bạn có chắc muốn gỡ thư mục '$name' khỏi Whitelist?",
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text("Hủy", style: TextStyle(color: Colors.grey)),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isAdding ? Theme.of(context).colorScheme.primary : Colors.redAccent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text("Đồng ý"),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;

                    final endpoint = isAdding ? "" : "/delete";
                    final apiUrl = "$localApiBase/api/v1/whitelist$endpoint";
                    final body = jsonEncode({"path": path});
                    final signature = RSAUtils.signBody(AppConfig.rsaPrivateKey, body);

                    try {
                      final response = await (isAdding
                          ? http.post(
                              Uri.parse(apiUrl),
                              headers: {"Content-Type": "application/json", "X-Signature": signature},
                              body: body,
                            )
                          : http.delete(
                              Uri.parse(apiUrl),
                              headers: {"Content-Type": "application/json", "X-Signature": signature},
                              body: body,
                            ));
                      if (response.statusCode != 200) {
                        log("Whitelist API error: ${response.body}");
                      }
                    } catch (e) {
                      log("Whitelist API catch error: $e");
                    }
                  }
                : null,
            icon: Icon(
              isWhitelisted ? Icons.security_rounded : Icons.security_outlined,
              size: 18,
              color: isWhitelisted ? Theme.of(context).colorScheme.primary : Colors.grey,
            ),
            tooltip: isWhitelisted ? "Gỡ khỏi Whitelist" : "Thêm vào Whitelist",
          ),
        ],
      ),
    );
  }
}
