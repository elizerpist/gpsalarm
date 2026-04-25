import 'package:flutter/material.dart';
import 'alarm_point.dart';

enum GpsPollingMode { continuous, custom }
enum MapStartView { currentGps, lastPosition, custom }
enum MapProvider { free, googleMaps, mapTiler }
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
  final MapProvider mapProvider;
  final MapTileStyle mapTileStyle;
  final String? googleMapsApiKey;
  final String? mapTilerApiKey;
  final String mapTilerStyle; // style name for MapTiler
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
    this.mapProvider = MapProvider.free,
    this.mapTileStyle = MapTileStyle.standard,
    this.googleMapsApiKey,
    this.mapTilerApiKey,
    this.mapTilerStyle = 'streets-v2',
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
        'mapProvider': mapProvider.index,
        'mapTileStyle': mapTileStyle.index,
        'googleMapsApiKey': googleMapsApiKey,
        'mapTilerApiKey': mapTilerApiKey,
        'mapTilerStyle': mapTilerStyle,
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
        mapProvider: map['mapProvider'] != null
            ? MapProvider.values[map['mapProvider'] as int]
            : MapProvider.free,
        mapTileStyle: map['mapTileStyle'] != null
            ? MapTileStyle.values[map['mapTileStyle'] as int]
            : MapTileStyle.standard,
        googleMapsApiKey: map['googleMapsApiKey'] as String?,
        mapTilerApiKey: map['mapTilerApiKey'] as String?,
        mapTilerStyle: map['mapTilerStyle'] as String? ?? 'streets-v2',
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
    MapProvider? mapProvider,
    MapTileStyle? mapTileStyle,
    String? googleMapsApiKey,
    String? mapTilerApiKey,
    String? mapTilerStyle,
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
        mapProvider: mapProvider ?? this.mapProvider,
        mapTileStyle: mapTileStyle ?? this.mapTileStyle,
        googleMapsApiKey: googleMapsApiKey ?? this.googleMapsApiKey,
        mapTilerApiKey: mapTilerApiKey ?? this.mapTilerApiKey,
        mapTilerStyle: mapTilerStyle ?? this.mapTilerStyle,
        themeMode: themeMode ?? this.themeMode,
        locale: locale ?? this.locale,
      );
}
