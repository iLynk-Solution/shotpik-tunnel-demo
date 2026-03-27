import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../domain/tunnel_models.dart';
import 'folder_list_card.dart';
import 'top_bar.dart';
import 'error_card.dart';
import 'debug_log_view.dart';

class DashboardView extends StatelessWidget {
  final String localApiBase;
  final ScrollController scrollController;

  final TextEditingController searchController;
  final VoidCallback onSearch;
  final bool isSearching;
  final VoidCallback onClearSearch;
  final bool isRunning;
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
  final List<String> logs;
  final ScrollController logScrollController;
  final VoidCallback onClearLogs;

  const DashboardView({
    super.key,
    required this.localApiBase,
    required this.scrollController,
    required this.logScrollController,
    required this.logs,
    required this.onClearLogs,

    required this.searchController,
    required this.onSearch,
    required this.isSearching,
    required this.onClearSearch,
    required this.isRunning,
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
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.3),
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 20,
                            ),
                            suffixIcon: searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 16,
                                    ),
                                    onPressed: onClearSearch,
                                  )
                                : null,
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.grey.shade200,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.2),
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
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
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
                      if (error != null) ErrorCard(error: error!),
                       if (searchResults.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 24),
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
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final item = searchResults[index];
                                  final path = item['path'] as String;
                                  final name = p.basename(path);
                                  return Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.grey.shade100,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.surface,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Icon(
                                            Icons.folder_rounded,
                                            size: 18,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
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
                                        const SizedBox(width: 12),
                                        ElevatedButton(
                                          onPressed: () =>
                                              onStartSharingForPath(path),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          child: const Text("Thêm"),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        )
                      else if (!isSearching &&
                          searchController.text.isNotEmpty &&
                          error == null)
                        const Padding(
                          padding: EdgeInsets.only(top: 24),
                          child: ErrorCard(error: "Không tìm thấy kết quả nào"),
                        ),
                      if (kDebugMode) ...[
                        const SizedBox(height: 24),
                        FolderListCard(
                          localApiBase: localApiBase,
                          isRunning: isRunning,
                          sharedFolders: sharedFolders,
                          apiToken: apiToken,
                          whitelist: whitelist,
                          onAddFolder: onAddFolder,
                          onRemoveFolder: onRemoveFolder,
                          onRefreshTunnel: onRefreshTunnel,
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          height: 300,
                          child: DebugLogView(
                            logs: logs,
                            scrollController: logScrollController,
                            onClearLogs: onClearLogs,
                          ),
                        ),
                      ],
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
