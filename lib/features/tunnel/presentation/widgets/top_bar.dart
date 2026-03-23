import 'package:flutter/material.dart';

class TopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? child;

  const TopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              subtitle ?? "Welcome back,",
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            Text(
              title,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
                height: 1.2,
              ),
            ),
          ],
        ),
        const Spacer(),
        // ignore: use_null_aware_elements
        if (child != null) child!,
      ],
    );
  }
}
