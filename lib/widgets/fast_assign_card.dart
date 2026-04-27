import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/alarm_point.dart';
import '../services/debug_console.dart';

/// Shared fast assign card for both raster and vector maps.
/// Continuous drag: up = expand, down = collapse → dismiss.
/// Bottom buttons always visible. Toggle icons in header.
class FastAssignCard extends StatefulWidget {
  final double initialRadius;
  final ValueChanged<double> onRadiusChanged;
  final ValueChanged<ZoneTrigger> onZoneTriggerChanged;
  final ValueChanged<TriggerType> onTriggerTypeChanged;
  final ValueChanged<int> onTimeChanged;
  final void Function(String? name, TriggerType triggerType, ZoneTrigger zoneTrigger, int timeMinutes) onSave;
  final VoidCallback onCancel;

  const FastAssignCard({
    super.key,
    required this.initialRadius,
    required this.onRadiusChanged,
    required this.onZoneTriggerChanged,
    required this.onTriggerTypeChanged,
    required this.onTimeChanged,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<FastAssignCard> createState() => _FastAssignCardState();
}

class _FastAssignCardState extends State<FastAssignCard> {
  late double _radius;
  double _dragOffset = 0;
  static const double _collapsedHeight = 180;
  static const double _expandedExtra = 80;
  final _nameController = TextEditingController();
  TriggerType _triggerType = TriggerType.distance;
  ZoneTrigger _zoneTrigger = ZoneTrigger.onEntry;
  int _timeMinutes = 10;

  @override
  void initState() {
    super.initState();
    _radius = widget.initialRadius;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  double get _expandFraction => (_dragOffset.abs() / _expandedExtra).clamp(0.0, 1.0);
  bool get _isExpanded => _expandFraction > 0.3;
  // How far the whole card should slide down when dismissing (0..1)
  double get _dismissFraction => _dragOffset > 0 ? (_dragOffset / 200).clamp(0.0, 1.0) : 0.0;

  void _snapToPosition() {
    if (_dragOffset > 60) {
      // Dismiss
      widget.onCancel();
      return;
    }
    setState(() {
      if (_dragOffset < -_expandedExtra * 0.3) {
        _dragOffset = -_expandedExtra;
      } else {
        _dragOffset = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final cardHeight = _collapsedHeight + (_expandFraction * _expandedExtra);
    // When dragging down, slide the entire card off-screen
    final slideDown = _dismissFraction * 300;

    return Transform.translate(
      offset: Offset(0, slideDown),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) => setState(() => _dragOffset += d.delta.dy),
        onVerticalDragEnd: (_) => _snapToPosition(),
        child: Material(
          color: Colors.transparent,
          child: Container(
            height: cardHeight + bottomPad + 16,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1a1a2e) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, -4))],
            ),
            child: Column(children: [
              // Drag handle
              GestureDetector(
                onTap: () => setState(() {
                  _dragOffset = _isExpanded ? 0 : -_expandedExtra;
                }),
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              // Content area
              Expanded(
                child: ClipRect(
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      // Header with toggle buttons
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
                        child: Row(children: [
                          const Icon(Icons.location_on, color: Colors.red, size: 24),
                          const SizedBox(width: 6),
                          Text(
                            _triggerType == TriggerType.distance
                                ? '${_radius.round()}m'
                                : '$_timeMinutes min',
                            style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold,
                              color: _triggerType == TriggerType.distance ? Colors.red[700] : Colors.orange[700],
                            ),
                          ),
                          const Spacer(),
                          _toggleIcon(
                            icon: _triggerType == TriggerType.distance ? Icons.straighten : Icons.timer,
                            tooltip: _triggerType == TriggerType.distance ? tr('distance') : tr('time'),
                            active: _triggerType == TriggerType.time,
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
                            onTap: () {
                              final next = _zoneTrigger == ZoneTrigger.onEntry
                                  ? ZoneTrigger.onLeave : ZoneTrigger.onEntry;
                              setState(() => _zoneTrigger = next);
                              widget.onZoneTriggerChanged(next);
                            },
                          ),
                          IconButton(
                            icon: Icon(_isExpanded ? Icons.expand_more : Icons.expand_less, size: 22),
                            onPressed: () => setState(() {
                              _dragOffset = _isExpanded ? 0 : -_expandedExtra;
                            }),
                            visualDensity: VisualDensity.compact,
                          ),
                        ]),
                      ),
                      // Slider
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: _triggerType == TriggerType.distance
                            ? Slider(
                                value: _radius, min: 100, max: 5000, divisions: 49,
                                activeColor: Colors.red,
                                onChanged: (v) {
                                  setState(() => _radius = v);
                                  widget.onRadiusChanged(v);
                                },
                              )
                            : Slider(
                                value: _timeMinutes.toDouble(), min: 5, max: 120, divisions: 23,
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
                                  Text('5km', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                                ]
                              : [
                                  Text('5 min', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                                  Text('120 min', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                                ],
                        ),
                      ),
                      // Expanded content
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: TextField(
                          controller: _nameController,
                          decoration: InputDecoration(labelText: tr('name_optional')),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ]),
                  ),
                ),
              ),
              // Bottom buttons — always visible
              Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottomPad),
                child: Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: widget.onCancel,
                    child: Text(tr('cancel')),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton(
                    onPressed: () {
                      final name = _nameController.text.isEmpty ? null : _nameController.text;
                      widget.onSave(name, _triggerType, _zoneTrigger, _timeMinutes);
                    },
                    child: Text(tr('save')),
                  )),
                ]),
              ),
            ]),
          ),
        ),
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
              color: active ? Theme.of(context).colorScheme.primary : Colors.transparent,
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
}
