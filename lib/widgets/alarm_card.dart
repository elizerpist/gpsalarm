import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:uuid/uuid.dart';
import '../models/alarm_point.dart';

/// Unified alarm assign/edit card used by both raster and vector maps.
/// - No modal backdrop (Positioned widget, not showModalBottomSheet)
/// - Swipe down = cancel
/// - Tappable name pill (expands to text field on tap)
/// - Coordinate display + toggles + active switch + slider
/// - Radius syncs with external swipe via [radius] prop
class AlarmCard extends StatefulWidget {
  final double latitude;
  final double longitude;
  final AlarmPoint? existingPoint;
  final double radius;
  final ValueChanged<double> onRadiusChanged;
  final ValueChanged<ZoneTrigger> onZoneTriggerChanged;
  final ValueChanged<TriggerType> onTriggerTypeChanged;
  final ValueChanged<int> onTimeChanged;
  final void Function(AlarmPoint alarm) onSave;
  final VoidCallback onCancel;
  final VoidCallback? onDelete;

  const AlarmCard({
    super.key,
    required this.latitude,
    required this.longitude,
    this.existingPoint,
    required this.radius,
    required this.onRadiusChanged,
    required this.onZoneTriggerChanged,
    required this.onTriggerTypeChanged,
    required this.onTimeChanged,
    required this.onSave,
    required this.onCancel,
    this.onDelete,
  });

  @override
  State<AlarmCard> createState() => _AlarmCardState();
}

