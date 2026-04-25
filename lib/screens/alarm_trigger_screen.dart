import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/alarm_point.dart';

class AlarmTriggerScreen extends StatelessWidget {
  final AlarmPoint alarmPoint;
  final double distanceMeters;
  final VoidCallback onDismiss;

  const AlarmTriggerScreen({
    super.key,
    required this.alarmPoint,
    required this.distanceMeters,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.alarm, color: Colors.red, size: 80),
                const SizedBox(height: 24),
                Text(
                  alarmPoint.name ?? tr('no_name'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  '${distanceMeters.round()}m',
                  style: TextStyle(color: Colors.grey[400], fontSize: 18),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onDismiss,
                    icon: const Icon(Icons.close),
                    label: Text(tr('dismiss'),
                        style: const TextStyle(fontSize: 18)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
