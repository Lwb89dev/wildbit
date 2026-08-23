import 'dart:ui';

/// Draw slices around a mobile scene actor.
enum ProjectedDepthSlice { all, behindPivot, inFrontOfPivot }

/// Classifies ground anchors after the map camera has projected and rotated
/// them. Screen Y, rather than latitude, keeps the ordering correct at every
/// map bearing.
abstract final class ProjectedDepthOrder {
  static bool belongsToSlice({
    required Offset objectFoot,
    required Offset pivotFoot,
    required ProjectedDepthSlice slice,
  }) {
    if (slice == ProjectedDepthSlice.all) return true;
    final isInFront = objectFoot.dy > pivotFoot.dy;
    return switch (slice) {
      ProjectedDepthSlice.all => true,
      ProjectedDepthSlice.behindPivot => !isInFront,
      ProjectedDepthSlice.inFrontOfPivot => isInFront,
    };
  }
}
