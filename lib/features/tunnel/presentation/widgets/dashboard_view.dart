import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../domain/tunnel_models.dart';
import 'status_config_card.dart';
import 'folder_list_card.dart';
import 'top_bar.dart';
import 'error_card.dart';

// Since SharedFolderData might be in tunnel_models.dart now, we use that.
// If it's still in a separate file, we'll fix the path.
// Based on typical refactors, models are often moved to domain/ folder.

class DashboardView extends StatelessWidget {
  final int? currentPort;
  final ScrollController scrollController;
  final String searchRoot;
  final VoidCallback onPickSearchRoot;
  final TextEditingController searchController;
  final VoidCallback onSearch;
  final bool isSearching;
  final VoidCallback onClearSearch;
  final bool isRunning;
  final bool isConnecting;
  final String? statusMessage;
  final VoidCallback onToggleTunnel;
  final String? tunnelUrl;
  final String? error;
  final List<dynamic> searchResults;
  final VoidCallback onClearSearchResults;
  final Function(String) onStartSharingForPath;
  final Map<String, SharedFolderData> sharedFolders;
  final String apiToken;
  final Set<String> whitelist;
  final VoidCallback onAddFolder;
  final Function(String) onRemoveFolder;
  final Function(String) onRefreshTunnel;
  final Function(SharedFolderData) onExportFolder;

  const DashboardView({
    super.key,
    required this.currentPort,
    required this.scrollController,
    required this.searchRoot,
    required this.onPickSearchRoot,
    required this.searchController,
    required this.onSearch,
    required this.isSearching,
    required this.onClearSearch,
    required this.isRunning,
    required this.isConnecting,
    this.statusMessage,
    required this.onToggleTunnel,
    this.tunnelUrl,
    this.error,
    required this.searchResults,
    required this.onClearSearchResults,
    required this.onStartSharingForPath,
    required this.sharedFolders,
    required this.apiToken,
    required this.whitelist,
    required this.onAddFolder,
    required this.onRemoveFolder,
    required this.onRefreshTunnel,
    required this.onExportFolder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(
                title: "Dashboard Overview",
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: "Chọn thư mục gốc để tìm kiếm ($searchRoot)",
                      child: IconButton(
                        onPressed: onPickSearchRoot,
                        icon: Icon(
                          Icons.folder_open_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.1),
                          padding: const EdgeInsets.all(12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: SizedBox(
                        height: 48,
                        child: TextField(
                          controller: searchController,
                          textAlignVertical: TextAlignVertical.center,
                          onSubmitted: (_) => onSearch(),
                          decoration: InputDecoration(
                            hintText: "Tìm kiếm thư mục...",
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.3),
                            ),
                            prefixIcon:
                                const Icon(Icons.search_rounded, size: 20),
                            suffixIcon: searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close_rounded,
                                        size: 16),
                                    onPressed: onClearSearch,
                                  )
                                : null,
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade200),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.2),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: isSearching ? null : onSearch,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isSearching
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                "Tìm",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusConfigCard(
                        isRunning: isRunning,
                        isConnecting: isConnecting,
                        statusMessage: statusMessage ??
                            (isRunning ? "Tunnel Online" : "Tunnel Offline"),
                        onToggleTunnel: onToggleTunnel,
                        tunnelUrl: tunnelUrl,
                      ),
                      if (error != null) ErrorCard(error: error!),
                      if (searchResults.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(20),
                          margin: const EdgeInsets.only(top: 24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.grey.shade100),
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
                              Row(
                                children: [
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        const TextSpan(
                                          text: "Kết quả tìm kiếm",
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        TextSpan(
                                          text: " ($searchRoot)",
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.normal,
                                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: onClearSearchResults,
                                    child: const Text("Xóa kết quả"),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: searchResults.length,
                                separatorBuilder: (context, index) =>
                                    const Divider(),
                                itemBuilder: (context, index) {
                                  final item = searchResults[index];
                                  final path = item['path'] as String;
                                  final name = p.basename(path);
                                  return ListTile(
                                    leading: Icon(
                                      Icons.folder_rounded,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                    title: Text(name),
                                    subtitle: Text(path),
                                    trailing: ElevatedButton(
                                      onPressed: () =>
                                          onStartSharingForPath(path),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      child: const Text("Thêm"),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 24),
                      FolderListCard(
                        currentPort: currentPort,
                        isRunning: isRunning,
                        sharedFolders: sharedFolders,
                        apiToken: apiToken,
                        whitelist: whitelist,
                        onAddFolder: onAddFolder,
                        onRemoveFolder: onRemoveFolder,
                        onRefreshTunnel: onRefreshTunnel,
                        onExportFolder: onExportFolder,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
