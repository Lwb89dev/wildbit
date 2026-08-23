import 'package:latlong2/latlong.dart';

import '../enums/poi_type.dart';

class Poi {
  const Poi({
    required this.id,
    required this.name,
    required this.type,
    required this.position,
  });

  final String id;
  final String name;
  final PoiType type;
  final LatLng position;
}
