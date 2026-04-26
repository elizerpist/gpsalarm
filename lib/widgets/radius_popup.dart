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

  const RadiusPopup({
    super.key,
    required this.latitude,
    required this.longitude,
    this.existingPoint,
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
              left: 20, right: 20, top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('new_alarm_point'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.latitude.toStringAsFixed(4)}° N, ${widget.longitude.toStringAsFixed(4)}° E',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: tr('name_optional'),
              ),
            ),
            const SizedBox(height: 16),
            Text(tr('trigger_type'),
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 8),
            Row(
              children: [
                _TriggerChip(
                  label: tr('distance'),
                  icon: Icons.straighten,
                  selected: _triggerType == TriggerType.distance,
                  onTap: () =>
                      setState(() => _triggerType = TriggerType.distance),
                ),
                const SizedBox(width: 8),
                _TriggerChip(
                  label: tr('time'),
                  icon: Icons.timer,
                  selected: _triggerType == TriggerType.time,
                  onTap: () => setState(() => _triggerType = TriggerType.time),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Zone trigger: on entry / on leave
            Row(
              children: [
                _TriggerChip(
                  label: 'Belépéskor',
                  icon: Icons.login,
                  selected: _zoneTrigger == ZoneTrigger.onEntry,
                  onTap: () => setState(() => _zoneTrigger = ZoneTrigger.onEntry),
                ),
                const SizedBox(width: 8),
                _TriggerChip(
                  label: 'Kilépéskor',
                  icon: Icons.logout,
                  selected: _zoneTrigger == ZoneTrigger.onLeave,
                  onTap: () => setState(() => _zoneTrigger = ZoneTrigger.onLeave),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_triggerType == TriggerType.distance) ...[
              Text(tr('radius_meters'),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _radiusMeters,
                      min: 100,
                      max: 5000,
                      divisions: 49,
                      label: '${_radiusMeters.round()}m',
                      onChanged: (v) => setState(() => _radiusMeters = v),
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text('${_radiusMeters.round()}m',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ] else ...[
              Text(tr('minutes'),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _timeMinutes.toDouble(),
                      min: 5,
                      max: 120,
                      divisions: 23,
                      label: '$_timeMinutes min',
                      onChanged: (v) =>
                          setState(() => _timeMinutes = v.round()),
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text('$_timeMinutes min',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            // Delete button (only in edit mode)
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
            Row(
              children: [
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
              ],
            ),
          ],
        ),
      ),
    ),
    ],
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

class _TriggerChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TriggerChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[300]!,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
