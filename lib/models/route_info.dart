import 'package:google_maps_flutter/google_maps_flutter.dart';

class RouteInfo {
  final String distance;
  final String duration;
  // final String? encodedPolyline; // If CF returns encoded string
  final List<LatLng> polylinePoints;
  final List<dynamic> steps; // To store step-by-step instructions
  final String? summary; // Optional summary for the route (e.g., "via I-280 S")

  RouteInfo({
    required this.distance,
    required this.duration,
    required this.polylinePoints,
    // this.encodedPolyline,
    required this.steps,
    this.summary,
  });
}
