import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shotpik_agent/features/tunnel/presentation/widgets/top_bar.dart';
import 'package:shotpik_agent/features/tunnel/presentation/widgets/status_config_card.dart';

class SettingsPage extends StatefulWidget {
  final bool isRunning;
  final bool isConnecting;
  final String? statusMessage;
  final VoidCallback onToggleTunnel;
  final String? tunnelUrl;
  final Function(List<String>) onWatchFoldersChanged;

  const SettingsPage({
    super.key,
    required this.isRunning,
    required this.isConnecting,
    this.statusMessage,
    required this.onToggleTunnel,
    this.tunnelUrl,
    required this.onWatchFoldersChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<String> _watchFolders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWatchFolders();
  }

  Future<void> _loadWatchFolders() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _watchFolders = prefs.getStringList('watch_folders') ?? [];
      _isLoading = false;
    });
    widget.onWatchFoldersChanged(_watchFolders);
  }

  Future<void> _saveWatchFolders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('watch_folders', _watchFolders);
  }

  Future<void> _addFolder() async {
    final String? path = await getDirectoryPath(
      confirmButtonText: "Chọn thư mục",
    );
    if (path != null && !_watchFolders.contains(path)) {
      setState(() {
        _watchFolders.add(path);
      });
      await _saveWatchFolders();
      widget.onWatchFoldersChanged(_watchFolders);
    }
  }

  void _removeFolder(int index) async {
    setState(() {
      _watchFolders.removeAt(index);
    });
    await _saveWatchFolders();
    widget.onWatchFoldersChanged(_watchFolders);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TopBar(
              title: "Cài đặt & Thư mục",
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _addFolder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "Thêm thư mục",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            StatusConfigCard(
              isRunning: widget.isRunning,
              isConnecting: widget.isConnecting,
              statusMessage:
                  widget.statusMessage ??
                  (widget.isRunning ? "Tunnel Online" : "Tunnel Offline"),
              onToggleTunnel: widget.onToggleTunnel,
              tunnelUrl: widget.tunnelUrl,
            ),
            const SizedBox(height: 32),
            Expanded(
              child: _watchFolders.isEmpty
                  ? _buildEmptyState()
                  : _buildFolderList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_off_outlined,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            "Chưa có thư mục nào được chọn",
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Nhấn 'Thêm thư mục' để bắt đầu cài đặt",
            style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderList() {
    return ListView.separated(
      itemCount: _watchFolders.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final path = _watchFolders[index];
        final name = path.split('/').last;
        if (name.isEmpty && path.length > 1) {
          // handle trailing slash
          final parts = path.split('/').where((p) => p.isNotEmpty).toList();
          if (parts.isNotEmpty) {
            // name = parts.last;
          }
        }

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 8,
            ),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.folder_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: Text(
              name.isEmpty ? path : name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            subtitle: Text(
              path,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
            trailing: IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.redAccent,
              ),
              onPressed: () => _removeFolder(index),
              style: IconButton.styleFrom(
                backgroundColor: Colors.redAccent.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
