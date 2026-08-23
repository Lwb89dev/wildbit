import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/entities/geo_fix.dart';
import '../../location/location_service.dart';
import 'bit_animation_controller.dart';
import 'bit_cursor.dart';

/// Places [BitCursor] at the user's GPS position on the map, smoothly
/// interpolating between fixes (which arrive every second or so) instead of
/// snapping — this is what makes Bit feel grounded in the world rather than
/// an image pasted on top of it.
class BitMapLayer extends StatefulWidget {
  const BitMapLayer({
    super.key,
    required this.locationService,
    required this.controller,
    this.onPositionUpdate,
    this.renderedPosition,
    this.pixelSize = 72,
  });

  final LocationService locationService;
  final BitAnimationController controller;
  final ValueChanged<GeoFix>? onPositionUpdate;

  /// Publishes the interpolated ground anchor actually used for painting.
  final ValueNotifier<LatLng?>? renderedPosition;
  final double pixelSize;

  @override
  State<BitMapLayer> createState() => BitMapLayerState();
}

class BitMapLayerState extends State<BitMapLayer>
    with SingleTickerProviderStateMixin {
  static const _distance = Distance();
  static const _interpolationWindow = Duration(milliseconds: 900);
  static const _depthPublishInterval = Duration(milliseconds: 80);
  static const _movingSpeedThreshold = 0.8; // m/s, rejects GPS jitter

  late final Ticker _ticker;
  StreamSubscription<GeoFix>? _subscription;

  LatLng? _previous;
  LatLng? _target;
  LatLng? _rendered;
  DateTime _targetSetAt = DateTime.now();
  DateTime _lastDepthPublishedAt = DateTime.fromMillisecondsSinceEpoch(0);

  LatLng? get currentPosition => _rendered;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _subscription = widget.locationService.positionStream.listen(_onFix);
    widget.locationService.getCurrentPosition().then((point) {
      if (point != null) _onFix(point);
    });
  }

  void _onFix(GeoFix point) {
    final movedMeters = _rendered == null
        ? 0.0
        : _distance.as(LengthUnit.Meter, _rendered!, point.position);
    // GNSS can report a small non-zero speed while stationary. Require actual
    // displacement as well, otherwise Bit keeps walking while the hiker rests.
    final isMoving =
        movedMeters > 2.5 &&
        (point.speedMetersPerSecond ?? 0) > _movingSpeedThreshold;
    widget.controller.reportMovement(
      isMoving: isMoving,
      headingDegrees: point.headingDegrees,
    );

    _previous = _rendered ?? point.position;
    _target = point.position;
    _targetSetAt = DateTime.now();
    widget.onPositionUpdate?.call(point);
  }

  void _onTick(Duration elapsed) {
    final target = _target;
    if (target == null) return;

    final elapsedSinceFix = DateTime.now()
        .difference(_targetSetAt)
        .inMilliseconds;
    final t = (elapsedSinceFix / _interpolationWindow.inMilliseconds).clamp(
      0.0,
      1.0,
    );
    final prev = _previous ?? target;
    final next = LatLng(
      prev.latitude + (target.latitude - prev.latitude) * t,
      prev.longitude + (target.longitude - prev.longitude) * t,
    );
    if (_rendered == next) return;
    setState(() => _rendered = next);
    final now = DateTime.now();
    final publishDepth =
        t >= 1 ||
        now.difference(_lastDepthPublishedAt) >= _depthPublishInterval;
    if (publishDepth && widget.renderedPosition?.value != next) {
      _lastDepthPublishedAt = now;
      widget.renderedPosition?.value = next;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rendered = _rendered;
    if (rendered == null) return const SizedBox.shrink();

    final camera = MapCamera.of(context);
    final pixelSize = (42 * math.pow(2, camera.zoom - 16))
        .clamp(22.0, 72.0)
        .toDouble();
    final offset = camera.latLngToScreenOffset(rendered);
    final boxHeight = pixelSize * 1.5;

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Stack(
            children: [
              Positioned(
                left: offset.dx - pixelSize / 2,
                top: offset.dy - boxHeight,
                child: BitCursor(
                  controller: widget.controller,
                  pixelSize: pixelSize,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
