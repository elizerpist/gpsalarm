import 'package:flutter/material.dart';
import '../models/alarm_point.dart';

class RadiusPopup extends StatelessWidget {
  final double latitude;
  final double longitude;
  final AlarmPoint? existingPoint;

  const RadiusPopup({
    super.key,
    required this.latitude,
    required this.longitude,
    this.existingPoint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: const Center(child: Text('Alarm popup - TODO')),
    );
  }
}
