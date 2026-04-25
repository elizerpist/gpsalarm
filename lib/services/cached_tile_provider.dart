import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Tile provider that caches tiles to disk automatically.
/// Once downloaded, tiles are available offline.
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
    return CachedNetworkImageProvider(url);
  }

  /// Returns cache stats for display in settings
  static Future<int> getCacheSize() async {
    try {
      final info = await _cacheManager.getFileFromCache('_dummy_');
      // Can't easily get total size, return object count estimate
      return 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> clearCache() async {
    await _cacheManager.emptyCache();
  }
}

/// ImageProvider that loads from cache first, network second
class CachedNetworkImageProvider extends ImageProvider<CachedNetworkImageProvider> {
  final String url;

  CachedNetworkImageProvider(this.url);

  static final _cacheManager = CacheManager(
    Config(
      'map_tile_cache',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 10000,
    ),
  );

  @override
  Future<CachedNetworkImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
      CachedNetworkImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
    );
  }

  Future<Codec> _loadAsync(
      CachedNetworkImageProvider key, ImageDecoderCallback decode) async {
    final file = await _cacheManager.getSingleFile(url);
    final bytes = await file.readAsBytes();
    final buffer = await ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is CachedNetworkImageProvider && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
