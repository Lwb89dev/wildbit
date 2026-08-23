import 'package:latlong2/latlong.dart';

import '../enums/poi_type.dart';
import 'poi_metadata.dart';

class Poi {
  const Poi({
    required this.id,
    required this.name,
    required this.type,
    required this.position,
    this.metadata = const PoiMetadata(),
  });

  final String id;
  final String name;
  final PoiType type;
  final LatLng position;
  final PoiMetadata metadata;
}