class _AlarmCardState extends State<AlarmCard> {
  late double _radius;
  late TriggerType _triggerType;
  late ZoneTrigger _zoneTrigger;
  late int _timeMinutes;
  late bool _isActive;
  bool _isEditingName = false;
  late TextEditingController _nameController;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    final p = widget.existingPoint;
    _radius = p?.radiusMeters ?? widget.radius;
    _triggerType = p?.triggerType ?? TriggerType.distance;
    _zoneTrigger = p?.zoneTrigger ?? ZoneTrigger.onEntry;
    _timeMinutes = p?.timeTrigger?.inMinutes ?? 10;
    _isActive = p?.isActive ?? true;
    _nameController = TextEditingController(text: p?.name ?? '');
  }

  @override
  void didUpdateWidget(AlarmCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync radius from external swipe drag
    if (widget.radius != oldWidget.radius) {
      _radius = widget.radius;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String get _displayName {
    if (_nameController.text.isNotEmpty) return _nameController.text;
    return widget.existingPoint?.name ?? tr('new_alarm_point');
  }

  double get _dismissFraction => _dragOffset > 0 ? (_dragOffset / 200).clamp(0.0, 1.0) : 0.0;

  void _snapOrDismiss() {
    if (_dragOffset > 80) {
      widget.onCancel();
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final slideDown = _dismissFraction * 300;
    final isEdit = widget.existingPoint != null;

    return Transform.translate(
      offset: Offset(0, slideDown - keyboardHeight),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) => setState(() => _dragOffset += d.delta.dy),
        onVerticalDragEnd: (_) => _snapOrDismiss(),
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1a1a2e) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, -4))],
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
                // Header: name pill + coordinates + toggles
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
                  child: Row(children: [
                    const Icon(Icons.location_on, color: Colors.red, size: 24),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _isEditingName
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextField(
                                  controller: _nameController,
                                  autofocus: true,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                    isDense: true,
                                  ),
                                  onSubmitted: (_) => setState(() => _isEditingName = false),
                                  onTapOutside: (_) => setState(() => _isEditingName = false),
                                ),
                                Text(
                                  '${widget.latitude.toStringAsFixed(4)}°, ${widget.longitude.toStringAsFixed(4)}°',
                                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                                ),
                              ],
                            )
                          : GestureDetector(
                              onTap: () => setState(() => _isEditingName = true),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _displayName,
                                    style: TextStyle(
                                      fontSize: 15, fontWeight: FontWeight.bold,
                                      color: _nameController.text.isEmpty && widget.existingPoint?.name == null
                                          ? Colors.grey[500] : null,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${widget.latitude.toStringAsFixed(4)}°, ${widget.longitude.toStringAsFixed(4)}°',
                                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    // Delete icon (edit mode only) — separate group
                    if (isEdit) ...[
                      GestureDetector(
                        onTap: widget.onDelete,
                        child: Icon(Icons.delete_outline, size: 22, color: Colors.red[400]),
                      ),
                      const SizedBox(width: 12),
                    ],
                    // Trigger toggles — grouped; time+exit is invalid combo
                    _toggleIcon(
                      icon: _triggerType == TriggerType.distance ? Icons.straighten : Icons.timer,
                      tooltip: _triggerType == TriggerType.distance ? tr('distance') : tr('time'),
                      active: _triggerType == TriggerType.time,
                      disabled: _zoneTrigger == ZoneTrigger.onLeave,
                      onTap: () {
                        final next = _triggerType == TriggerType.distance
                            ? TriggerType.time : TriggerType.distance;
                        setState(() => _triggerType = next);
                        widget.onTriggerTypeChanged(next);
                      },
                    ),
                    const SizedBox(width: 4),
                    _toggleIcon(
                      icon: _zoneTrigger == ZoneTrigger.onEntry ? Icons.login : Icons.logout,
                      tooltip: _zoneTrigger == ZoneTrigger.onEntry ? tr('on_entry') : tr('on_leave'),
                      active: _zoneTrigger == ZoneTrigger.onLeave,
                      disabled: _triggerType == TriggerType.time,
                      onTap: () {
                        final next = _zoneTrigger == ZoneTrigger.onEntry
                            ? ZoneTrigger.onLeave : ZoneTrigger.onEntry;
                        setState(() => _zoneTrigger = next);
                        widget.onZoneTriggerChanged(next);
                      },
                    ),
                    const SizedBox(width: 12),
                    // Active toggle with bell icon
                    GestureDetector(
                      onTap: () => setState(() => _isActive = !_isActive),
                      child: Icon(
                        _isActive ? Icons.notifications_active : Icons.notifications_off,
                        size: 22,
                        color: _isActive
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[400],
                      ),
                    ),
                  ]),
                ),
                // Slider
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _triggerType == TriggerType.distance
                      ? Slider(
                          value: _radius.clamp(100, 5000),
                          min: 100, max: 5000, divisions: 49,
                          activeColor: Colors.red,
                          onChanged: (v) {
                            setState(() => _radius = v);
                            widget.onRadiusChanged(v);
                          },
                        )
                      : Slider(
                          value: _timeMinutes.toDouble().clamp(5, 120),
                          min: 5, max: 120, divisions: 23,
                          activeColor: Colors.orange,
                          onChanged: (v) {
                            setState(() => _timeMinutes = v.round());
                            widget.onTimeChanged(v.round());
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: _triggerType == TriggerType.distance
                        ? [
                            Text('100m', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                            Text('${_radius.round()}m',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red[700])),
                            Text('5km', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                          ]
                        : [
                            Text('5 min', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                            Text('$_timeMinutes min',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange[700])),
                            Text('120 min', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                          ],
                  ),
                ),
                const SizedBox(height: 8),
                // Bottom buttons
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + bottomPad),
                  child: Row(children: [
                    Expanded(child: OutlinedButton(
                      onPressed: widget.onCancel,
                      child: Text(tr('cancel')),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: FilledButton(
                      onPressed: _save,
                      child: Text(tr('save')),
                    )),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _toggleIcon({
    required IconData icon,
    required String tooltip,
    required bool active,
    bool disabled = false,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Opacity(
          opacity: disabled ? 0.3 : 1.0,
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: active && !disabled
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
                  : (isDark ? Colors.grey[800] : Colors.grey[200]),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active && !disabled ? Theme.of(context).colorScheme.primary : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Icon(icon, size: 18,
              color: active && !disabled
                  ? Theme.of(context).colorScheme.primary
                  : (isDark ? Colors.grey[400] : Colors.grey[600]),
          ),
        ),
        ),
      ),
    );
  }

  void _save() {
    final name = _nameController.text.isEmpty ? null : _nameController.text;
    widget.onSave(AlarmPoint(
      id: widget.existingPoint?.id ?? const Uuid().v4(),
      name: name,
      latitude: widget.latitude,
      longitude: widget.longitude,
      radiusMeters: _triggerType == TriggerType.distance ? _radius : 0,
      triggerType: _triggerType,
      zoneTrigger: _zoneTrigger,
      isActive: _isActive,
      timeTrigger: _triggerType == TriggerType.time
          ? Duration(minutes: _timeMinutes)
          : null,
    ));
  }
}
