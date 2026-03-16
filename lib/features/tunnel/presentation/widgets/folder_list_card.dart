import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FolderListCard extends StatelessWidget {
  final bool isRunning;
  final Map<String, String> sharedFolders;
  final String? tunnelUrl;
  final String apiToken;
  final VoidCallback onAddFolder;
  final Function(String) onRemoveFolder;

  const FolderListCard({
    super.key,
    required this.isRunning,
    required this.sharedFolders,
    this.tunnelUrl,
    required this.apiToken,
    required this.onAddFolder,
    required this.onRemoveFolder,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            if (!isRunning)
              const Expanded(
                child: Center(
                  child: Text(
                    "Connect tunnel first to share folders",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ),
            if (isRunning)
              Expanded(
                child: sharedFolders.isEmpty
                    ? const Center(
                        child: Text(
                          "No folders shared yet",
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      )
                    : ListView(
                        children: sharedFolders.entries.map((e) {
                          final folderUrl = "$tunnelUrl/${Uri.encodeComponent(e.key)}/?token=$apiToken";
                          return _buildFolderCard(context, e.key, folderUrl);
                        }).toList(),
                      ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          "SHARED FOLDERS",
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.indigo,
          ),
        ),
        IconButton(
          onPressed: isRunning ? onAddFolder : null,
          icon: const Icon(Icons.add_circle, color: Colors.blue),
          tooltip: "Add Folder",
        ),
      ],
    );
  }

  Widget _buildFolderCard(BuildContext context, String name, String url) {
    return Card(
      elevation: 0,
      color: Colors.grey.shade50,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder, size: 18, color: Colors.blueGrey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                IconButton(
                  onPressed: () => onRemoveFolder(name),
                  icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      url,
                      style: const TextStyle(fontSize: 11, color: Colors.blue),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: url));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Link Copied!")),
                      );
                    },
                    child: const Icon(Icons.copy, size: 14, color: Colors.blue),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
