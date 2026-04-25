enum TriggerType { distance, time }
enum ZoneTrigger { onEntry, onLeave }
enum AlarmType { soundAndVibration, notificationOnly, fullScreenAlarm }

class AlarmPoint {
  final String id;
  final String? name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final Duration? timeTrigger;
  final TriggerType triggerType;
  final ZoneTrigger zoneTrigger;
  final bool isActive;
  final String? customAlarmSound;
  final AlarmType? customAlarmType;
  final DateTime createdAt;

  AlarmPoint({
    required this.id,
    this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    this.timeTrigger,
    required this.triggerType,
    this.zoneTrigger = ZoneTrigger.onEntry,
    this.isActive = true,
    this.customAlarmSound,
    this.customAlarmType,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
        'timeTriggerMinutes': timeTrigger?.inMinutes,
        'triggerType': triggerType.index,
        'zoneTrigger': zoneTrigger.index,
        'isActive': isActive,
        'customAlarmSound': customAlarmSound,
        'customAlarmType': customAlarmType?.index,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AlarmPoint.fromMap(Map<String, dynamic> map) => AlarmPoint(
        id: map['id'] as String,
        name: map['name'] as String?,
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        radiusMeters: (map['radiusMeters'] as num).toDouble(),
        timeTrigger: map['timeTriggerMinutes'] != null
            ? Duration(minutes: map['timeTriggerMinutes'] as int)
            : null,
        triggerType: TriggerType.values[map['triggerType'] as int],
        zoneTrigger: map['zoneTrigger'] != null
            ? ZoneTrigger.values[map['zoneTrigger'] as int]
            : ZoneTrigger.onEntry,
        isActive: map['isActive'] as bool,
        customAlarmSound: map['customAlarmSound'] as String?,
        customAlarmType: map['customAlarmType'] != null
            ? AlarmType.values[map['customAlarmType'] as int]
            : null,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );

  AlarmPoint copyWith({
    String? name,
    double? latitude,
    double? longitude,
    double? radiusMeters,
    Duration? timeTrigger,
    TriggerType? triggerType,
    ZoneTrigger? zoneTrigger,
    bool? isActive,
    String? customAlarmSound,
    AlarmType? customAlarmType,
  }) =>
      AlarmPoint(
        id: id,
        name: name ?? this.name,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        radiusMeters: radiusMeters ?? this.radiusMeters,
        timeTrigger: timeTrigger ?? this.timeTrigger,
        triggerType: triggerType ?? this.triggerType,
        zoneTrigger: zoneTrigger ?? this.zoneTrigger,
        isActive: isActive ?? this.isActive,
        customAlarmSound: customAlarmSound ?? this.customAlarmSound,
        customAlarmType: customAlarmType ?? this.customAlarmType,
        createdAt: createdAt,
      );
}
