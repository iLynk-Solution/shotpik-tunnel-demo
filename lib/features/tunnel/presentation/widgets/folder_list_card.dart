import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shotpik_agent/core/app_config.dart';
import 'package:shotpik_agent/core/rsa_utils.dart';
import 'package:shotpik_agent/features/tunnel/domain/tunnel_models.dart';

class FolderListCard extends StatelessWidget {
  final String localApiBase;
  final bool isRunning;
  final Map<String, SharedFolderData> sharedFolders;
  final String apiToken;
  final String? mainTunnelUrl;
  final VoidCallback onAddFolder;
  final Function(String) onRemoveFolder;
  final Function(String) onRefreshTunnel;
  final Set<String> whitelist;

  const FolderListCard({
    super.key,
    required this.localApiBase,
    required this.isRunning,
    required this.sharedFolders,
    required this.apiToken,
    this.mainTunnelUrl,
    required this.onAddFolder,
    required this.onRemoveFolder,
    required this.onRefreshTunnel,
    required this.whitelist,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context),
        const SizedBox(height: 16),
        if (sharedFolders.isEmpty)
          _buildEmptyState(
            context,
            isRunning
                ? "No folders shared yet. Click + to add one."
                : "Folder list is saved. Start server to share.",
            Icons.folder_open_rounded,
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sharedFolders.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final folder = sharedFolders.values.elementAt(index);
              String urlText;

              if (folder.tunnelUrl != null) {
                urlText = folder.tunnelUrl!;
              } else if (folder.isConnecting) {
                urlText = "Creating Tunnel...";
              } else if (!isRunning) {
                urlText = "Server Offline";
              } else {
                urlText = "Tunnel Offline (Ready to Start)";
              }

              // Force rebuild hasUrl logic
              bool isAvailable =
                  (folder.tunnelUrl != null && !folder.isConnecting);

              return _FolderItem(
                localApiBase: localApiBase,
                folder: folder,
                url: urlText,
                isRunning: isRunning,
                isAvailable: isAvailable,
                isWhitelisted: whitelist.contains(folder.namePath),
                onRemove: () => onRemoveFolder(folder.id),
                onRefresh: () => onRefreshTunnel(folder.id),
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
              Icons.folder_shared_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              "SHARED ALBUMS",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              "${sharedFolders.length}",
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        IconButton(
          onPressed: isRunning ? onAddFolder : null,
          icon: Icon(
            Icons.add_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.1),
            padding: const EdgeInsets.all(8),
          ),
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
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.1),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.4),
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
  final SharedFolderData folder;
  final String url;
  final bool isRunning;
  final bool isAvailable;
  final bool isWhitelisted;
  final VoidCallback onRemove;
  final VoidCallback onRefresh;

  const _FolderItem({
    required this.localApiBase,
    required this.folder,
    required this.url,
    required this.isRunning,
    required this.isAvailable,
    required this.isWhitelisted,
    required this.onRemove,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    bool hasUrl = isAvailable && isRunning;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                      folder.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      folder.localPath,
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (folder.isConnecting)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                if (hasUrl)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: Colors.green,
                  )
                else
                  const Icon(
                    Icons.cloud_off_rounded,
                    size: 16,
                    color: Colors.grey,
                  ),
                const SizedBox(width: 8),

                // Regenerate/Refresh Button
                IconButton(
                  onPressed:
                      isRunning && !folder.isConnecting ? onRefresh : null,
                  icon: Icon(
                    folder.tunnelUrl == null
                        ? Icons.play_arrow_rounded
                        : Icons.refresh_rounded,
                    size: 18,
                    color: isRunning
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                  ),
                  tooltip: folder.tunnelUrl == null
                      ? "Bắt đầu Tunnel"
                      : "Cấp lại link tunnel",
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 12),

                // Whitelist Toggle Button (Now calling API with confirmation for ADD)
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
                                    isAdding
                                        ? Icons.security_rounded
                                        : Icons.remove_moderator_rounded,
                                    color: isAdding
                                        ? Colors.blueAccent
                                        : Colors.redAccent,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isAdding
                                        ? "Xác nhận Whitelist"
                                        : "Gỡ khỏi Whitelist",
                                  ),
                                ],
                              ),
                              content: Text(
                                isAdding
                                    ? "Cho phép công khai thư mục '${folder.name}'?\nMọi người có thể download file từ link tunnel này."
                                    : "Bạn có chắc muốn gỡ thư mục '${folder.name}' khỏi Whitelist?\nLink tunnel của thư mục này sẽ không thể download công khai.",
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
                                  onPressed: () => Navigator.pop(context, true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isAdding
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.redAccent,
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

                          final endpoint = isAdding ? "" : "/delete";
                          final method = isAdding ? "POST" : "DELETE";

                          final apiUrl =
                              "$localApiBase/api/v1/whitelist$endpoint";
                          final body = jsonEncode({"path": folder.namePath});
                          final signature = RSAUtils.signBody(
                            AppConfig.rsaPrivateKey,
                            body,
                          );

                          log(
                            "--- ${isAdding ? 'ADD' : 'DELETE'} WHITELIST CURL FROM DASHBOARD ---",
                          );
                          log(
                            "curl --location --request $method '$apiUrl' \\",
                          );
                          log(
                            "--header 'Content-Type: application/json' \\",
                          );
                          log("--header 'X-Signature: $signature' \\");
                          log("--data '$body'");

                          try {
                            final response = await (isAdding
                                ? http.post(
                                    Uri.parse(apiUrl),
                                    headers: {
                                      "Content-Type": "application/json",
                                      "X-Signature": signature,
                                    },
                                    body: body,
                                  )
                                : http.delete(
                                    Uri.parse(apiUrl),
                                    headers: {
                                      "Content-Type": "application/json",
                                      "X-Signature": signature,
                                    },
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
                    isWhitelisted
                        ? Icons.security_rounded
                        : Icons.security_outlined,
                    size: 18,
                    color: isWhitelisted
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                  ),
                  tooltip: isWhitelisted
                      ? "Gỡ khỏi Whitelist"
                      : "Thêm vào Whitelist",
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
              const SizedBox(width: 12),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: Colors.redAccent,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: "Remove folder",
              ),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: hasUrl
                ? () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Link copied to clipboard")),
                    );
                  }
                : null,
            child: Opacity(
              opacity: hasUrl ? 1.0 : 0.6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: hasUrl
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.4),
                          fontStyle: hasUrl ? FontStyle.normal : FontStyle.italic,
                        ),
                      ),
                    ),
                    if (hasUrl) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.copy_rounded,
                        size: 14,
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.5),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
