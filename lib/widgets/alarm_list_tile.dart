import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/alarm_point.dart';

class AlarmListTile extends StatelessWidget {
  final AlarmPoint point;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  const AlarmListTile({
    super.key,
    required this.point,
    required this.onToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = point.isActive;
    final triggerInfo = point.triggerType == TriggerType.distance
        ? '${_formatDistance(point.radiusMeters)} · ${tr("distance")}'
        : '${point.timeTrigger?.inMinutes ?? 0} ${tr("minutes")} · ${tr("time")}';

    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: (isActive ? Colors.red : Colors.grey).withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.location_on,
          color: isActive ? Colors.red : Colors.grey[400],
          size: 22,
        ),
      ),
      title: Text(
        point.name ?? tr('no_name'),
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: isActive ? null : Colors.grey,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(triggerInfo,
              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          Text(
            '${point.latitude.toStringAsFixed(3)}° N, ${point.longitude.toStringAsFixed(3)}° E',
            style: TextStyle(fontSize: 10, color: Colors.grey[400]),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Switch(
            value: isActive,
            onChanged: (_) => onToggle(),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          Text(
            isActive ? tr('active') : tr('inactive'),
            style: TextStyle(
              fontSize: 9,
              color: isActive ? Colors.green : Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      isThreeLine: true,
    );
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)}km';
    }
    return '${meters.round()}m';
  }
}
