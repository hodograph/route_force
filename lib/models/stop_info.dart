// Example structure for lib/models/stop_info.dart
// import 'package:google_maps_flutter/google_maps_flutter.dart'; // if you use LatLng

class StopInfo {
  final String id;
  final String name;
  final String address;
  // final LatLng location; // Example
  // Add other relevant fields like arrivalTime, departureTime, notes etc.

  StopInfo({
    required this.id,
    required this.name,
    required this.address,
    // required this.location,
  });

  // Factory constructor to create StopInfo from a map (e.g., from Firestore)
  factory StopInfo.fromMap(Map<String, dynamic> map) {
    return StopInfo(
      id: map['id'] as String,
      name: map['name'] as String? ?? 'Unnamed Stop',
      address: map['address'] as String? ?? '',
      // location: LatLng(map['latitude'] as double, map['longitude'] as double), // Example
    );
  }

  // Method to convert StopInfo instance to a map for Firestore
  Map<String, dynamic> toFirestoreMap() {
    return {
      'id': id,
      'name': name,
      'address': address,
      // 'latitude': location.latitude, // Example
      // 'longitude': location.longitude, // Example
    };
  }

  // It's good practice to implement copyWith if you need to make modified copies
  StopInfo copyWith({
    String? id,
    String? name,
    String? address,
    // LatLng? location,
  }) {
    return StopInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      // location: location ?? this.location,
    );
  }
}
