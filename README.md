# GPS Alarm

GPS-based proximity alarm app built with Flutter.

The app lets you place alarm points on a map and trigger alerts when you enter or leave a configured radius, or when a time-based ETA radius is reached. Android is the primary native target; raster maps are available everywhere, and native MapLibre vector mode is available on mobile.

## Development

```sh
flutter pub get
flutter test
flutter analyze
```

Android release signing uses `android/key.properties` when present. Copy `android/key.properties.example`, point it at a real release keystore, and keep the real file out of git. If no release key is configured, release APKs fall back to the debug signing key so GitHub workflow artifacts remain installable for testing. Keystore files and signing properties are intentionally ignored.
