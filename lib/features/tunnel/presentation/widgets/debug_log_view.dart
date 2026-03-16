import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DebugLogView extends StatelessWidget {
  final List<String> logs;
  final ScrollController scrollController;
  final VoidCallback onClearLogs;

  const DebugLogView({
    super.key,
    required this.logs,
    required this.scrollController,
    required this.onClearLogs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: logs.length,
              itemBuilder: (c, i) => Text(
                logs[i],
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          "LOGS",
          style: TextStyle(color: Colors.white, fontSize: 9),
        ),
        Row(
          children: [
            IconButton(
              onPressed: () {
                if (logs.isNotEmpty) {
                  Clipboard.setData(ClipboardData(text: logs.join('\n')));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Logs Copied!")),
                  );
                }
              },
              icon: const Icon(Icons.copy_all, size: 12, color: Colors.blue),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onClearLogs,
              icon: const Icon(Icons.delete, size: 12, color: Colors.orange),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ],
    );
  }
}
