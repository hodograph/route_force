import 'package:google_maps_flutter/google_maps_flutter.dart';

class RouteInfo {
  final int distanceInMeters; // Changed from String distance
  final String duration;
  // final String? encodedPolyline; // If CF returns encoded string
  final List<LatLng> polylinePoints;
  final List<dynamic> steps; // To store step-by-step instructions
  final String? summary; // Optional summary for the route (e.g., "via I-280 S")

  RouteInfo({
    required this.distanceInMeters,
    required this.duration,
    required this.polylinePoints,
    // this.encodedPolyline,
    required this.steps,
    this.summary,
  });

  factory RouteInfo.fromJson(
    Map<String, dynamic> json,
    List<LatLng> decodedPolylinePoints,
  ) {
    return RouteInfo(
      distanceInMeters: (json['distanceInMeters'] as num?)?.toInt() ?? 0,
      duration: json['duration'] as String? ?? 'N/A',
      polylinePoints: decodedPolylinePoints,
      steps: (json['steps'] as List<dynamic>?) ?? [],
      summary: json['summary'] as String?,
    );
  }
}
