import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
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
  final List<dynamic> searchResults;
  final VoidCallback onClearSearchResults;
  final List<String> watchFolders;
  final String apiToken;
  final Set<String> whitelist;
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
    required this.searchResults,
    required this.onClearSearchResults,
    required this.watchFolders,
    required this.apiToken,
    required this.whitelist,
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
                title: "Tổng quan bảng điều khiển",
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
                                "Tìm kiếm",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32.0),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    children: [
                      if (searchResults.isNotEmpty)
                        _buildSearchResults(context)
                      else if (searchController.text.isNotEmpty &&
                          !isSearching)
                        const ErrorCard(
                          error:
                              "Không tìm thấy thư mục nào khớp với từ khóa của bạn.",
                        )
                      else
                        FolderListCard(
                          localApiBase: localApiBase,
                          isRunning: isRunning,
                          watchFolders: watchFolders,
                          whitelist: whitelist,
                        ),
                      if (kDebugMode) ...[
                        const SizedBox(height: 32.0),
                        SizedBox(
                          height: 400,
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

  Widget _buildSearchResults(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "KẾT QUẢ TÌM KIẾM",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            TextButton.icon(
              onPressed: onClearSearchResults,
              icon: const Icon(Icons.close_rounded, size: 14),
              label: const Text("Xóa kết quả", style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: searchResults.length,
          itemBuilder: (context, index) {
            final item = searchResults[index];
            final path = item['path'] as String;
            final name = p.basename(path);

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade100),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 16),
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
                          Text(
                            path,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
