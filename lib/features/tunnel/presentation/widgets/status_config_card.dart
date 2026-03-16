import 'package:flutter/material.dart';

class StatusConfigCard extends StatelessWidget {
  final bool isRunning;
  final bool isConnecting;
  final String? statusMessage;
  final VoidCallback onToggleTunnel;
  final String? authToken;
  final Map<String, dynamic>? userData;
  final VoidCallback onLogout;
  final VoidCallback onLoginWeb;
  final String? tunnelUrl;

  const StatusConfigCard({
    super.key,
    required this.isRunning,
    required this.isConnecting,
    this.statusMessage,
    required this.onToggleTunnel,
    this.authToken,
    this.userData,
    required this.onLogout,
    required this.onLoginWeb,
    this.tunnelUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          _buildStatusRow(),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 10),
          _buildAuthRow(context),
          if (tunnelUrl != null) ...[
            const Divider(height: 30),
            _buildGatewaySection(),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "TUNNEL STATUS",
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 10,
                  color: isRunning
                      ? Colors.green
                      : (isConnecting ? Colors.orange : Colors.grey),
                ),
                const SizedBox(width: 6),
                Text(
                  isRunning
                      ? "ONLINE"
                      : (isConnecting ? (statusMessage ?? "CONNECTING...") : "OFFLINE"),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isRunning ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
        ElevatedButton(
          onPressed: isConnecting ? null : onToggleTunnel,
          style: ElevatedButton.styleFrom(
            backgroundColor: isRunning ? Colors.red : Colors.green,
            foregroundColor: Colors.white,
          ),
          child: Text(isRunning ? "STOP TUNNEL" : "START TUNNEL"),
        ),
      ],
    );
  }

  Widget _buildAuthRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "AUTHENTICATION",
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              authToken != null
                  ? "Logged in as: ${userData?['email'] ?? 'User'}"
                  : "Not authenticated",
              style: TextStyle(
                color: authToken != null ? Colors.green : Colors.grey,
              ),
            ),
          ],
        ),
        Row(
          children: [
            if (authToken != null)
              TextButton.icon(
                onPressed: onLogout,
                icon: const Icon(Icons.logout, size: 16, color: Colors.red),
                label: const Text("LOGOUT",
                    style: TextStyle(color: Colors.red, fontSize: 12)),
              ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: onLoginWeb,
              icon: const Icon(Icons.login),
              label: Text(authToken != null ? "RE-LOGIN" : "LOGIN WEB"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                side: const BorderSide(color: Colors.grey),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGatewaySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "GATEWAY DOMAIN:",
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          tunnelUrl!,
          style: const TextStyle(
            color: Colors.blue,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
