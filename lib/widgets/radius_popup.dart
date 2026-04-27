import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:uuid/uuid.dart';
import '../models/alarm_point.dart';
import '../providers/alarm_provider.dart';

class RadiusPopup extends StatefulWidget {
  final double latitude;
  final double longitude;
  final AlarmPoint? existingPoint;
  final ValueChanged<double>? onRadiusChanged;

  const RadiusPopup({
    super.key,
    required this.latitude,
    required this.longitude,
    this.existingPoint,
    this.onRadiusChanged,
  });

  @override
  State<RadiusPopup> createState() => _RadiusPopupState();
}

class _RadiusPopupState extends State<RadiusPopup> {
  late TextEditingController _nameController;
  late TriggerType _triggerType;
  late ZoneTrigger _zoneTrigger;
  late double _radiusMeters;
  late int _timeMinutes;

  @override
  void initState() {
    super.initState();
    final p = widget.existingPoint;
    _nameController = TextEditingController(text: p?.name ?? '');
    _triggerType = p?.triggerType ?? TriggerType.distance;
    _zoneTrigger = p?.zoneTrigger ?? ZoneTrigger.onEntry;
    _radiusMeters = p?.radiusMeters ?? 500;
    _timeMinutes = p?.timeTrigger?.inMinutes ?? 10;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1a1a2e) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: 16, right: 8, top: 4,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row: title + toggles
                  Row(children: [
                    const Icon(Icons.location_on, color: Colors.red, size: 24),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.existingPoint != null ? tr('edit_alarm') : tr('new_alarm_point'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${widget.latitude.toStringAsFixed(4)}°, ${widget.longitude.toStringAsFixed(4)}°',
                            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    ),
                    // Distance/Time toggle
                    _toggleIcon(
                      icon: _triggerType == TriggerType.distance ? Icons.straighten : Icons.timer,
                      tooltip: _triggerType == TriggerType.distance ? tr('distance') : tr('time'),
                      active: _triggerType == TriggerType.time,
                      onTap: () => setState(() {
                        _triggerType = _triggerType == TriggerType.distance
                            ? TriggerType.time : TriggerType.distance;
                      }),
                    ),
                    const SizedBox(width: 4),
                    // Entry/Leave toggle
                    _toggleIcon(
                      icon: _zoneTrigger == ZoneTrigger.onEntry ? Icons.login : Icons.logout,
                      tooltip: _zoneTrigger == ZoneTrigger.onEntry ? tr('on_entry') : tr('on_leave'),
                      active: _zoneTrigger == ZoneTrigger.onLeave,
                      onTap: () => setState(() {
                        _zoneTrigger = _zoneTrigger == ZoneTrigger.onEntry
                            ? ZoneTrigger.onLeave : ZoneTrigger.onEntry;
                      }),
                    ),
                    const SizedBox(width: 4),
                  ]),
                  const SizedBox(height: 12),
                  // Slider
                  if (_triggerType == TriggerType.distance) ...[
                    Slider(
                      value: _radiusMeters, min: 100, max: 5000, divisions: 49,
                      activeColor: Colors.red,
                      onChanged: (v) {
                        setState(() => _radiusMeters = v);
                        widget.onRadiusChanged?.call(v);
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('100m', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                          Text('${_radiusMeters.round()}m',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red[700])),
                          Text('5km', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                        ],
                      ),
                    ),
                  ] else ...[
                    Slider(
                      value: _timeMinutes.toDouble(), min: 5, max: 120, divisions: 23,
                      activeColor: Colors.orange,
                      onChanged: (v) => setState(() => _timeMinutes = v.round()),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('5 min', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                          Text('$_timeMinutes min',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange[700])),
                          Text('120 min', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Name field
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(labelText: tr('name_optional')),
                  ),
                  const SizedBox(height: 16),
                  // Delete button (edit mode only)
                  if (widget.existingPoint != null) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _delete(context),
                        icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                        label: Text(tr('delete'),
                            style: const TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Bottom buttons
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(tr('cancel')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _save(context),
                        child: Text(tr('save')),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleIcon({
    required IconData icon,
    required String tooltip,
    required bool active,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: active
                ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
                : (isDark ? Colors.grey[800] : Colors.grey[200]),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Icon(icon, size: 18,
            color: active
                ? Theme.of(context).colorScheme.primary
                : (isDark ? Colors.grey[400] : Colors.grey[600]),
          ),
        ),
      ),
    );
  }

  void _save(BuildContext context) {
    final alarmProv = context.read<AlarmProvider>();

    if (!alarmProv.canAddAlarm && widget.existingPoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('max_alarms_reached'))),
      );
      return;
    }

    final point = AlarmPoint(
      id: widget.existingPoint?.id ?? const Uuid().v4(),
      name: _nameController.text.isEmpty ? null : _nameController.text,
      latitude: widget.latitude,
      longitude: widget.longitude,
      radiusMeters: _triggerType == TriggerType.distance ? _radiusMeters : 0,
      triggerType: _triggerType,
      zoneTrigger: _zoneTrigger,
      timeTrigger: _triggerType == TriggerType.time
          ? Duration(minutes: _timeMinutes)
          : null,
    );

    if (widget.existingPoint != null) {
      alarmProv.updateAlarmPoint(point);
    } else {
      alarmProv.addAlarmPoint(point);
    }
    Navigator.pop(context);
  }

  void _delete(BuildContext context) {
    if (widget.existingPoint == null) return;
    final alarmProv = context.read<AlarmProvider>();
    alarmProv.removeAlarmPoint(widget.existingPoint!.id);
    Navigator.pop(context);
  }
}
