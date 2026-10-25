import 'dart:ui';

import 'package:flutter_map/flutter_map.dart' show MapCamera;
import 'package:latlong2/latlong.dart' show LatLng;

/// Screen space in which geometry projected for one camera stays valid while
/// the camera only pans.
///
/// At a fixed zoom, rotation and viewport size FlutterMap maps every
/// coordinate through the same rotation and scale, so moving the centre
/// translates all projected points by one shared offset. Layers project into
/// a frame once and paint later cameras with a single canvas translation
/// instead of reprojecting every vertex on each pan frame. Culling and LOD
/// selection still run against the live camera, so the painted result is
/// identical to a fresh projection.
class PanProjectionFrame {
  PanProjectionFrame(MapCamera camera)
    : zoom = camera.zoom,
      rotation = camera.rotation,
      viewportSize = camera.nonRotatedSize,
      _anchor = camera.center,
      _anchorScreen = camera.latLngToScreenOffset(camera.center);

  final double zoom;
  final double rotation;
  final Size viewportSize;
  final LatLng _anchor;
  final Offset _anchorScreen;

  /// True when [camera] differs from this frame by a translation only.
  bool accepts(MapCamera camera) =>
      camera.zoom == zoom &&
      camera.rotation == rotation &&
      camera.nonRotatedSize == viewportSize;

  /// Translation from frame coordinates to [camera]'s screen coordinates.
  Offset offsetFor(MapCamera camera) =>
      camera.latLngToScreenOffset(_anchor) - _anchorScreen;

  /// Projects [point] into frame coordinates for a camera whose translation
  /// from this frame is [offset].
  static Offset project(MapCamera camera, Offset offset, LatLng point) =>
      camera.latLngToScreenOffset(point) - offset;

  /// The canvas viewport expressed in frame coordinates.
  static Rect viewportIn(Size size, Offset offset) =>
      Rect.fromLTWH(-offset.dx, -offset.dy, size.width, size.height);
}
