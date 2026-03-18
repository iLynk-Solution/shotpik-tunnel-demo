import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../domain/tunnel_models.dart';

class FolderListCard extends StatelessWidget {
  final bool isRunning;
  final Map<String, SharedFolderData> sharedFolders;
  final String apiToken;
  final String? mainTunnelUrl;
  final VoidCallback onAddFolder;
  final Function(String) onRemoveFolder;
  final Function(String) onRefreshTunnel;

  const FolderListCard({
    super.key,
    required this.isRunning,
    required this.sharedFolders,
    required this.apiToken,
    this.mainTunnelUrl,
    required this.onAddFolder,
    required this.onRemoveFolder,
    required this.onRefreshTunnel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const Divider(height: 1),
          if (sharedFolders.isEmpty)
            _buildEmptyState(
              context,
              isRunning
                  ? "No folders shared yet. Click + to add one."
                  : "Folder list is saved. Start server to share.",
              Icons.folder_open_rounded,
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: sharedFolders.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
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
                  bool isAvailable = (folder.tunnelUrl != null && !folder.isConnecting);

                  return _FolderItem(
                    folder: folder,
                    url: urlText,
                    isRunning: isRunning,
                    isAvailable: isAvailable,
                    onRemove: () => onRemoveFolder(folder.id),
                    onRefresh: () => onRefreshTunnel(folder.id),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "${sharedFolders.length}",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: isRunning ? onAddFolder : null,
            icon: Icon(Icons.add_rounded, color: Theme.of(context).colorScheme.primary),
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              padding: const EdgeInsets.all(8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String message, IconData icon) {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderItem extends StatelessWidget {
  final SharedFolderData folder;
  final String url;
  final bool isRunning;
  final bool isAvailable;
  final VoidCallback onRemove;
  final VoidCallback onRefresh;

  const _FolderItem({
    required this.folder,
    required this.url,
    required this.isRunning,
    required this.isAvailable,
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
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
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
                  onPressed: isRunning && !folder.isConnecting ? onRefresh : null,
                  icon: Icon(
                    folder.tunnelUrl == null ? Icons.play_arrow_rounded : Icons.refresh_rounded,
                    size: 18,
                    color: isRunning ? Theme.of(context).colorScheme.primary : Colors.grey,
                  ),
                  tooltip: folder.tunnelUrl == null ? "Bắt đầu Tunnel" : "Cấp lại link tunnel",
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
                  border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
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
                              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                          fontStyle: hasUrl
                              ? FontStyle.normal
                              : FontStyle.italic,
                        ),
                      ),
                    ),
                    if (hasUrl) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.copy_rounded,
                        size: 14,
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
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
