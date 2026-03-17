import 'package:flutter/material.dart';

class StatusConfigCard extends StatelessWidget {
  final bool isRunning;
  final bool isConnecting;
  final String? statusMessage;
  final VoidCallback onToggleTunnel;
  final String? tunnelUrl;
  final String? initialToken;
  final Function(String) onSaveToken;

  const StatusConfigCard({
    super.key,
    required this.isRunning,
    required this.isConnecting,
    this.statusMessage,
    required this.onToggleTunnel,
    this.tunnelUrl,
    this.initialToken,
    required this.onSaveToken,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isRunning
              ? [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)]
              : [Colors.grey.shade400, Colors.grey.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (isRunning ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatusIndicator(), 
              Row(
                children: [
                  _buildTokenButton(context),
                  const SizedBox(width: 8),
                  _buildToggleButton(context),
                ],
              ),
            ],
          ),
          if (statusMessage != null && !isRunning) ...[
            const SizedBox(height: 16),
            Text(
              statusMessage!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ],
          if (isRunning && statusMessage == 'Service Ready') ...[
            const SizedBox(height: 24),
            _buildGatewayInfo(),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "SERVICE STATUS",
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 10,
            letterSpacing: 1.2,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _PulseIndicator(isActive: isRunning),
            const SizedBox(width: 12),
            Text(
              isRunning
                  ? "TUNNEL ONLINE"
                  : (isConnecting ? "CONNECTING..." : "OFFLINE"),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildToggleButton(BuildContext context) {
    return ElevatedButton(
      onPressed: isConnecting ? null : onToggleTunnel,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: isRunning ? Theme.of(context).colorScheme.primary : Colors.green,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
      child: Text(
        isRunning ? "STOP SERVICE" : "START SERVICE",
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }

  Widget _buildTokenButton(BuildContext context) {
    String currentToken = initialToken ?? '';
    bool hasToken = currentToken.isNotEmpty;

    return IconButton(
      onPressed: () {
        final controller = TextEditingController(text: currentToken);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Cloudflare Tunnel Token", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            content: TextField(
              controller: controller,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: "Dán Token từ Cloudflare Dashboard vào đây...",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              style: const TextStyle(fontSize: 12),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Hủy")),
              ElevatedButton(
                onPressed: () {
                  onSaveToken(controller.text.trim());
                  Navigator.pop(context);
                },
                child: const Text("Lưu & Restart"),
              ),
            ],
          ),
        );
      },
      icon: Icon(
        hasToken ? Icons.vpn_key_rounded : Icons.vpn_key_outlined,
        color: hasToken ? Colors.white : Colors.white60,
        size: 20,
      ),
      tooltip: "Cấu hình Domain cố định",
    );
  }

  Widget _buildGatewayInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link, color: Colors.indigoAccent, size: 16),
              const SizedBox(width: 8),
              Text(
                "GATEWAY DOMAIN",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            tunnelUrl ?? "Cài đặt đường truyền...",
            style: TextStyle(
              color: tunnelUrl == null ? Colors.white70 : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              fontStyle: tunnelUrl == null ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseIndicator extends StatefulWidget {
  final bool isActive;
  const _PulseIndicator({required this.isActive});

  @override
  State<_PulseIndicator> createState() => _PulseIndicatorState();
}

class _PulseIndicatorState extends State<_PulseIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          color: Colors.white24,
          shape: BoxShape.circle,
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.greenAccent,
            boxShadow: [
              BoxShadow(
                color: Colors.greenAccent.withValues(
                  alpha: 0.5 * (1 - _controller.value),
                ),
                blurRadius: 10 * _controller.value,
                spreadRadius: 5 * _controller.value,
              ),
            ],
          ),
        );
      },
    );
  }
}
