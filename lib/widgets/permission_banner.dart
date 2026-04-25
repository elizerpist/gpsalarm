import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/permission_service.dart';

class PermissionBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const PermissionBanner({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.orange.withOpacity(0.9),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => PermissionService.openAppSettings(),
            child: Text(tr('open_settings'),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
