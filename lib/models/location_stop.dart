import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:route_force/enums/travel_mode.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LocationStop {
  final String id;
  final String name;
  final LatLng position;
  final int durationMinutes;
  TravelMode travelMode;
  final String? departureName;
  final LatLng? departurePosition;
  final DateTime? manualArrivalTime;
  final DateTime? manualDepartureTime;
  final int? aiSuggestedDurationMinutes;
  final List<String>? openingHoursWeekdayText;
  final String? notes; // Added notes field

  LocationStop({
    required this.id,
    required this.name,
    required this.position,
    required this.durationMinutes,
    this.travelMode = TravelMode.driving,
    this.departureName,
    this.departurePosition,
    this.manualArrivalTime,
    this.manualDepartureTime,
    this.aiSuggestedDurationMinutes,
    this.openingHoursWeekdayText,
    this.notes, // Added to constructor
  });

  String get effectiveDepartureName => departureName ?? name;
  LatLng get effectiveDeparturePosition => departurePosition ?? position;

  LocationStop copyWith({
    String? id,
    String? name,
    LatLng? position,
    int? durationMinutes,
    TravelMode? travelMode,
    String? departureName,
    bool clearDepartureName = false,
    LatLng? departurePosition,
    bool clearDeparturePosition = false,
    DateTime? manualArrivalTime,
    bool clearManualArrivalTime = false,
    DateTime? manualDepartureTime,
    bool clearManualDepartureTime = false,
    int? aiSuggestedDurationMinutes,
    bool clearAiSuggestedDuration = false,
    List<String>? openingHoursWeekdayText,
    bool clearOpeningHours = false,
    String? notes,
    bool clearNotes = false, // Added notes parameters to copyWith
  }) {
    return LocationStop(
      id: id ?? this.id,
      name: name ?? this.name,
      position: position ?? this.position,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      travelMode: travelMode ?? this.travelMode,
      departureName:
          clearDepartureName ? null : (departureName ?? this.departureName),
      departurePosition:
          clearDeparturePosition
              ? null
              : (departurePosition ?? this.departurePosition),
      manualArrivalTime:
          clearManualArrivalTime
              ? null
              : (manualArrivalTime ?? this.manualArrivalTime),
      manualDepartureTime:
          clearManualDepartureTime
              ? null
              : (manualDepartureTime ?? this.manualDepartureTime),
      aiSuggestedDurationMinutes:
          clearAiSuggestedDuration
              ? null
              : (aiSuggestedDurationMinutes ?? this.aiSuggestedDurationMinutes),
      openingHoursWeekdayText:
          clearOpeningHours
              ? null
              : (openingHoursWeekdayText ?? this.openingHoursWeekdayText),
      notes:
          clearNotes ? null : (notes ?? this.notes), // Handle notes in copyWith
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'position': {
        'latitude': position.latitude,
        'longitude': position.longitude,
      },
      'durationMinutes': durationMinutes,
      'travelMode': travelMode.toString().split('.').last,
      'departureName': departureName,
      'departurePosition':
          departurePosition != null
              ? {
                'latitude': departurePosition!.latitude,
                'longitude': departurePosition!.longitude,
              }
              : null,
      'manualArrivalTime':
          manualArrivalTime != null
              ? Timestamp.fromDate(manualArrivalTime!)
              : null,
      'manualDepartureTime':
          manualDepartureTime != null
              ? Timestamp.fromDate(manualDepartureTime!)
              : null,
      'aiSuggestedDurationMinutes': aiSuggestedDurationMinutes,
      'openingHoursWeekdayText': openingHoursWeekdayText,
      'notes': notes, // Added notes to toJson
    };
  }

  factory LocationStop.fromJson(Map<String, dynamic> json) {
    return LocationStop(
      id: json['id'] as String,
      name: json['name'] as String,
      position: LatLng(
        (json['position']['latitude'] as num).toDouble(),
        (json['position']['longitude'] as num).toDouble(),
      ),
      durationMinutes: json['durationMinutes'] as int,
      travelMode: TravelMode.values.firstWhere(
        (e) => e.toString().split('.').last == json['travelMode'],
        orElse: () => TravelMode.driving,
      ),
      departureName: json['departureName'] as String?,
      departurePosition:
          json['departurePosition'] != null
              ? LatLng(
                (json['departurePosition']['latitude'] as num).toDouble(),
                (json['departurePosition']['longitude'] as num).toDouble(),
              )
              : null,
      manualArrivalTime: (json['manualArrivalTime'] as Timestamp?)?.toDate(),
      manualDepartureTime:
          (json['manualDepartureTime'] as Timestamp?)?.toDate(),
      aiSuggestedDurationMinutes: json['aiSuggestedDurationMinutes'] as int?,
      openingHoursWeekdayText:
          (json['openingHoursWeekdayText'] as List<dynamic>?)?.cast<String>(),
      notes: json['notes'] as String?, // Added notes to fromJson
    );
  }
}
