import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/alarm_provider.dart';
import '../widgets/alarm_list_tile.dart';
import '../widgets/radius_popup.dart';

class AlarmListScreen extends StatelessWidget {
  const AlarmListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final alarmProv = context.watch<AlarmProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('saved_locations')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                tr('active_alarms',
                    args: [alarmProv.activeCount.toString()]),
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary),
              ),
            ),
          ),
        ],
      ),
      body: alarmProv.alarmPoints.isEmpty
          ? Center(
              child: Text(
                tr('no_results'),
                style: TextStyle(color: Colors.grey[500]),
              ),
            )
          : ListView.separated(
              itemCount: alarmProv.alarmPoints.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, index) {
                final point = alarmProv.alarmPoints[index];
                return Dismissible(
                  key: Key(point.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: Colors.red,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) => alarmProv.removeAlarmPoint(point.id),
                  child: AlarmListTile(
                    point: point,
                    onDelete: () => alarmProv.removeAlarmPoint(point.id),
                    onToggle: () => alarmProv.toggleActive(point.id),
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => RadiusPopup(
                          latitude: point.latitude,
                          longitude: point.longitude,
                          existingPoint: point,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
