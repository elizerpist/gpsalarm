import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Tile provider that caches tiles to disk automatically.
/// Once downloaded, tiles are available offline.
/// Only used on native platforms (not web).
class CachedTileProvider extends TileProvider {
  static final _cacheManager = CacheManager(
    Config(
      'map_tile_cache',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 10000,
    ),
  );

  CachedTileProvider();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return _CachedTileImageProvider(url, _cacheManager);
  }

  static Future<void> clearCache() async {
    await _cacheManager.emptyCache();
  }
}

class _CachedTileImageProvider extends ImageProvider<_CachedTileImageProvider> {
  final String url;
  final CacheManager cacheManager;

  _CachedTileImageProvider(this.url, this.cacheManager);

  @override
  Future<_CachedTileImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
      _CachedTileImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _load(decode),
      scale: 1.0,
    );
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final file = await cacheManager.getSingleFile(url);
    final bytes = await file.readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is _CachedTileImageProvider && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
