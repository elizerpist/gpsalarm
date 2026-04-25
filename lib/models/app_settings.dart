import 'package:flutter/material.dart';
import 'alarm_point.dart';

enum GpsPollingMode { continuous, custom }
enum MapStartView { currentGps, lastPosition, custom }
enum MapTileStyle { standard, humanitarian, topo, positron, voyager, darkMatter }

class AppSettings {
  final AlarmType defaultAlarmType;
  final String defaultAlarmSound;
  final bool vibrationEnabled;
  final double volume;
  final GpsPollingMode gpsPollingMode;
  final Duration customPollingInterval;
  final MapStartView mapStartView;
  final double? customStartLat;
  final double? customStartLng;
  final MapTileStyle mapTileStyle;
  final ThemeMode themeMode;
  final String locale;

  AppSettings({
    this.defaultAlarmType = AlarmType.soundAndVibration,
    this.defaultAlarmSound = 'classic_bell',
    this.vibrationEnabled = true,
    this.volume = 0.7,
    this.gpsPollingMode = GpsPollingMode.continuous,
    this.customPollingInterval = const Duration(seconds: 10),
    this.mapStartView = MapStartView.currentGps,
    this.customStartLat,
    this.customStartLng,
    this.mapTileStyle = MapTileStyle.standard,
    this.themeMode = ThemeMode.system,
    this.locale = 'hu',
  });

  Map<String, dynamic> toMap() => {
        'defaultAlarmType': defaultAlarmType.index,
        'defaultAlarmSound': defaultAlarmSound,
        'vibrationEnabled': vibrationEnabled,
        'volume': volume,
        'gpsPollingMode': gpsPollingMode.index,
        'customPollingIntervalSeconds': customPollingInterval.inSeconds,
        'mapStartView': mapStartView.index,
        'customStartLat': customStartLat,
        'customStartLng': customStartLng,
        'mapTileStyle': mapTileStyle.index,
        'themeMode': themeMode.index,
        'locale': locale,
      };

  factory AppSettings.fromMap(Map<String, dynamic> map) => AppSettings(
        defaultAlarmType: AlarmType.values[map['defaultAlarmType'] as int],
        defaultAlarmSound: map['defaultAlarmSound'] as String,
        vibrationEnabled: map['vibrationEnabled'] as bool,
        volume: (map['volume'] as num).toDouble(),
        gpsPollingMode: GpsPollingMode.values[map['gpsPollingMode'] as int],
        customPollingInterval:
            Duration(seconds: map['customPollingIntervalSeconds'] as int),
        mapStartView: MapStartView.values[map['mapStartView'] as int],
        customStartLat: (map['customStartLat'] as num?)?.toDouble(),
        customStartLng: (map['customStartLng'] as num?)?.toDouble(),
        mapTileStyle: map['mapTileStyle'] != null
            ? MapTileStyle.values[map['mapTileStyle'] as int]
            : MapTileStyle.standard,
        themeMode: ThemeMode.values[map['themeMode'] as int],
        locale: map['locale'] as String,
      );

  AppSettings copyWith({
    AlarmType? defaultAlarmType,
    String? defaultAlarmSound,
    bool? vibrationEnabled,
    double? volume,
    GpsPollingMode? gpsPollingMode,
    Duration? customPollingInterval,
    MapStartView? mapStartView,
    double? customStartLat,
    double? customStartLng,
    MapTileStyle? mapTileStyle,
    ThemeMode? themeMode,
    String? locale,
  }) =>
      AppSettings(
        defaultAlarmType: defaultAlarmType ?? this.defaultAlarmType,
        defaultAlarmSound: defaultAlarmSound ?? this.defaultAlarmSound,
        vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
        volume: volume ?? this.volume,
        gpsPollingMode: gpsPollingMode ?? this.gpsPollingMode,
        customPollingInterval:
            customPollingInterval ?? this.customPollingInterval,
        mapStartView: mapStartView ?? this.mapStartView,
        customStartLat: customStartLat ?? this.customStartLat,
        customStartLng: customStartLng ?? this.customStartLng,
        mapTileStyle: mapTileStyle ?? this.mapTileStyle,
        themeMode: themeMode ?? this.themeMode,
        locale: locale ?? this.locale,
      );
}
