import 'package:flutter/material.dart';

class TunnelSidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onIndexChanged;
  final String? userName;
  final String? userEmail;
  final String? userAvatar;
  final VoidCallback onLogout;

  const TunnelSidebar({
    super.key,
    required this.selectedIndex,
    required this.onIndexChanged,
    this.userName,
    this.userEmail,
    this.userAvatar,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(32.0),
            child: Row(
              children: [
                Image.asset('assets/shotpik-agent.png', width: 40, height: 40),
                const SizedBox(width: 16),
                Text(
                  "Shotpik",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          _buildNavSection(context, "MENU"),
          _buildNavItem(
            context,
            Icons.dashboard_rounded,
            "Dashboard",
            selectedIndex == 0,
            onTap: () => onIndexChanged(0),
          ),
          _buildNavItem(
            context,
            Icons.security_rounded,
            "Whitelist",
            selectedIndex == 1,
            onTap: () => onIndexChanged(1),
          ),
          _buildNavItem(
            context,
            Icons.settings_outlined,
            "Settings",
            selectedIndex == 2,
            onTap: () => onIndexChanged(2),
          ),
          const Spacer(),
          _buildUserCard(context),
        ],
      ),
    );
  }

  Widget _buildNavSection(BuildContext context, String title) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _buildNavItem(
    BuildContext context,
    IconData icon,
    String label,
    bool active, {
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Icon(
          icon,
          size: 20,
          color: active
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
            color: active
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selected: active,
        selectedTileColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        onTap: onTap,
      ),
    );
  }

  Widget _buildUserCard(BuildContext context) {
    final email = userEmail ?? "agent@shotpik.com";
    final name = userName ?? "Agent User";

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            backgroundImage: userAvatar != null ? NetworkImage(userAvatar!) : null,
            child: userAvatar == null
                ? Icon(
                    Icons.person_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Text(
                  email,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.logout_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            onPressed: onLogout,
          ),
        ],
      ),
    );
  }
}
