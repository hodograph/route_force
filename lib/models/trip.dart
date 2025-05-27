// lib/models/trip.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:route_force/models/location_stop.dart'; // Changed from StopInfo

class Trip {
  final String id;
  final String name; // Corresponds to 'tripName' in Firestore
  final DateTime date; // Corresponds to 'tripStartTime' in Firestore
  final String? description;
  final List<LocationStop> stops; // Changed from StopInfo
  final Map<String, int> selectedRouteIndices;
  final String? userId;
  final DateTime? createdAt;
  final List<String> participantUserIds; // New field for multiple users
  final DateTime? endTime; // New field for trip end time

  Trip({
    required this.id,
    required this.name,
    required this.date,
    this.description,
    required this.stops,
    required this.selectedRouteIndices,
    this.userId,
    this.createdAt,
    this.participantUserIds = const [], // Default to an empty list
    this.endTime,
  });

  // Factory constructor to create a Trip from a Firestore document
  factory Trip.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data();
    if (data == null) {
      // Or handle this more gracefully, e.g., by returning a default Trip or throwing a specific error.
      throw StateError("Missing data for Trip ${snapshot.id}");
    }

    // Parse tripStartTime (maps to Trip.date)
    DateTime parsedTripDate;
    final tripStartTimeData = data['tripStartTime']; // Changed from 'date'

    if (tripStartTimeData is Timestamp) {
      parsedTripDate = tripStartTimeData.toDate();
    } else {
      if (kDebugMode) {
        print(
          "Warning: 'tripStartTime' field for trip ${snapshot.id} is not a Timestamp or is missing. Value: $tripStartTimeData. Using current time as fallback.",
        );
      }
      parsedTripDate =
          DateTime.now(); // Or throw an error: throw FormatException("Invalid date format for trip ${snapshot.id}");
    }

    // Parse createdAt
    DateTime? parsedCreatedAt;
    final createdAtData = data['createdAt'];
    if (createdAtData is Timestamp) {
      parsedCreatedAt = createdAtData.toDate();
    } else if (createdAtData != null) {
      if (kDebugMode) {
        print(
          "Warning: 'createdAt' field for trip ${snapshot.id} is not a Timestamp. Value: $createdAtData. Ignoring.",
        );
      }
    }

    // Parse stops
    List<LocationStop> parsedStops = []; // Changed from StopInfo
    final stopsData = data['stops'];
    if (stopsData is List) {
      parsedStops =
          stopsData
              .map((stopData) {
                if (stopData is Map<String, dynamic>) {
                  return LocationStop.fromJson(
                    stopData, // Use LocationStop.fromJson
                  );
                }
                if (kDebugMode) {
                  print(
                    "Warning: Invalid stop data in 'stops' for trip ${snapshot.id}. Item: $stopData",
                  );
                }
                return null;
              })
              .whereType<LocationStop>() // Changed from StopInfo
              .toList();
    } else if (stopsData != null) {
      if (kDebugMode) {
        print(
          "Warning: 'stops' field for trip ${snapshot.id} is not a List. Value: $stopsData. Using empty list.",
        );
      }
    }

    // Parse selectedRouteIndices
    Map<String, int> parsedSelectedRouteIndices = {};
    final selectedRouteIndicesData = data['selectedRouteIndices'];
    if (selectedRouteIndicesData is Map) {
      selectedRouteIndicesData.forEach((key, value) {
        if (key is String && value is int) {
          parsedSelectedRouteIndices[key] = value;
        } else if (key is String && value is num) {
          // Allow num and cast to int
          parsedSelectedRouteIndices[key] = value.toInt();
        } else {
          if (kDebugMode) {
            print(
              "Warning: Invalid entry in 'selectedRouteIndices' for trip ${snapshot.id}. Key: $key, Value: $value. Skipping.",
            );
          }
        }
      });
    } else if (selectedRouteIndicesData != null) {
      if (kDebugMode) {
        print(
          "Warning: 'selectedRouteIndices' field for trip ${snapshot.id} is not a Map. Value: $selectedRouteIndicesData. Using empty map.",
        );
      }
    }

    // Parse participantUserIds
    List<String> parsedParticipantUserIds = [];
    final participantUserIdsData = data['participantUserIds'];
    if (participantUserIdsData is List) {
      parsedParticipantUserIds = participantUserIdsData.cast<String>().toList();
    } else if (participantUserIdsData != null) {
      if (kDebugMode) {
        print(
          "Warning: 'participantUserIds' field for trip ${snapshot.id} is not a List. Value: $participantUserIdsData. Using empty list.",
        );
      }
    }

    // Parse endTime
    DateTime? parsedEndTime;
    final endTimeData = data['endTime'];
    if (endTimeData is Timestamp) {
      parsedEndTime = endTimeData.toDate();
    }

    return Trip(
      id: snapshot.id,
      name:
          data['tripName'] as String? ?? 'Unnamed Trip', // Changed from 'name'
      date: parsedTripDate,
      description: data['description'] as String?,
      stops: parsedStops,
      selectedRouteIndices: parsedSelectedRouteIndices,
      userId: data['userId'] as String?,
      createdAt: parsedCreatedAt,
      participantUserIds: parsedParticipantUserIds,
      endTime: parsedEndTime,
    );
  }

  // Method to convert a Trip instance to a Map for Firestore
  Map<String, dynamic> toFirestore() {
    final Map<String, dynamic> data = {
      'tripName': name, // Changed from 'name'
      'tripStartTime': Timestamp.fromDate(date), // Changed from 'date'
      'stops':
          stops // Use LocationStop's toJson method
              .map((stop) => stop.toJson())
              .toList(),
      'selectedRouteIndices': selectedRouteIndices,
      'participantUserIds': participantUserIds, // Add to Firestore map
      'endTime':
          endTime != null
              ? Timestamp.fromDate(endTime!)
              : null, // Add endTime to Firestore map
    };

    if (description != null && description!.isNotEmpty) {
      data['description'] = description;
    }
    if (userId != null) {
      data['userId'] = userId;
    }
    if (createdAt != null) {
      data['createdAt'] = Timestamp.fromDate(createdAt!);
    }
    // Note: 'id' is the document ID and not part of the data map itself.
    return data;
  }
}
