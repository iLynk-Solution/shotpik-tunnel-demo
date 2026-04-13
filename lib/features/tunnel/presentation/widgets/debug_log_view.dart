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
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListView.builder(
                controller: scrollController,
                itemCount: logs.length,
                itemBuilder: (c, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    logs[i].trim(),
                    style: const TextStyle(
                      color: Color(0xFF9CDCFE),
                      fontSize: 10,
                      fontFamily: 'monospace',
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF2D2D2D),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Row(
            children: [
              Icon(Icons.terminal_rounded, size: 14, color: Colors.grey),
              SizedBox(width: 8),
              Text(
                "BẢN TIN HỆ THỐNG",
                style: TextStyle(
                  color: Colors.grey, 
                  fontSize: 10, 
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          Row(
            children: [
              _HeaderAction(
                icon: Icons.content_copy_rounded,
                onPressed: () {
                  if (logs.isNotEmpty) {
                    Clipboard.setData(ClipboardData(text: logs.join('\n')));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Đã sao chép log vào bộ nhớ tạm")),
                    );
                  }
                },
              ),
              const SizedBox(width: 8),
              _HeaderAction(
                icon: Icons.delete_sweep_rounded,
                onPressed: onClearLogs,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _HeaderAction({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 16, color: Colors.grey.shade500),
      ),
    );
  }
}
