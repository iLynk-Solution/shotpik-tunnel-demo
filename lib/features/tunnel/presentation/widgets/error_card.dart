import 'package:flutter/material.dart';

class ErrorCard extends StatelessWidget {
  final String error;

  const ErrorCard({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: Colors.red.shade700,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              error,
              style: TextStyle(
                color: Colors.red.shade700,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
