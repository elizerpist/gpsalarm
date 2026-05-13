#!/usr/bin/env python3
import os
from pathlib import Path


def main() -> None:
    pub_cache = Path(os.environ.get("PUB_CACHE", Path.home() / ".pub-cache"))
    cache = pub_cache / "hosted" / "pub.dev"
    matches = sorted(
        cache.glob("maplibre-*/lib/src/platform/android/style_controller.dart")
    )
    if not matches:
        print("WARNING: maplibre Android style_controller.dart not found")
        return

    controller = matches[-1]
    text = controller.read_text()

    text = text.replace(
        "final jniOptions = jni.GeoJsonOptions();",
        "final jniOptions = jni.GeoJsonOptions().withTolerance(0.0);",
    )

    method = """\
  Future<void> setCircleLayerRadius({
    required String layerId,
    required double radius,
  }) async =>
      using((arena) {
        final jLayer = _jniStyle.getLayer(layerId.toJString());
        if (jLayer == null) return;
        jLayer.releasedBy(arena);
        final radiusBox = JFloat(radius)..releasedBy(arena);
        final radiusValue = jni.PropertyFactory.circleRadius(radiusBox);
        if (radiusValue == null) return;
        radiusValue.releasedBy(arena);
        final props = JArray(
          jni.PropertyValue.nullableType(JObject.nullableType),
          1,
        )..releasedBy(arena);
        final radiusObject = radiusValue.as(
          jni.PropertyValue.type(JObject.type),
        )..releasedBy(arena);
        props[0] = radiusObject;
        jLayer.setProperties(props);
      });

"""

    marker = "  @override\n  Future<void> updateGeoJsonSource({"
    if "Future<void> setCircleLayerRadius(" not in text:
        if marker not in text:
            raise RuntimeError("Could not find updateGeoJsonSource insertion point")
        text = text.replace(marker, method + marker)

    controller.write_text(text)
    print(f"Patched: {controller}")


if __name__ == "__main__":
    main()
