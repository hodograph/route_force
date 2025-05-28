import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Added for input formatters
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:intl/intl.dart';
import 'package:route_force/enums/stop_action.dart';
import 'package:uuid/uuid.dart';
import 'dart:ui' as ui;
import 'dart:math'; // Added for pi, sin, cos

import 'package:firebase_ai/firebase_ai.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:route_force/widgets/departure_search_dialog.dart';
import 'package:route_force/widgets/directions_list.dart';
import 'package:route_force/map_styles/map_style_definitions.dart'
    as map_styles;
import 'package:route_force/models/location_stop.dart';
import 'package:route_force/models/route_info.dart';
import 'package:route_force/models/scheduled_stop_info.dart';
import 'package:route_force/widgets/trip_sheet.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:route_force/utils/map_display_helpers.dart';
import 'package:route_force/models/trip.dart'; // Import the Trip model

import 'package:route_force/enums/travel_mode.dart' as travel_mode;

class TripPlannerApp extends StatefulWidget {
  final Trip? trip; // Optional Trip object for editing

  const TripPlannerApp({super.key, this.trip});

  @override
  State<TripPlannerApp> createState() => _TripPlannerAppState();
}

class _TripPlannerAppState extends State<TripPlannerApp> {
  // State variable for the name of the currently selected style
  String _selectedMapStyleName =
      map_styles.styleStandardName; // Default to Standard

  // Constants for stop duration input
  static const int _minStopDuration = 0; // 0 minutes
  static const int _maxStopDuration = 24 * 60; // 1440 minutes (24 hours)
  static const int _durationStep = 5; // 5 minutes for +/- buttons

  GoogleMapController? _mapController;
  List<LocationStop> stops = [];
  DateTime tripStartTime = DateTime.now();
  Map<String, List<RouteInfo>> routes = {}; // routeId to list of route options
  Map<String, int> selectedRouteIndices =
      {}; // routeId to selected index in the list
  bool isLoading = false;

  // Default to San Francisco if location permission is denied
  static const LatLng _defaultLocation = LatLng(37.7749, -122.4194);
  LatLng _currentPosition = _defaultLocation;

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _placePredictions = [];
  // String? _editingDepartureForStopId; // No longer needed
  String? _pickingDepartureOnMapForStopId; // For picking departure on map
  bool _isPickingNewStopOnMap = false; // For picking a new stop on map

  Map<String, ExpansionTileController> _tileControllers = {};
  String? _expandedStopId; // To track the currently expanded stop
  // API Key will be handled by Firebase Functions
  final uuid = Uuid();
  String _sessionToken = '';
  String _departureSessionToken = '';

  // Cache for generated marker icons
  final Map<String, BitmapDescriptor> _markerIconCache = {};

  // Firebase AI
  GenerativeModel? _generativeModel;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // State for route label markers
  Set<Marker> _routeLabelMarkers = {};

  // --- State for Saved Trips ---
  List<Map<String, dynamic>> _savedTrips =
      []; // Each map will contain 'id' and 'data'

  // --- State for Participants ---
  List<String> _participantUserIds = [];
  List<Map<String, String>> _participantUserDetails =
      []; // e.g., {'id': 'uid', 'email': 'user@example.com', 'displayName': 'Name'}
  bool _isLoadingParticipants = false;

  bool _isLoadingSavedTrips = false;

  String? _editingTripId; // To store the ID of the trip being edited
  String _initialTripName = ''; // To pre-fill trip name when saving/editing
  String? _tripOwnerId; // To store the UID of the trip's owner

  // Helper method to generate a descriptive summary for a transit route option
  String _getTransitRouteSummary(RouteInfo routeInfo, int routeNumber) {
    // Priority 1: Use existing summary if it seems descriptive for transit
    if (routeInfo.summary != null && routeInfo.summary!.isNotEmpty) {
      final lowerSummary = routeInfo.summary!.toLowerCase();
      // Check for common transit keywords or line number patterns
      if (lowerSummary.contains("bus") ||
          lowerSummary.contains("train") ||
          lowerSummary.contains("subway") ||
          lowerSummary.contains("metro") ||
          lowerSummary.contains("tram") ||
          lowerSummary.contains("line") ||
          RegExp(r'\b[a-zA-Z]?\d+[a-zA-Z]?\b').hasMatch(routeInfo.summary!)) {
        return routeInfo.summary!;
      }
    }

    // Priority 2: Construct from the first significant transit step
    for (var step in routeInfo.steps) {
      if (step is Map<String, dynamic> && step['travel_mode'] == 'TRANSIT') {
        final transitDetails = step['transit_details'] as Map<String, dynamic>?;
        if (transitDetails != null) {
          final lineDetails = transitDetails['line'] as Map<String, dynamic>?;
          final vehicleDetails =
              lineDetails?['vehicle'] as Map<String, dynamic>?;
          final headsign = transitDetails['headsign'] as String?;

          String primaryRouteName = "";
          String? lineShortName = lineDetails?['short_name'] as String?;
          String? lineLongName = lineDetails?['name'] as String?;

          if (lineShortName != null && lineShortName.isNotEmpty) {
            primaryRouteName = lineShortName;
          } else if (lineLongName != null && lineLongName.isNotEmpty) {
            primaryRouteName = lineLongName;
          }

          // Prepare formatted vehicle type
          String vehicleTypeRaw = vehicleDetails?['type']?.toString() ?? "";
          String formattedVehicleType = "";
          if (vehicleTypeRaw.isNotEmpty &&
              vehicleTypeRaw.toUpperCase() != "TRANSIT") {
            formattedVehicleType = vehicleTypeRaw
                .split('_')
                .map((e) {
                  if (e.isEmpty) return '';
                  return e[0] + e.substring(1).toLowerCase();
                })
                .join(' ');
          }

          // If primaryRouteName is purely numeric, prepend formatted vehicle type for context.
          if (primaryRouteName.isNotEmpty &&
              RegExp(r'^\d+$').hasMatch(primaryRouteName) &&
              formattedVehicleType.isNotEmpty) {
            primaryRouteName = "$formattedVehicleType $primaryRouteName";
          } else if (primaryRouteName.isEmpty) {
            // No line name, fall back to vehicle name or formatted type
            primaryRouteName = vehicleDetails?['name'] ?? formattedVehicleType;
            if (primaryRouteName.isEmpty) {
              primaryRouteName = "Transit"; // Absolute fallback for name part
            }
          }

          String finalSummary = primaryRouteName;

          if (headsign != null && headsign.isNotEmpty) {
            // Avoid appending "to [headsign]" if headsign seems already included
            if (!finalSummary.toLowerCase().contains(headsign.toLowerCase())) {
              finalSummary += " to $headsign";
            }
          }

          // If the constructed summary is empty, very generic, or too long, use a fallback.
          if (finalSummary.isEmpty ||
              (finalSummary.toLowerCase() == "transit" &&
                  !(lineShortName == null && lineLongName == null)) ||
              finalSummary.length > 70) {
            // If too long, try a shorter version: just the original line name + headsign
            if (finalSummary.length > 70 &&
                (lineShortName != null || lineLongName != null)) {
              String shorterName = (lineShortName ?? lineLongName!);
              if (headsign != null &&
                  headsign.isNotEmpty &&
                  !shorterName.toLowerCase().contains(headsign.toLowerCase())) {
                shorterName += " to $headsign";
              }
              if (shorterName.length <= 70 &&
                  shorterName.isNotEmpty &&
                  shorterName.toLowerCase() != "transit") {
                return shorterName;
              }
            }
            return "Transit Option $routeNumber";
          }
          return finalSummary;
        }
      }
    }

    // Fallback
    return "Route $routeNumber";
  }

  // Helper method to get a short label for transit routes on the map
  String _getShortTransitLabel(RouteInfo routeInfo, int routeNumber) {
    for (var step in routeInfo.steps) {
      if (step is Map<String, dynamic> && step['travel_mode'] == 'TRANSIT') {
        final transitDetails = step['transit_details'] as Map<String, dynamic>?;
        if (transitDetails != null) {
          final line = transitDetails['line'] as Map<String, dynamic>?;
          if (line != null) {
            final shortName = line['short_name'] as String?;
            if (shortName != null &&
                shortName.isNotEmpty &&
                shortName.length <= 4) {
              // Allow slightly longer short names
              return shortName;
            }
            // If short_name is not suitable, try vehicle name if it's very short (e.g. "Bus")
            final vehicle = line['vehicle'] as Map<String, dynamic>?;
            final vehicleName = vehicle?['name'] as String?;
            if (vehicleName != null &&
                vehicleName.isNotEmpty &&
                vehicleName.length <= 3) {
              return vehicleName;
            }
            // As a last resort for a specific transit leg, use a generic "T" + number
            return "T$routeNumber";
          }
        }
      }
    }
    // Fallback to just the number if no transit info found or suitable
    return routeNumber.toString();
  }

  @override
  void initState() {
    super.initState();
    // Debug print
    if (kDebugMode) {
      print("Initializing Trip Planner App");
    }
    _tileControllers = {}; // Initialize the map
    _sessionToken = uuid.v4();
    _searchController.addListener(_onSearchChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Make async
      if (!mounted) return; // Good practice to check mounted in the callback

      // Load user preferences first, so _selectedMapStyleName is up-to-date
      // before the map potentially initializes or other location-dependent logic runs.
      await _loadUserPreferences();

      _getCurrentLocation();

      // Initialize Firebase AI (if still needed on client, or move to where it's used)
      if (widget.trip != null) {
        _loadTripDataFromWidget(widget.trip!);
        // _tripOwnerId is set within _loadTripDataFromWidget
      } else {
        // For a new trip, ensure participant list is clear.
        // Optionally, automatically add the current user.
        _participantUserIds.clear();
        _participantUserDetails.clear();
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null &&
            !currentUser.isAnonymous && // Ensure not anonymous for ownership
            !_participantUserIds.contains(currentUser.uid)) {
          // _participantUserIds.add(currentUser.uid); // Decide if owner is implicitly a participant or needs to be added
          // _fetchParticipantDetails(); // Then fetch details
        }
      }
      _fetchSavedTrips(); // Keep this
      _initializeFirebaseAI();
    });
    _tripOwnerId =
        widget.trip?.userId ?? FirebaseAuth.instance.currentUser?.uid;
  }

  Future<void> _initializeFirebaseAI() async {
    try {
      _generativeModel = FirebaseAI.googleAI().generativeModel(
        model: 'gemini-2.0-flash', // Corrected model name
      );
      if (kDebugMode) {
        print("Firebase AI Model initialized successfully.");
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error initializing Firebase AI: $e");
      }
      // Optionally, inform the user that AI suggestions might not be available.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Debug print map status
    if (kDebugMode) {
      print("Map dependencies changed");
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tileControllers.clear();
    super.dispose();
  }

  Future<void> _loadUserPreferences() async {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null && !currentUser.isAnonymous) {
      try {
        final userDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(currentUser.uid)
                .get();
        if (userDoc.exists && userDoc.data() != null) {
          final data = userDoc.data()!;
          if (data.containsKey('lastMapStyle')) {
            final String? savedStyle = data['lastMapStyle'] as String?;
            if (savedStyle != null &&
                map_styles.availableMapStyles.containsKey(savedStyle)) {
              if (mounted) {
                setState(() {
                  _selectedMapStyleName = savedStyle;
                  if (kDebugMode) {
                    print(
                      "Loaded map style from preferences: $_selectedMapStyleName",
                    );
                  }
                });
                // If map is already created, apply style. Otherwise, onMapCreated will handle it.
                if (_mapController != null) {
                  await _applySelectedStyleToMap();
                }
              }
            } else if (savedStyle != null) {
              if (kDebugMode) {
                print(
                  "Saved map style '$savedStyle' is no longer available. Using default.",
                );
              }
              // Optionally, update Firestore to remove/reset the invalid style if desired
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print("Error loading user map style preference: $e");
        }
        // Keep default style, optionally inform user via SnackBar
      }
    }
  }

  LatLngBounds _calculateBounds(List<LatLng> points) {
    if (points.isEmpty) {
      // Fallback to a default bounds, though this case should be handled
      // by checking if stops list is empty before calling.
      return LatLngBounds(
        southwest: _defaultLocation,
        northeast: _defaultLocation,
      );
    }
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (LatLng point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  Future<void> _loadTripDataFromWidget(Trip trip) async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      _editingTripId = trip.id;
      _tripOwnerId = trip.userId; // Set the owner ID from the loaded trip
      _initialTripName = trip.name;
      tripStartTime = trip.date; // Assuming Trip.date is the start time

      stops = trip.stops.map((s) => s.copyWith()).toList(); // Deep copy
      _tileControllers.clear();
      for (var stop in stops) {
        _tileControllers[stop.id] = ExpansionTileController();
      }
      selectedRouteIndices = Map<String, int>.from(trip.selectedRouteIndices);
      _participantUserIds = List<String>.from(
        trip.participantUserIds,
      ); // Load participant IDs
    });

    try {
      await _fetchParticipantDetails(); // Fetch details for loaded IDs
      await _triggerRouteAndMarkerUpdates(); // This will update markers and routes

      // Focus map on loaded stops
      if (_mapController != null && stops.isNotEmpty) {
        final Set<LatLng> uniquePointsSet = {};
        for (final stop in stops) {
          uniquePointsSet.add(stop.position); // Arrival position
          if (stop.departurePosition != null &&
              stop.departurePosition != stop.position) {
            uniquePointsSet.add(
              stop.departurePosition!,
            ); // Distinct departure position
          }
        }
        final List<LatLng> uniquePoints = uniquePointsSet.toList();

        if (uniquePoints.isNotEmpty) {
          final LatLngBounds bounds = _calculateBounds(uniquePoints);
          _mapController!.animateCamera(
            CameraUpdate.newLatLngBounds(bounds, 75.0), // 75.0 padding
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error during _loadTripDataFromWidget's async part: $e");
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initializing trip data: ${e.toString()}'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _onSearchChanged() async {
    if (!mounted) return;
    if (_searchController.text.isNotEmpty) {
      final predictions = await _fetchPlacePredictionsApi(
        _searchController.text,
        _sessionToken,
      );
      if (mounted) {
        // Check mounted again before setState after await
        setState(() => _placePredictions = predictions);
      }
    } else {
      if (mounted) {
        setState(() => _placePredictions = []);
      }
    }
  }

  void _resetSessionToken() {
    if (mounted) {
      setState(() {
        _sessionToken = uuid.v4();
      });
    }
  }

  void _resetDepartureSessionToken() {
    if (mounted) {
      // Added mounted check
      setState(() {
        _departureSessionToken = uuid.v4();
      });
    }
  }

  Future<int?> _fetchAISuggestedDuration(String stopName) async {
    if (_generativeModel == null) {
      if (kDebugMode) {
        print("Firebase AI model not initialized. Cannot fetch suggestion.");
      }
      await _initializeFirebaseAI(); // Attempt to re-initialize
      if (_generativeModel == null) return null; // Still not initialized
    }

    final prompt =
        'What is a typical or average amount of time people spend at a place like "$stopName"? Please answer with just the number of minutes (e.g., "30" for 30 minutes, or "90" for 1.5 hours). If you cannot determine a typical time, please respond with "N/A".';

    try {
      final response = await _generativeModel!.generateContent([
        Content.text(prompt),
      ]);
      if (kDebugMode) {
        print("AI Raw Response for '$stopName': ${response.text}");
      }

      if (response.text != null) {
        final textResponse = response.text!.trim();
        if (textResponse.toLowerCase() == "n/a") {
          return null;
        }
        // Try to parse the number, removing " minutes" or other text if present
        final int? duration = int.tryParse(
          textResponse.replaceAll(RegExp(r'[^0-9]'), ''),
        );
        if (duration != null && duration >= 0) {
          if (kDebugMode) {
            print("AI Suggested Duration for '$stopName': $duration minutes");
          }
          return duration;
        }
      }
      return null; // If not an int or negative
    } catch (e) {
      if (kDebugMode) {
        print("Error fetching AI suggested duration for '$stopName': $e");
      }
      // Log more detailed error if needed, e.g., e.toString()
    }
    return null;
  }

  Future<List<dynamic>> _fetchPlacePredictionsApi(
    String input,
    String sessionToken,
  ) async {
    if (input.isEmpty) return [];

    // --- Debugging: Check auth state ---
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (kDebugMode) {
        print(
          'Error: User is not authenticated when calling getPlacePredictions.',
        );
      }
      // Optionally, show a message to the user or handle re-authentication
      // For example, by showing a SnackBar:
      // ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Authentication error. Please log in again.')));
      return [];
    }
    if (kDebugMode) {
      print(
        'User ${currentUser.uid} (${currentUser.email}) is authenticated. Calling getPlacePredictions...',
      );
    }
    // --- End Debugging ---
    try {
      final HttpsCallable callable = _functions.httpsCallable(
        'getPlacePredictions',
      );
      final HttpsCallableResult result = await callable.call<List<dynamic>>({
        'input': input,
        'sessionToken': sessionToken,
      });
      // The Firebase Function should return a List<Map<String, dynamic>>
      // where each map is like {'description': ..., 'place_id': ...}
      if (result.data != null) {
        // Ensure the data is correctly typed.
        // The function returns List<dynamic>, where dynamic is Map<String, dynamic>
        if (result.data is List) {
          return (result.data as List).map((item) {
            if (item is Map) {
              return item;
            }
            return {}; // Should not happen if function is correct
          }).toList();
        } else {
          if (kDebugMode) {
            print(
              'Places Autocomplete API error for input "$input": No suggestions found or unexpected format.',
            );
          }
          return [];
        }
      }
      return [];
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching place predictions: $e');
      }
      return [];
    }
  }

  Future<void> _getPlaceDetails(
    String placeId, {
    String? stopIdToUpdateDeparture,
  }) async {
    // The new Place Details API (GET) can use a session token.
    String sessionTokenForRequest = _sessionToken;
    if (stopIdToUpdateDeparture != null) {
      sessionTokenForRequest = _departureSessionToken;
    }

    try {
      final HttpsCallable callable = _functions.httpsCallable(
        'getPlaceDetails',
      );
      final HttpsCallableResult resultCallable = await callable
          .call<Map<String, dynamic>>({
            'placeId': placeId,
            'sessionToken': sessionTokenForRequest,
            // 'fields' is hardcoded in the cloud function for now
          });

      if (resultCallable.data != null) {
        final result =
            resultCallable.data!; // This is already a Map<String, dynamic>

        // Check if 'error' field exists in the response from the new API
        if (result['error'] != null) {
          if (kDebugMode) {
            print(
              'Place Details API v1 error for placeId "$placeId": ${result['error']['message']} (Code: ${result['error']['code']})',
            );
          }
          // Reset session token and return
          if (stopIdToUpdateDeparture != null) {
            _resetDepartureSessionToken();
          } else {
            _resetSessionToken();
          }
          return;
        }
        final locationData =
            result['location']; // { "latitude": ..., "longitude": ... }
        final name = result['displayName']?['text'] ?? 'Unknown Name';
        final openingHoursData = result['regularOpeningHours'] as Map?;
        final List<String>? weekdayText =
            openingHoursData?['weekdayDescriptions']?.cast<String>();

        if (kDebugMode) {
          print("Place Details for $name: $result");
          print("Opening Hours for $name: $weekdayText");
        }

        if (locationData == null ||
            locationData['latitude'] == null ||
            locationData['longitude'] == null) {
          if (kDebugMode) {
            print(
              'Place Details API v1 error for placeId "$placeId": Location data is missing or malformed.',
            );
          }
          // Reset session token and return
          if (stopIdToUpdateDeparture != null) {
            _resetDepartureSessionToken();
          } else {
            _resetSessionToken();
          }
          return;
        }

        if (stopIdToUpdateDeparture != null) {
          _setDepartureForStop(
            stopIdToUpdateDeparture,
            LatLng(locationData['latitude'], locationData['longitude']),
            name,
          );
        } else {
          _addStop(
            LatLng(locationData['latitude'], locationData['longitude']),
            name,
            openingHoursWeekdayText: weekdayText,
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching place details for $placeId: $e');
      }
    }

    if (stopIdToUpdateDeparture != null) {
      _resetDepartureSessionToken();
    } else {
      _resetSessionToken();
    }
  }

  Future<List<RouteInfo>?> _getDirections(
    LatLng origin,
    LatLng destination,
    travel_mode.TravelMode mode, {
    DateTime? departureTime, // Added optional parameter
  }) async {
    String travelModeStr;
    switch (mode) {
      case travel_mode.TravelMode.driving:
        travelModeStr = 'DRIVE'; // Matches CF
        break;
      case travel_mode.TravelMode.walking:
        travelModeStr = 'WALK'; // Matches CF
        break;
      case travel_mode.TravelMode.bicycling:
        travelModeStr = 'BICYCLE'; // Matches CF
        break;
      case travel_mode.TravelMode.transit:
        travelModeStr = 'TRANSIT'; // Matches CF
        break;
    }

    final Map<String, dynamic> params = {
      'origin': {'latitude': origin.latitude, 'longitude': origin.longitude},
      'destination': {
        'latitude': destination.latitude,
        'longitude': destination.longitude,
      },
      'travelMode': travelModeStr,
    };

    if (departureTime != null) {
      params['departureTime'] = departureTime.toUtc().toIso8601String();
    }

    try {
      if (kDebugMode) {
        print("Current user: ${FirebaseAuth.instance.currentUser?.uid}");
      }
      final HttpsCallable callable = _functions.httpsCallable('getDirections');
      final HttpsCallableResult result = await callable.call<List<dynamic>>(
        params,
      );

      if (result.data != null && result.data is List) {
        final List<dynamic> routesData = result.data as List<dynamic>;
        if (routesData.isNotEmpty) {
          List<RouteInfo> routeOptions = [];
          for (var routeMap in routesData) {
            if (routeMap is! Map) continue;

            final String? encodedPolyline =
                routeMap['encodedPolyline'] as String?;
            List<LatLng> polylineCoordinates = [];
            if (encodedPolyline != null) {
              PolylinePoints polylinePoints = PolylinePoints();
              polylineCoordinates =
                  polylinePoints
                      .decodePolyline(encodedPolyline)
                      .map((p) => LatLng(p.latitude, p.longitude))
                      .toList();
            }

            // The Cloud Function now transforms steps to match Flutter's expectation
            final List<dynamic> steps =
                (routeMap['steps'] as List<dynamic>?) ?? [];

            routeOptions.add(
              RouteInfo(
                distance: routeMap['distance'] as String? ?? 'N/A',
                duration: routeMap['duration'] as String? ?? 'N/A',
                polylinePoints: polylineCoordinates,
                steps: steps,
                summary: routeMap['summary'] as String?,
              ),
            );
          }
          return routeOptions.isNotEmpty ? routeOptions : null;
        } else {
          if (kDebugMode) {
            print(
              'Directions Function: No routes found or unexpected response format.',
            );
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error calling getDirections Firebase Function: $e");
      }
    }
    return null;
  }

  Future<void> _getCurrentLocation() async {
    try {
      // Check and request location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (kDebugMode) {
            print("Location permissions denied");
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (kDebugMode) {
          print("Location permissions permanently denied");
        }
        // Show dialog to guide the user to app settings
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      ).catchError((e) {
        if (kDebugMode) {
          print("Error getting position: $e");
        }
        return Position(
          longitude: _defaultLocation.longitude,
          latitude: _defaultLocation.latitude,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0,
        );
      });

      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });

      // Animate camera if map controller is available
      if (_mapController != null) {
        _mapController!.animateCamera(CameraUpdate.newLatLng(_currentPosition));
      }
    } catch (e) {
      if (kDebugMode) {
        print("Exception getting location: $e");
      }
    }
  }

  Future<void> _addStop(
    LatLng position,
    String name, {
    List<String>? openingHoursWeekdayText,
  }) async {
    // Made async
    final id = uuid.v4();
    travel_mode.TravelMode defaultTravelMode =
        travel_mode.TravelMode.driving; // Default for the first stop

    // If there are existing stops, the new stop's travel mode should default
    // to the travel mode *to* the previously last stop.
    // The travel mode *to* a stop `n` is stored in `stops[n].travelMode`.
    // So, for a new stop being added at the end, its travel mode should
    // be based on the travel mode of the *current* last stop (which will become the second to last).
    if (stops.isNotEmpty) {
      defaultTravelMode = stops.last.travelMode;
    }

    int? aiSuggestedDuration;
    // Only fetch if the stop name is meaningful and not a generic placeholder
    if (name.isNotEmpty &&
        name.toLowerCase() != "new stop" &&
        name.toLowerCase() != "custom location" &&
        name.toLowerCase() != "picked location") {
      aiSuggestedDuration = await _fetchAISuggestedDuration(name);
    }

    final newStop = LocationStop(
      id: id,
      name: name,
      position: position,
      durationMinutes: 0, // Default duration 0 minutes
      travelMode: defaultTravelMode,
      aiSuggestedDurationMinutes: aiSuggestedDuration,
      openingHoursWeekdayText: openingHoursWeekdayText,
    );
    final newController = ExpansionTileController(); // Create controller
    setState(() {
      // Synchronous part
      stops.add(newStop);
      _tileControllers[id] = newController; // Store controller
    });

    // Move map to the new stop
    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(position, 15.0),
      ); // Zoom level 15, adjust as needed
    }

    // Asynchronous operations after state update
    await _triggerRouteAndMarkerUpdates(); // This handles markers and routes

    _searchController.clear();
    if (mounted) {
      // Check mounted before further setState
      setState(() {
        _placePredictions = [];
      });
    }
  }

  void _setDepartureForStop(
    String stopId,
    LatLng newDeparturePosition,
    String newDepartureName,
  ) {
    // Kept sync for setState
    bool updated = false;
    setState(() {
      final index = stops.indexWhere((s) => s.id == stopId);
      if (index != -1) {
        stops[index] = stops[index].copyWith(
          departureName: newDepartureName,
          departurePosition: newDeparturePosition,
        );
        updated = true;
      }
    });
    if (updated) {
      _triggerRouteAndMarkerUpdates();
    }
  }

  void _clearDepartureForStop(String stopId) {
    // Kept sync for setState
    bool updated = false;
    setState(() {
      final index = stops.indexWhere((s) => s.id == stopId);
      if (index != -1) {
        stops[index] = stops[index].copyWith(
          clearDepartureName: true,
          clearDeparturePosition: true,
        );
        updated = true;
      }
    });
    if (updated) {
      _triggerRouteAndMarkerUpdates();
    }
  }

  // Helper method to calculate adjusted marker position to avoid overlaps
  LatLng _getAdjustedMarkerPosition(
    LatLng originalPosition,
    int instanceIndexForOriginal, // 1-based index for this originalPosition
    double
    angularSeed, // To differentiate between arrival/departure series for the same original LatLng
    Set<LatLng> occupiedDisplayPositions,
  ) {
    // If it's the first instance for this original LatLng AND the original spot is free, use it.
    if (instanceIndexForOriginal == 1 &&
        !occupiedDisplayPositions.contains(originalPosition)) {
      return originalPosition;
    }

    // This marker needs to be displaced.
    // displacementRank determines the "ring" or "spiral arm" for this marker.
    // It's 0 for the first marker that needs displacement (either instanceIndex=1 but spot taken, or instanceIndex=2).
    int displacementRank = instanceIndexForOriginal - 1;
    if (instanceIndexForOriginal == 1 &&
        occupiedDisplayPositions.contains(originalPosition)) {
      // First instance for its original LatLng, but the LatLng is already occupied by another marker.
      displacementRank = 0;
    }

    LatLng candidatePosition;
    int attempt =
        0; // Collision avoidance attempts for the *calculated* displaced position
    const double baseOffsetMagnitude =
        0.000025; // Approx 2.7 meters, adjust as needed

    do {
      double effectiveDisplacementOrder =
          displacementRank.toDouble() + attempt.toDouble();
      double angle =
          angularSeed +
          effectiveDisplacementOrder *
              (pi / 3.5); // Approx 51.4 degree increments
      double magnitude =
          baseOffsetMagnitude *
          (1 +
              (effectiveDisplacementOrder *
                  0.25)); // Magnitude increases with rank and attempts
      candidatePosition = LatLng(
        originalPosition.latitude + magnitude * sin(angle),
        originalPosition.longitude + magnitude * cos(angle),
      );
      attempt++;
    } while (occupiedDisplayPositions.contains(candidatePosition) &&
        attempt < 12); // Max 12 attempts to find a free spot
    return candidatePosition;
  }

  Future<BitmapDescriptor> _createNumberedMarkerIcon(
    int number,
    Color color,
  ) async {
    final String cacheKey = "$number-${color.value}";
    if (_markerIconCache.containsKey(cacheKey)) {
      return _markerIconCache[cacheKey]!;
    }

    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    final double canvasWidth = 60.0;
    final double canvasHeight = 75.0;
    final double circleRadius = canvasWidth / 2.5; // Approx 24
    final double circleCenterY =
        circleRadius + 2; // Position circle slightly down
    final double circleCenterX = canvasWidth / 2;

    final Paint pinPaint = Paint()..color = color;

    // Draw circle part
    canvas.drawCircle(
      Offset(circleCenterX, circleCenterY),
      circleRadius,
      pinPaint,
    );

    // Draw tail part
    final Path triangle = Path();
    triangle.moveTo(
      circleCenterX - circleRadius / 2.5,
      circleCenterY + circleRadius / 1.5,
    ); // Left base of tail
    triangle.lineTo(
      circleCenterX + circleRadius / 2.5,
      circleCenterY + circleRadius / 1.5,
    ); // Right base of tail
    triangle.lineTo(circleCenterX, canvasHeight); // Tip of the pin
    triangle.close();
    canvas.drawPath(triangle, pinPaint);

    // Draw text
    final TextPainter textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    );
    final String text = number.toString();
    textPainter.text = TextSpan(
      text: text,
      style: TextStyle(
        fontSize:
            circleRadius *
            (text.length > 1
                ? 0.7
                : 0.9), // Adjust font size for multiple digits
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
    );
    textPainter.layout(minWidth: 0, maxWidth: circleRadius * 2);
    textPainter.paint(
      canvas,
      Offset(
        circleCenterX - textPainter.width / 2,
        circleCenterY - textPainter.height / 2,
      ), // Center text in circle
    );

    final ui.Image image = await pictureRecorder.endRecording().toImage(
      canvasWidth.toInt(),
      canvasHeight.toInt(),
    );
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );

    if (byteData == null) {
      // Fallback if image generation fails
      bool wasDepartureAttempt =
          color.value == Colors.orange.shade700.value; // Heuristic
      return BitmapDescriptor.defaultMarkerWithHue(
        wasDepartureAttempt
            ? BitmapDescriptor.hueOrange
            : BitmapDescriptor.hueBlue,
      );
    }

    final BitmapDescriptor descriptor = BitmapDescriptor.fromBytes(
      byteData.buffer.asUint8List(),
    );
    _markerIconCache[cacheKey] = descriptor;
    return descriptor;
  }

  Future<void> _updateMarkers() async {
    if (!mounted) return; // Early exit if not mounted

    Set<Marker> newMarkers = {};
    List<Future<Marker>> markerFutures = [];
    final Set<LatLng> finalMarkerDisplayPositions =
        {}; // Tracks actual LatLngs used on map
    final Map<LatLng, int> originalPositionReferences =
        {}; // Tracks how many markers originate from the same LatLng

    // Define colors for markers
    final Color arrivalMarkerColor =
        Theme.of(
          context,
        ).colorScheme.inversePrimary; // Safe: guarded by mounted check
    final Color departureMarkerColor = Colors.orange.shade700;

    for (int i = 0; i < stops.length; i++) {
      final stop = stops[i];

      // --- Arrival Marker ---
      final LatLng originalArrivalPos = stop.position;
      final int arrivalInstanceNum =
          (originalPositionReferences[originalArrivalPos] ?? 0) + 1;
      originalPositionReferences[originalArrivalPos] = arrivalInstanceNum;

      final LatLng displayArrivalPos = _getAdjustedMarkerPosition(
        originalArrivalPos,
        arrivalInstanceNum,
        0.0, // Base angle seed for arrivals
        finalMarkerDisplayPositions,
      );
      finalMarkerDisplayPositions.add(displayArrivalPos);

      // Future for the arrival marker icon
      final Future<BitmapDescriptor> arrivalIconFuture =
          _createNumberedMarkerIcon(i + 1, arrivalMarkerColor);
      markerFutures.add(
        arrivalIconFuture.then((icon) {
          return Marker(
            markerId: MarkerId(stop.id), // Main marker ID for the arrival stop
            position: displayArrivalPos,
            icon: icon,
            anchor: const Offset(
              0.5,
              1.0,
            ), // Tip of the pin is at the bottom center
            infoWindow: InfoWindow(
              title: '${stop.name} (Stop ${i + 1})', // Add stop number to title
              snippet:
                  _getStopScheduleSummary(i) +
                  (stop.departurePosition != null &&
                          stop.departurePosition != stop.position
                      ? "\n(Departs from: ${stop.effectiveDepartureName})"
                      : ""),
            ),
            zIndex:
                1.0, // Ensure arrival markers are generally above departure markers if they overlap
          );
        }),
      );

      // If there's a custom departure location, add a marker for it
      if (stop.departurePosition != null &&
          stop.departurePosition != stop.position) {
        final Future<BitmapDescriptor> departureIconFuture =
            _createNumberedMarkerIcon(
              i + 1,
              departureMarkerColor,
            ); // Same number, different color

        markerFutures.add(
          departureIconFuture.then((icon) {
            return Marker(
              markerId: MarkerId(
                '${stop.id}_departure',
              ), // Unique ID for departure marker
              position: stop.effectiveDeparturePosition,
              icon: icon,
              anchor: const Offset(0.5, 1.0),
              infoWindow: InfoWindow(
                title:
                    'Departure for Stop ${i + 1}: ${stop.effectiveDepartureName}',
                snippet: 'Associated with: ${stop.name}',
              ),
              zIndex: 0.5, // Lower zIndex than arrival if they could overlap
            );
          }),
        );
      }
    }

    // Wait for all marker futures to complete
    final List<Marker> resolvedMarkers = await Future.wait(markerFutures);
    newMarkers.addAll(resolvedMarkers);

    if (mounted) {
      // Double check, good practice
      setState(() {
        _markers = newMarkers;
      });
    }
  }

  Future<void> _calculateRoutes() async {
    if (stops.length < 2) {
      setState(() {
        routes.clear();
        selectedRouteIndices.clear();
        _polylines.clear();
        _routeLabelMarkers.clear(); // Clear route labels as well
        isLoading = false;
      });
      return;
    }

    setState(() {
      isLoading = true;
    });

    Map<String, List<RouteInfo>> newRoutes = {};
    Map<String, int> newSelectedRouteIndices = {};

    DateTime currentExpectedArrivalTimeForNextStop = tripStartTime;

    // If the first stop has a manual arrival time, it dictates the start for our internal calculation.
    if (stops.isNotEmpty && stops.first.manualArrivalTime != null) {
      currentExpectedArrivalTimeForNextStop = stops.first.manualArrivalTime!;
    }

    for (int i = 0; i < stops.length - 1; i++) {
      final currentStop = stops[i];
      final nextStop = stops[i + 1];

      // Determine arrival time at currentStop (stops[i]) for this calculation pass
      DateTime actualArrivalTimeAtCurrentStop;
      if (currentStop.manualArrivalTime != null) {
        actualArrivalTimeAtCurrentStop = currentStop.manualArrivalTime!;
      } else {
        actualArrivalTimeAtCurrentStop = currentExpectedArrivalTimeForNextStop;
      }

      // Determine departure time from currentStop (stops[i]) for this segment
      DateTime departureTimeForThisSegment;
      if (currentStop.manualDepartureTime != null) {
        departureTimeForThisSegment = currentStop.manualDepartureTime!;
        // Ensure manual departure is not before calculated/manual arrival for this pass
        if (departureTimeForThisSegment.isBefore(
          actualArrivalTimeAtCurrentStop,
        )) {
          departureTimeForThisSegment = actualArrivalTimeAtCurrentStop.add(
            Duration(minutes: currentStop.durationMinutes),
          );
        }
      } else {
        departureTimeForThisSegment = actualArrivalTimeAtCurrentStop.add(
          Duration(minutes: currentStop.durationMinutes),
        );
      }

      final origin = currentStop.effectiveDeparturePosition;
      final destination = nextStop.position;
      final travelMode =
          nextStop.travelMode; // Travel mode TO nextStop is stored IN nextStop
      final routeId = '${currentStop.id}-${nextStop.id}';

      // Pass departureTimeForThisSegment to _getDirections
      final List<RouteInfo>? routeOptions = await _getDirections(
        origin,
        destination,
        travelMode,
        departureTime: departureTimeForThisSegment,
      );

      if (routeOptions != null && routeOptions.isNotEmpty) {
        newRoutes[routeId] = routeOptions;
        int currentSelection = selectedRouteIndices[routeId] ?? 0;
        if (currentSelection >= routeOptions.length) {
          currentSelection =
              0; // Default to first route if previous selection is invalid
        }
        newSelectedRouteIndices[routeId] = currentSelection;

        // Update currentExpectedArrivalTimeForNextStop for the *next* segment's start (arrival at nextStop)
        final selectedRouteDurationStr =
            routeOptions[currentSelection].duration;
        final travelMinutes = _parseDurationString(selectedRouteDurationStr);
        currentExpectedArrivalTimeForNextStop = departureTimeForThisSegment.add(
          Duration(minutes: travelMinutes),
        );
      } else {
        newSelectedRouteIndices.remove(routeId); // No routes, remove selection
        // If no route, the next segment's arrival time will be based on the current segment's departure time
        // (effectively zero travel time for this provisional calculation).
        // The main _computeScheduleDetails will handle "No route" display and actual schedule impact.
        currentExpectedArrivalTimeForNextStop = departureTimeForThisSegment;
      }
    }

    if (mounted) {
      setState(() {
        routes = newRoutes;
        selectedRouteIndices = newSelectedRouteIndices;
        isLoading = false;
      });
    }
    _updateMapPolylines(); // Centralized polyline drawing
  }

  // Helper method to consolidate asynchronous updates after state changes
  Future<void> _triggerRouteAndMarkerUpdates() async {
    if (!mounted) return;
    await _updateMarkers(); // Calls setState internally for markers
    await _calculateRoutes(); // Calls setState internally for routes and isLoading
    // _updateMapPolylines(); // Already called by _calculateRoutes
  }

  void _removeStop(String id) {
    // Kept sync for setState
    bool wasActuallyRemoved = false;

    setState(() {
      final index = stops.indexWhere((s) => s.id == id);
      if (index != -1) {
        stops.removeAt(index);
        _tileControllers.remove(id); // Remove controller when stop is removed
        if (_expandedStopId == id) {
          _expandedStopId = null;
        }
        wasActuallyRemoved = true;
      }
    });

    if (wasActuallyRemoved) {
      _triggerRouteAndMarkerUpdates();
    }
  }

  void _updateStopDuration(String id, int durationMinutes) {
    setState(() {
      final index = stops.indexWhere((stop) => stop.id == id);
      if (index != -1) {
        stops[index] = stops[index].copyWith(
          durationMinutes: durationMinutes,
          // If a manual departure time was set, changing the duration slider
          // implies the user wants to control duration again, so clear the manual departure.
          // Manual arrival time remains unaffected.
          clearManualDepartureTime: stops[index].manualDepartureTime != null,
        );
      }
      // setState will trigger UI rebuild, which uses _computeScheduleDetails
    });
  }

  Future<void> _pickDateTime(
    BuildContext context, {
    required DateTime initialDate,
    required Function(DateTime) onDateTimePicked,
  }) async {
    // For individual stops, we only allow picking the time.
    // The date component will be preserved from the initialDate.
    // The overall trip start time has its own dedicated date and time pickers.
    if (!context.mounted) return; // Check if widget is still mounted

    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (pickedTime != null) {
      final finalDateTime = DateTime(
        initialDate.year, // Use year from initialDate
        initialDate.month, // Use month from initialDate
        initialDate.day, // Use day from initialDate
        pickedTime.hour,
        pickedTime.minute,
      );
      onDateTimePicked(finalDateTime);
    }
  }

  void _setManualArrivalTime(String stopId, DateTime? time) {
    setState(() {
      final index = stops.indexWhere((s) => s.id == stopId);
      if (index == -1) return;

      if (time == null) {
        // Clearing the manual arrival time for the stop
        stops[index] = stops[index].copyWith(clearManualArrivalTime: true);
        // No backward propagation needed when clearing.
        // The schedule will naturally re-flow from tripStartTime or other existing manual times.
      } else {
        // Setting or changing the manual arrival time
        DateTime newManualArrivalTime = time;
        stops[index] = stops[index].copyWith(
          manualArrivalTime: newManualArrivalTime,
        );

        // If this stop's manual departure time is now before its new manual arrival time, clear the departure time.
        if (stops[index].manualDepartureTime != null &&
            stops[index].manualDepartureTime!.isBefore(newManualArrivalTime)) {
          stops[index] = stops[index].copyWith(clearManualDepartureTime: true);
        }

        if (index == 0) {
          // If the first stop's arrival time is manually set, it becomes the trip start time.
          tripStartTime = newManualArrivalTime;
        } else {
          // For subsequent stops, propagate changes backward.
          DateTime anchorArrivalTime =
              newManualArrivalTime; // This is the fixed arrival time for stops[j+1] (initially stops[index])

          for (int j = index - 1; j >= 0; j--) {
            LocationStop currentStopToAdjust = stops[j];
            LocationStop nextStopInSequence =
                stops[j +
                    1]; // The stop whose arrival time (anchorArrivalTime) is guiding this adjustment

            int travelMinutesToNextStop = 0;
            final routeId =
                '${currentStopToAdjust.id}-${nextStopInSequence.id}';
            if (routes.containsKey(routeId) && routes[routeId] != null) {
              final List<RouteInfo>? routeOptions = routes[routeId];
              final int selectedIdx = selectedRouteIndices[routeId] ?? 0;
              if (routeOptions != null &&
                  routeOptions.isNotEmpty &&
                  selectedIdx < routeOptions.length) {
                travelMinutesToNextStop = _parseDurationString(
                  routeOptions[selectedIdx].duration,
                );
              }
            }

            DateTime requiredDepartureForCurrent = anchorArrivalTime.subtract(
              Duration(minutes: travelMinutesToNextStop),
            );

            // Check currentStopToAdjust's manual departure time
            if (currentStopToAdjust.manualDepartureTime != null) {
              if (currentStopToAdjust.manualDepartureTime!.isAfter(
                requiredDepartureForCurrent,
              )) {
                // Conflict: Manual departure is too late. Clear it to allow cascade.
                stops[j] = currentStopToAdjust.copyWith(
                  clearManualDepartureTime: true,
                );
                currentStopToAdjust = stops[j]; // Refresh from list
              } else {
                // Manual departure is not conflicting (it's earlier or same). It acts as a firewall.
                // The new arrival for currentStopToAdjust is its manualDeparture - its duration.
                anchorArrivalTime = currentStopToAdjust.manualDepartureTime!
                    .subtract(
                      Duration(minutes: currentStopToAdjust.durationMinutes),
                    );
                // If currentStopToAdjust also has a manualArrivalTime, check for conflict with this derived arrival
                if (currentStopToAdjust.manualArrivalTime != null &&
                    currentStopToAdjust.manualArrivalTime!.isAfter(
                      anchorArrivalTime,
                    )) {
                  stops[j] = currentStopToAdjust.copyWith(
                    clearManualArrivalTime: true,
                  );
                  // currentStopToAdjust = stops[j]; // Refresh if needed later, but we break now
                }
                if (j == 0) {
                  tripStartTime = anchorArrivalTime;
                }
                break; // Cascade stops at this firewall
              }
            }

            // If no manual departure or it was cleared, calculate new arrival for currentStopToAdjust
            DateTime newArrivalForCurrent = requiredDepartureForCurrent
                .subtract(
                  Duration(minutes: currentStopToAdjust.durationMinutes),
                );

            // Check currentStopToAdjust's manual arrival time
            if (currentStopToAdjust.manualArrivalTime != null) {
              if (currentStopToAdjust.manualArrivalTime!.isAfter(
                newArrivalForCurrent,
              )) {
                // Conflict: Manual arrival is too late. Clear it.
                stops[j] = currentStopToAdjust.copyWith(
                  clearManualArrivalTime: true,
                );
                // currentStopToAdjust = stops[j]; // Refresh if needed later
              } else {
                // Manual arrival is not conflicting. It acts as a firewall.
                anchorArrivalTime = currentStopToAdjust.manualArrivalTime!;
                if (j == 0) {
                  tripStartTime = anchorArrivalTime;
                }
                break; // Cascade stops at this firewall
              }
            }

            // If we reach here, currentStopToAdjust's arrival is determined by the cascade.
            anchorArrivalTime =
                newArrivalForCurrent; // This new arrival becomes the anchor for the stop before it (if any).

            if (j == 0) {
              tripStartTime = anchorArrivalTime;
            }
          }
        }
      }
    });
  }

  void _setManualDepartureTime(String stopId, DateTime? time) {
    setState(() {
      final index = stops.indexWhere((s) => s.id == stopId);
      if (index != -1) {
        stops[index] = stops[index].copyWith(
          manualDepartureTime: time,
          clearManualDepartureTime: time == null,
        );
        // If manual departure is set, and an existing manual arrival is now after it, clear manual arrival.
        if (time != null &&
            stops[index].manualArrivalTime != null &&
            stops[index].manualArrivalTime!.isAfter(time)) {
          stops[index] = stops[index].copyWith(clearManualArrivalTime: true);
        }
      }
    });
  }

  void _updateStopNotes(String stopId, String? newNotes) {
    if (!mounted) return;
    setState(() {
      final index = stops.indexWhere((s) => s.id == stopId);
      if (index != -1) {
        // Ensure notes are trimmed and null if empty
        final String? processedNotes =
            (newNotes != null && newNotes.trim().isNotEmpty)
                ? newNotes.trim()
                : null;
        stops[index] = stops[index].copyWith(notes: processedNotes);
      }
    });
  }

  void _updateTravelMode(String id, travel_mode.TravelMode mode) {
    bool updated = false;
    setState(() {
      final index = stops.indexWhere((stop) => stop.id == id);
      if (index != -1) {
        stops[index] = stops[index].copyWith(travelMode: mode);
        updated = true;
      }
    });
    if (updated) {
      _triggerRouteAndMarkerUpdates();
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      // This adjustment is needed because onReorder gives the newIndex
      // as if the item was already removed.
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final LocationStop item = stops.removeAt(oldIndex);
      stops.insert(newIndex, item);
    });
    _triggerRouteAndMarkerUpdates();
  }

  // Helper to parse duration string (e.g., "1 hour 23 mins" or "25 mins")
  int _parseDurationString(String durationStr) {
    int travelMinutes = 0;
    final hourMatch = RegExp(r'(\d+)\s*hour').firstMatch(durationStr);
    final minMatch = RegExp(r'(\d+)\s*min').firstMatch(durationStr);

    if (hourMatch != null) {
      travelMinutes += int.parse(hourMatch.group(1)!) * 60;
    }
    if (minMatch != null) {
      travelMinutes += int.parse(minMatch.group(1)!);
    }
    return travelMinutes;
  }

  List<ScheduledStopInfo> _computeScheduleDetails() {
    if (stops.isEmpty) return [];

    List<ScheduledStopInfo> schedule = [];
    DateTime currentExpectedArrivalTime = tripStartTime;

    for (int i = 0; i < stops.length; i++) {
      final stop = stops[i];
      DateTime actualArrivalTime;
      bool arrivalIsManual = false;
      String? travelTimeText;

      // Determine actual arrival time for the current stop
      if (stop.manualArrivalTime != null) {
        actualArrivalTime = stop.manualArrivalTime!;
        arrivalIsManual = true;
      } else {
        actualArrivalTime = currentExpectedArrivalTime;
      }

      // Get travel duration text from previous stop to this one
      if (i > 0) {
        final prevScheduledStop = schedule.last; // This is schedule[i-1]
        final routeId = '${prevScheduledStop.stop.id}-${stop.id}';
        if (routes.containsKey(routeId)) {
          final List<RouteInfo>? routeOptions = routes[routeId];
          final int selectedIdx = selectedRouteIndices[routeId] ?? 0;
          if (routeOptions != null &&
              routeOptions.isNotEmpty &&
              selectedIdx < routeOptions.length) {
            travelTimeText = routeOptions[selectedIdx].duration;
          }
        }
      }

      DateTime actualDepartureTime;
      bool departureIsManual = false;
      if (stop.manualDepartureTime != null) {
        actualDepartureTime = stop.manualDepartureTime!;
        departureIsManual = true;
        // Ensure departure is not before arrival; if so, fallback to durationMinutes
        if (actualDepartureTime.isBefore(actualArrivalTime)) {
          actualDepartureTime = actualArrivalTime.add(
            Duration(minutes: stop.durationMinutes),
          );
          departureIsManual = false; // Considered not manually set if corrected
        }
      } else {
        actualDepartureTime = actualArrivalTime.add(
          Duration(minutes: stop.durationMinutes),
        );
      }

      schedule.add(
        ScheduledStopInfo(
          stop: stop,
          arrivalTime: actualArrivalTime,
          departureTime: actualDepartureTime,
          isArrivalManual: arrivalIsManual,
          isDepartureManual: departureIsManual,
          travelDurationToThisStopText: travelTimeText,
        ),
      );

      // For the *next* stop's expected arrival time:
      // This is the departure time of the current stop + travel time to the next stop.
      if (i < stops.length - 1) {
        final nextStop = stops[i + 1]; // The actual next LocationStop object
        final routeId =
            '${stop.id}-${nextStop.id}'; // Route from current to next
        if (routes.containsKey(routeId)) {
          final List<RouteInfo>? routeOptions = routes[routeId];
          final int selectedIdx = selectedRouteIndices[routeId] ?? 0;
          int travelMinutes = 0;
          if (routeOptions != null &&
              routeOptions.isNotEmpty &&
              selectedIdx < routeOptions.length) {
            travelMinutes = _parseDurationString(
              routeOptions[selectedIdx].duration,
            );
          }
          currentExpectedArrivalTime = actualDepartureTime.add(
            Duration(minutes: travelMinutes),
          );
        } else {
          currentExpectedArrivalTime =
              actualDepartureTime; // No route, assume immediate travel for calculation
        }
      }
    }
    return schedule;
  }

  // Helper method to create marker icons for route alternative labels
  Future<BitmapDescriptor> _createRouteLabelMarkerIcon(
    String label,
    Color color, {
    bool isSelected = false,
  }) async {
    final String cacheKey = "routeLabel-$label-${color.value}-$isSelected";
    if (_markerIconCache.containsKey(cacheKey)) {
      return _markerIconCache[cacheKey]!;
    }

    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final double size = isSelected ? 42.0 : 36.0; // Slightly larger if selected
    final double borderSize = 1.5;

    // Outer circle (border for contrast)
    final Paint borderPaint =
        Paint()..color = Colors.black.withValues(alpha: 0.6);
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2, borderPaint);

    // Inner circle
    final Paint paint = Paint()..color = color;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - borderSize, paint);

    final TextPainter textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.text = TextSpan(
      text: label,
      style: TextStyle(
        fontSize: size * 0.40, // Adjusted for smaller circle and border
        color: Colors.white,
        fontWeight: FontWeight.bold,
        shadows: const [
          Shadow(
            blurRadius: 1.0,
            color: Colors.black54,
            offset: Offset(0.5, 0.5),
          ),
        ],
      ),
    );
    textPainter.layout(minWidth: 0, maxWidth: size - (borderSize * 2));
    textPainter.paint(
      canvas,
      Offset(
        size / 2 - textPainter.width / 2,
        size / 2 - textPainter.height / 2,
      ),
    );

    final ui.Image image = await pictureRecorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );

    if (byteData == null) return BitmapDescriptor.defaultMarker; // Fallback

    final BitmapDescriptor descriptor = BitmapDescriptor.fromBytes(
      byteData.buffer.asUint8List(),
    );
    _markerIconCache[cacheKey] = descriptor;
    return descriptor;
  }

  void _updateMapPolylines() {
    if (!mounted) return;

    Set<Polyline> newPolylines = {};
    final List<Color> baseRouteColors = [
      // Base colors for selected routes
      Colors.blue, Colors.red, Colors.green, Colors.purple, Colors.orange,
    ];
    const double defaultWidth = 5.0;
    const double alternativeWidth = 4.0;
    const double selectedAlternativeWidth = 6.0;
    Set<Marker> tempRouteLabelMarkers = {}; // Temporary set for this update

    List<Future<void>> allLabelMarkerFutures = [];

    for (int i = 0; i < stops.length - 1; i++) {
      final currentStop = stops[i];
      final nextStop = stops[i + 1];
      final routeId = '${currentStop.id}-${nextStop.id}';
      final Color segmentBaseColor =
          baseRouteColors[i % baseRouteColors.length];

      final Color alternativeRouteDimColor = Colors.grey.withValues(alpha: 0.7);

      if (routes.containsKey(routeId)) {
        final List<RouteInfo> routeOptions = routes[routeId]!;
        final int selectedIndex = selectedRouteIndices[routeId] ?? 0;

        // Correctly check if the segment leading to nextStop is expanded
        bool isExpandedSegment =
            (stops.length > i + 1) && (stops[i + 1].id == _expandedStopId);

        if (isExpandedSegment) {
          // Show all alternatives for the expanded segment
          for (int j = 0; j < routeOptions.length; j++) {
            final routeInfo = routeOptions[j];
            final bool isSelectedAlternative = j == selectedIndex;
            newPolylines.add(
              Polyline(
                polylineId: PolylineId('$routeId-alt-$j'),
                points: routeInfo.polylinePoints,
                color:
                    isSelectedAlternative
                        ? segmentBaseColor
                        : alternativeRouteDimColor,
                width:
                    (isSelectedAlternative
                            ? selectedAlternativeWidth
                            : alternativeWidth)
                        .toInt(),
                zIndex: isSelectedAlternative ? 2 : 1,
                consumeTapEvents: true,
                onTap: () {
                  if (mounted) {
                    setState(() {
                      selectedRouteIndices[routeId] = j;
                    });
                    _updateMapPolylines(); // Redraw to reflect selection
                  }
                },
              ),
            );

            // Add future for label marker creation
            allLabelMarkerFutures.add(
              Future(() async {
                String label;
                final routeOpt = routeOptions[j];
                // The travel mode for the leg from currentStop (stops[i]) to nextStop (stops[i+1])
                // is determined by nextStop.travelMode.
                if (stops.length > i + 1 &&
                    stops[i + 1].travelMode == travel_mode.TravelMode.transit) {
                  label = _getShortTransitLabel(routeOpt, j + 1);
                } else {
                  label = (j + 1).toString();
                }

                final Color labelColor =
                    isSelectedAlternative
                        ? segmentBaseColor
                        : alternativeRouteDimColor;
                final BitmapDescriptor labelIcon =
                    await _createRouteLabelMarkerIcon(
                      label,
                      labelColor,
                      isSelected: isSelectedAlternative,
                    );

                LatLng markerPos;
                int numPoints = routeInfo.polylinePoints.length;
                if (numPoints > 0) {
                  // Position at ~25% of the route, with a small nudge if very short
                  int idx = (numPoints * 0.25).floor();
                  if (numPoints > 1 && idx == 0 && numPoints > 2) {
                    idx = (numPoints * 0.1).floor().clamp(
                      1,
                      numPoints - 1,
                    ); // Try 10% or 1st point
                  } else if (numPoints == 1) {
                    idx = 0;
                  }
                  markerPos =
                      routeInfo.polylinePoints[idx.clamp(0, numPoints - 1)];
                } else {
                  return; // No points to place a marker
                }

                tempRouteLabelMarkers.add(
                  Marker(
                    markerId: MarkerId('$routeId-alt-$j-label'),
                    position: markerPos,
                    icon: labelIcon,
                    anchor: const Offset(0.5, 0.5),
                    zIndex: 3, // Above polylines
                    consumeTapEvents: true,
                    onTap: () {
                      if (mounted) {
                        setState(() {
                          selectedRouteIndices[routeId] = j;
                        });
                        _updateMapPolylines();
                      }
                    },
                  ),
                );
              }),
            );
          }
        } else {
          // Not expanded: show only the primary selected route for this segment
          if (selectedIndex < routeOptions.length) {
            final selectedRouteInfo = routeOptions[selectedIndex];
            newPolylines.add(
              Polyline(
                polylineId: PolylineId(routeId),
                points: selectedRouteInfo.polylinePoints,
                color: segmentBaseColor,
                width: defaultWidth.toInt(),
                zIndex: 0,
              ),
            );
          }
        }
      }
    }
    // Wait for all label icon generation futures to complete
    Future.wait(allLabelMarkerFutures)
        .then((_) {
          if (mounted) {
            setState(() {
              _polylines = newPolylines;
              _routeLabelMarkers = tempRouteLabelMarkers;
            });
          }
        })
        .catchError((e) {
          if (kDebugMode) {
            print("Error generating route label markers: $e");
          }
          if (mounted) {
            // Still update polylines even if markers fail
            setState(() {
              _polylines = newPolylines;
              _routeLabelMarkers =
                  tempRouteLabelMarkers; // Might be empty or partially filled
            });
          }
        });
  }

  void _updatePolylinesForSegment(String routeId, int selectedRouteIndex) {
    if (routes.containsKey(routeId)) {
      final routeOptions = routes[routeId]!;
      if (selectedRouteIndex < routeOptions.length) {
        setState(() {
          selectedRouteIndices[routeId] = selectedRouteIndex;
        });
        _updateMapPolylines(); // Update all polylines based on new selection and expanded state
      }
    }
  }

  String _getStopScheduleSummary(int stopIndex) {
    final List<ScheduledStopInfo> detailedSchedule = _computeScheduleDetails();
    if (stopIndex < 0 || stopIndex >= detailedSchedule.length) {
      return 'Schedule N/A';
    }

    final scheduledStop = detailedSchedule[stopIndex];
    String arrivalStr = DateFormat('h:mm a').format(scheduledStop.arrivalTime);
    String departureStr = DateFormat(
      'h:mm a',
    ).format(scheduledStop.departureTime);
    String arrivalSuffix = scheduledStop.isArrivalManual ? " (M)" : "";
    String departureSuffix = scheduledStop.isDepartureManual ? " (M)" : "";

    return 'Arrival: $arrivalStr$arrivalSuffix | Depart: $departureStr$departureSuffix';
  }

  DateTime _getInitialPickerDateTimeForArrival(int stopIndex) {
    // Ensure stops list is accessed safely
    if (stopIndex < 0 || stopIndex >= stops.length) {
      // If adding a new stop (stopIndex == stops.length)
      if (stopIndex == stops.length && stops.isNotEmpty) {
        final schedule = _computeScheduleDetails();
        if (schedule.isNotEmpty) {
          // Suggest starting after the last stop's departure
          return schedule.last.departureTime;
        }
      }
      return tripStartTime; // Fallback for first stop or out of bounds
    }

    final stop = stops[stopIndex];
    if (stop.manualArrivalTime != null) return stop.manualArrivalTime!;

    final List<ScheduledStopInfo> schedule = _computeScheduleDetails();
    if (stopIndex < schedule.length) {
      return schedule[stopIndex].arrivalTime;
    }

    // Fallback if something unexpected happens
    if (stopIndex == 0) return tripStartTime;
    return DateTime.now();
  }

  DateTime _getInitialPickerDateTimeForDeparture(int stopIndex) {
    if (stopIndex < 0 || stopIndex >= stops.length) {
      // If adding a new stop (stopIndex == stops.length)
      if (stopIndex == stops.length && stops.isNotEmpty) {
        final schedule = _computeScheduleDetails();
        if (schedule.isNotEmpty) {
          // Suggest departure 30 mins after last stop's departure
          return schedule.last.departureTime.add(const Duration(minutes: 30));
        }
      }
      // Fallback for first stop or out of bounds, 30 mins after trip start
      return tripStartTime.add(const Duration(minutes: 30));
    }

    final stop = stops[stopIndex];
    if (stop.manualDepartureTime != null) return stop.manualDepartureTime!;

    final List<ScheduledStopInfo> schedule = _computeScheduleDetails();
    DateTime arrivalForThisStop;

    if (stop.manualArrivalTime != null) {
      arrivalForThisStop = stop.manualArrivalTime!;
    } else if (stopIndex < schedule.length) {
      arrivalForThisStop = schedule[stopIndex].arrivalTime;
    } else {
      // Fallback: try to get initial arrival for picker
      arrivalForThisStop = _getInitialPickerDateTimeForArrival(stopIndex);
    }

    return arrivalForThisStop.add(Duration(minutes: stop.durationMinutes));
  }

  Future<void> _onMapLongPress(LatLng position) async {
    if (_pickingDepartureOnMapForStopId != null) {
      // Handle setting a custom departure location for an existing stop
      final stopIdForDeparture = _pickingDepartureOnMapForStopId!;
      // Reset the mode and hide SnackBar *before* showing the dialog
      setState(() {
        _pickingDepartureOnMapForStopId = null;
      });
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // If context is no longer mounted (e.g., rapid navigation), bail out.
      if (!mounted) return;

      // Proceed to get a name for this custom departure location
      final TextEditingController nameController = TextEditingController();
      final departureName = await showDialog<String>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Name Custom Departure'),
            content: TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Enter departure name (e.g., Back Entrance)',
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: const Text('Set Departure'),
                onPressed: () {
                  Navigator.of(context).pop(nameController.text);
                },
              ),
            ],
          );
        },
      );

      if (departureName != null && departureName.isNotEmpty) {
        _setDepartureForStop(stopIdForDeparture, position, departureName);
      }
      return; // Exit after handling departure setting
    } else if (_isPickingNewStopOnMap) {
      // Handle adding a new stop via map picking mode
      // Reset the mode and hide SnackBar *before* showing the dialog
      setState(() {
        _isPickingNewStopOnMap = false;
      });
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // If context is no longer mounted, bail out.
      if (!mounted) return;

      // Proceed to get a name for the new stop
      final TextEditingController nameController = TextEditingController();
      final stopName = await showDialog<String>(
        context: context, // Use the main context for the dialog
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Add Stop'),
            content: TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Enter stop name'),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: const Text('Add'),
                onPressed: () {
                  Navigator.of(context).pop(nameController.text);
                },
              ),
            ],
          );
        },
      );
      if (stopName != null && stopName.isNotEmpty) {
        // For stops added via long-press, we don't have opening hours immediately.
        _addStop(position, stopName, openingHoursWeekdayText: null);
      }
      return; // Exit after handling new stop addition
    }
    // If neither picking mode is active, long-press does nothing.
  }

  // Helper method to apply the current _selectedMapStyleName to the map
  Future<void> _applySelectedStyleToMap() async {
    if (_mapController == null) return;
    try {
      if (_selectedMapStyleName == map_styles.styleSatelliteName) {
        // For satellite, mapType change (handled by widget rebuild) is primary.
        // Clear any existing JSON style.
        await _mapController!.setMapStyle(null);
      } else {
        // For other styles, ensure mapType is normal (handled by widget rebuild)
        // and apply the JSON style.
        final String? styleJson =
            map_styles.availableMapStyles[_selectedMapStyleName];
        await _mapController!.setMapStyle(styleJson);
      }
      if (kDebugMode) {
        print("Applied style '$_selectedMapStyleName' to map.");
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error applying style '$_selectedMapStyleName' to map: $e");
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error applying style: $_selectedMapStyleName'),
          ),
        );
      }
    }
  }

  // Method to change and apply the map style
  Future<void> _selectMapStyle(String styleName) async {
    // The styleName comes from PopupMenuButton which is built from _availableMapStyles.keys,
    // so _availableMapStyles.containsKey(styleName) is implicitly true.
    if (styleName == _selectedMapStyleName ||
        !map_styles.availableMapStyles.containsKey(styleName)) {
      return; // Style not found or already selected
    }

    final String oldStyle =
        _selectedMapStyleName; // Store old style for potential revert on error

    // Optimistically update UI first
    if (mounted) {
      setState(() {
        _selectedMapStyleName = styleName;
      });
    } else {
      if (kDebugMode) {
        print("Attempted to select map style while widget was not mounted.");
      }
      return;
    }

    if (_mapController != null) {
      try {
        await _applySelectedStyleToMap(); // This uses the new _selectedMapStyleName
        if (kDebugMode) {
          print("Successfully applied style/type: $styleName to map.");
        }

        // Save preference to Firestore
        final User? currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null && !currentUser.isAnonymous) {
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(currentUser.uid)
                .set({'lastMapStyle': styleName}, SetOptions(merge: true));
            if (kDebugMode) {
              print("Saved map style preference '$styleName' to Firestore.");
            }
          } catch (firestoreError) {
            if (kDebugMode) {
              print(
                "Error saving map style preference '$styleName' to Firestore: $firestoreError",
              );
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Map style changed, but failed to save preference.',
                  ),
                ),
              );
            }
          }
        }
      } catch (mapStyleError) {
        if (kDebugMode) {
          print(
            "Error applying map style/type $styleName to map: $mapStyleError",
          );
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error applying style: $styleName. Reverting.'),
            ),
          );
          // Revert to old style on map application error
          setState(() {
            _selectedMapStyleName = oldStyle;
          });
          await _applySelectedStyleToMap(); // Re-apply the old style
        }
      }
    } else {
      // _mapController is null. _selectedMapStyleName is updated.
      // _onGoogleMapCreated will handle applying this style when the map is ready.
      // Still attempt to save the preference.
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && !currentUser.isAnonymous) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .set({'lastMapStyle': styleName}, SetOptions(merge: true));
          if (kDebugMode) {
            print(
              "Saved map style preference '$styleName' to Firestore (map not ready).",
            );
          }
        } catch (firestoreError) {
          if (kDebugMode) {
            print(
              "Error saving map style preference '$styleName' to Firestore (map not ready): $firestoreError",
            );
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Map style selected, but failed to save preference.',
                ),
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _onGoogleMapCreated(GoogleMapController controller) async {
    _mapController = controller;
    // Apply the initially selected style/type when the map is ready.
    // _selectedMapStyleName should be up-to-date from _loadUserPreferences by now.
    await _applySelectedStyleToMap();
    if (kDebugMode) {
      print(
        "Initial map style/type '$_selectedMapStyleName' applied onMapCreated.",
      );
    }

    // If _currentPosition has been updated from default, ensure map reflects it.
    if (_currentPosition != _defaultLocation && _mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLng(_currentPosition));
    }
  }

  // Helper to check if a given DateTime is within the opening hours for that day.
  bool _isTimeWithinOpeningHours(
    DateTime dateTimeToCheck,
    List<String>? openingHoursWeekdayText,
  ) {
    if (openingHoursWeekdayText == null || openingHoursWeekdayText.isEmpty) {
      return true; // No hours info, assume open or unknown (no warning)
    }
    if (openingHoursWeekdayText.length != 7) {
      if (kDebugMode) {
        print(
          "Warning: openingHoursWeekdayText does not contain 7 days of data.",
        );
      }
      return true; // Data is malformed, assume open
    }

    // dateTimeToCheck.weekday: Monday (1) to Sunday (7)
    // openingHoursWeekdayText: Google Places API usually orders Sunday (index 0) to Saturday (index 6)
    int dayIndex =
        dateTimeToCheck.weekday %
        7; // Sunday (7%7=0), Monday (1%7=1), ..., Saturday (6%7=6)

    final String hoursForDayString = openingHoursWeekdayText[dayIndex];
    final int colonIndex = hoursForDayString.indexOf(':');

    if (colonIndex == -1 || colonIndex + 1 >= hoursForDayString.length) {
      if (kDebugMode) {
        print(
          "Warning: Malformed opening hours string (missing colon or content after colon): $hoursForDayString",
        );
      }
      return true; // Malformed, assume open
    }
    final String hoursPart = hoursForDayString.substring(colonIndex + 1).trim();

    if (hoursPart.toLowerCase() == 'closed') {
      return false;
    }
    if (hoursPart.toLowerCase().contains('open 24 hours')) {
      return true;
    }

    final List<String> timeRanges =
        hoursPart.split(',').map((e) => e.trim()).toList();
    final TimeOfDay timeToCheckAsTimeOfDay = TimeOfDay.fromDateTime(
      dateTimeToCheck,
    );
    final int timeToCheckInMinutes =
        timeToCheckAsTimeOfDay.hour * 60 + timeToCheckAsTimeOfDay.minute;

    for (final String range in timeRanges) {
      List<String> parts =
          range.split('–').map((e) => e.trim()).toList(); // en-dash (U+2013)
      if (parts.length != 2) {
        parts = range.split('-').map((e) => e.trim()).toList(); // hyphen
        if (parts.length != 2) {
          if (kDebugMode) {
            print(
              "Warning: Could not parse time range: \"$range\" from \"$hoursForDayString\"",
            );
          }
          continue;
        }
      }

      try {
        final DateTime startTimeDt = DateFormat.jm().parseLoose(parts[0]);
        final TimeOfDay startTimeOfDay = TimeOfDay.fromDateTime(startTimeDt);
        final int startMinutes =
            startTimeOfDay.hour * 60 + startTimeOfDay.minute;

        final DateTime endTimeDt = DateFormat.jm().parseLoose(parts[1]);
        final TimeOfDay endTimeOfDay = TimeOfDay.fromDateTime(endTimeDt);
        int endMinutes = endTimeOfDay.hour * 60 + endTimeOfDay.minute;

        // Adjust for "12:00 AM" / "Midnight" potentially meaning end of the current day (24:00)
        // This applies if the range is like "8:00 AM – 12:00 AM" (meaning 8 AM to 23:59:59 of the same day)
        String rawEndTimeStr = parts[1].trim().toLowerCase();
        if ((rawEndTimeStr == "12:00 am" || rawEndTimeStr == "midnight") &&
            endMinutes == 0 &&
            startMinutes > 0) {
          endMinutes =
              24 * 60; // Treat as 24:00 (exclusive end) for the current day
        }

        if (endMinutes < startMinutes) {
          // Range crosses midnight (e.g., 10 PM – 2 AM next day)
          // time is after start (e.g. 11 PM) OR time is before/at end (e.g. 1 AM)
          if (timeToCheckInMinutes >= startMinutes ||
              timeToCheckInMinutes < endMinutes) {
            return true;
          }
        } else {
          // Normal range (e.g., 9 AM – 5 PM) or (8 AM – Midnight [now 24*60])
          // Time is after/at start AND before end
          if (timeToCheckInMinutes >= startMinutes &&
              timeToCheckInMinutes < endMinutes) {
            return true;
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print(
            "Warning: Error parsing time string in range \"$range\" for day index $dayIndex ($hoursForDayString): $e",
          );
        }
      }
    }
    return false; // Not within any specified open time range
  }

  String _getStopOpeningHoursWarning(int stopIndex) {
    if (stopIndex < 0 || stopIndex >= stops.length) return "";
    final List<ScheduledStopInfo> schedule = _computeScheduleDetails();
    if (stopIndex >= schedule.length) return "";

    final ScheduledStopInfo scheduledStop = schedule[stopIndex];
    final LocationStop locationStop = stops[stopIndex];

    if (locationStop.openingHoursWeekdayText == null ||
        locationStop.openingHoursWeekdayText!.isEmpty) {
      return ""; // No hours info, no warning
    }

    bool arrivalOutside =
        !_isTimeWithinOpeningHours(
          scheduledStop.arrivalTime,
          locationStop.openingHoursWeekdayText,
        );
    bool departureOutside =
        !_isTimeWithinOpeningHours(
          scheduledStop.departureTime,
          locationStop.openingHoursWeekdayText,
        );

    if (arrivalOutside && departureOutside) {
      return "Arrival & Departure outside business hours";
    }
    if (arrivalOutside) return "Arrival outside business hours";
    if (departureOutside) return "Departure outside business hours";
    return "";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Planner'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.layers), // Icon for map style selection
            tooltip: "Select Map Style",
            initialValue: _selectedMapStyleName,
            onSelected: _selectMapStyle,
            itemBuilder: (BuildContext context) {
              return map_styles.availableMapStyles.keys.map((String styleName) {
                return PopupMenuItem<String>(
                  value: styleName,
                  child: Text(styleName),
                );
              }).toList();
            },
          ),
        ],
      ),
      body:
          ResponsiveBreakpoints.of(context).isDesktop
              ? _buildDesktopLayout()
              : _buildMobileLayout(),
    );
  }

  Widget _buildMobileLayout() {
    Widget draggableSheet = DraggableScrollableSheet(
      initialChildSize: 0.4,
      minChildSize: 0.2,
      maxChildSize: 0.9,
      builder: (BuildContext context, ScrollController scrollController) {
        return TripSheetContent(
          isSheetMode: true,
          scrollController: scrollController,
          tripStartTime: tripStartTime,
          onTripStartTimeChanged: (newTime) {
            setState(() {
              tripStartTime = newTime;
              // Recalculate routes if the first stop doesn't have a manual arrival time
              if (stops.isNotEmpty && stops.first.manualArrivalTime == null) {
                _calculateRoutes();
              }
            });
          },
          searchController: _searchController,
          placePredictions: _placePredictions,
          onPlaceSelected: (placeId) => _getPlaceDetails(placeId),
          isPickingNewStopOnMap: _isPickingNewStopOnMap,
          onTogglePickNewStopOnMap: () {
            setState(() {
              if (_isPickingNewStopOnMap) {
                _isPickingNewStopOnMap = false;
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              } else {
                _isPickingNewStopOnMap = true;
                _pickingDepartureOnMapForStopId = null;
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Long-press on the map to add a new stop.'),
                  ),
                );
              }
            });
          },
          stops: stops,
          tileControllers: _tileControllers,
          expandedStopId: _expandedStopId,
          onExpansionChanged: (stopId, expanded) {
            setState(() {
              if (expanded) {
                String? oldExpandedStopId = _expandedStopId;
                _expandedStopId = stopId;
                if (oldExpandedStopId != null && oldExpandedStopId != stopId) {
                  _tileControllers[oldExpandedStopId]?.collapse();
                }
              } else {
                if (_expandedStopId == stopId) {
                  _expandedStopId = null;
                }
              }
              _updateMapPolylines();
            });
          },
          getStopScheduleSummary: _getStopScheduleSummary,
          getTravelModeIcon: MapDisplayHelpers.getTravelModeIcon,
          routes: routes,
          selectedRouteIndices: selectedRouteIndices,
          onStopActionSelected: (action, stopId, index, buildContext) {
            // buildContext is passed from StopListItem for _pickDateTime
            _handleStopAction(action, stopId, index, buildContext);
          },
          updateTravelMode: _updateTravelMode,
          updateStopDuration: _updateStopDuration,
          computeScheduleDetails: _computeScheduleDetails,
          updatePolylinesForSegment: _updatePolylinesForSegment,
          buildStepList: _buildStepList,
          onReorder: _onReorder,
          getTransitRouteSummaryFunction: _getTransitRouteSummary,
          getManeuverIconDataFunction: MapDisplayHelpers.getManeuverIconData,
          getTransitVehicleIconFunction:
              MapDisplayHelpers.getTransitVehicleIcon,
          stripHtmlFunction: MapDisplayHelpers.stripHtmlIfNeeded,
          minStopDuration: _minStopDuration,
          maxStopDuration: _maxStopDuration,
          durationStep: _durationStep,
          getStopOpeningHoursWarningFunction: _getStopOpeningHoursWarning,
          onSaveTrip: _saveTripToFirestore,
          // --- Pass saved trips data and callbacks ---
          onUpdateStopNotes: _updateStopNotes,
          savedTrips: _savedTrips,
          isLoadingSavedTrips: _isLoadingSavedTrips,
          onLoadTrip: _loadTrip,
          onDeleteTrip: _deleteTripFromFirestore,
          // --- Pass participant data and callbacks ---
          participantUserDetails: _participantUserDetails,
          onAddParticipant: _showAddParticipantDialog,
          onRemoveParticipant: _removeParticipant,
          isLoadingParticipants: _isLoadingParticipants,
          tripOwnerId: _tripOwnerId,
        );
      },
    );

    if (kIsWeb) {
      draggableSheet = PointerInterceptor(child: draggableSheet);
    }

    return Stack(
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.move,
          child: GoogleMap(
            mapType:
                _selectedMapStyleName == map_styles.styleSatelliteName
                    ? MapType.satellite
                    : MapType.normal,
            initialCameraPosition: CameraPosition(
              target: _currentPosition,
              zoom: 14.0,
            ),
            onMapCreated: _onGoogleMapCreated,
            onLongPress: _onMapLongPress,
            markers: _markers.union(
              _routeLabelMarkers,
            ), // Combine stop markers and route labels
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true,
            compassEnabled: true,
          ),
        ),
        if (isLoading) const Center(child: CircularProgressIndicator()),
        draggableSheet,
      ],
    );
  }

  Widget _buildDesktopLayout() {
    Widget sidePanel = SizedBox(
      width: 450, // Width for the side panel
      child: Card(
        elevation: 4.0,
        margin:
            EdgeInsets
                .zero, // Ensure the card's visual boundary fills the SizedBox
        clipBehavior:
            Clip.antiAlias, // Ensures content respects card's rounded corners
        child: _buildTripSheetContentForDesktop(),
      ),
    );

    if (kIsWeb) {
      sidePanel = PointerInterceptor(child: sidePanel);
    }

    return Stack(
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.move,
          child: GoogleMap(
            mapType:
                _selectedMapStyleName == map_styles.styleSatelliteName
                    ? MapType.satellite
                    : MapType.normal,
            initialCameraPosition: CameraPosition(
              target: _currentPosition,
              zoom: 14.0,
            ),
            onMapCreated: _onGoogleMapCreated,
            onLongPress: _onMapLongPress,
            markers: _markers.union(_routeLabelMarkers),
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true, // Keep zoom controls on the map
            compassEnabled: true,
          ),
        ),
        if (isLoading)
          const Center(
            child: CircularProgressIndicator(),
          ), // Keep loading indicator on top
        Positioned(top: 8.0, right: 8.0, bottom: 8.0, child: sidePanel),
      ],
    );
  }

  void _handleStopAction(
    StopAction action,
    String stopId,
    int index,
    BuildContext itemContext,
  ) {
    switch (action) {
      case StopAction.editManualArrival:
        _pickDateTime(
          itemContext,
          initialDate: _getInitialPickerDateTimeForArrival(index),
          onDateTimePicked: (pickedDateTime) {
            _setManualArrivalTime(stopId, pickedDateTime);
          },
        );
        break;
      case StopAction.clearManualArrival:
        _setManualArrivalTime(stopId, null);
        break;
      case StopAction.editManualDeparture:
        _pickDateTime(
          itemContext,
          initialDate: _getInitialPickerDateTimeForDeparture(index),
          onDateTimePicked: (pickedDateTime) {
            _setManualDepartureTime(stopId, pickedDateTime);
          },
        );
        break;
      case StopAction.clearManualDeparture:
        _setManualDepartureTime(stopId, null);
        break;
      case StopAction.editDepartureLocation:
        setState(() {
          _pickingDepartureOnMapForStopId = null;
          _resetDepartureSessionToken();
        });
        final stop = stops.firstWhere((s) => s.id == stopId);
        _showDepartureSearchDialog(
          context, // Use the main context for the dialog
          stop.id,
          stop.name,
        );
        break;
      case StopAction.pickDepartureOnMap:
        setState(() {
          _isPickingNewStopOnMap = false;
          _pickingDepartureOnMapForStopId = stopId;
        });
        final stop = stops.firstWhere((s) => s.id == stopId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Long-press on the map to set departure for ${stop.name}',
            ),
          ),
        );
        break;
      case StopAction.resetDepartureToArrival:
        _clearDepartureForStop(stopId);
        break;
      case StopAction.removeStop:
        _removeStop(stopId);
        break;
    }
  }

  Future<void> _saveTripToFirestore() async {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to save trips.')),
        );
      }
      return;
    }

    if (stops.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add some stops before saving.')),
        );
      }
      return;
    }

    // Ensure the current user (owner) is always in the participant list when saving
    if (!_participantUserIds.contains(currentUser.uid)) {
      _participantUserIds.add(currentUser.uid);
      // Details will be fetched on next load or if _fetchParticipantDetails is called after this.
    }

    String? tripName;
    if (mounted) {
      final TextEditingController tripNameController = TextEditingController(
        text: _initialTripName,
      ); // Pre-fill if editing
      tripName = await showDialog<String>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Save Trip'),
            content: TextField(
              controller: tripNameController,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Enter trip name'),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              TextButton(
                child: const Text('Save'),
                onPressed:
                    () => Navigator.of(
                      dialogContext,
                    ).pop(tripNameController.text),
              ),
            ],
          );
        },
      );
    }

    if (tripName == null || tripName.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trip not saved. Name is required.')),
        );
      }
      return;
    }

    // Calculate trip end time
    final List<ScheduledStopInfo> schedule = _computeScheduleDetails();
    DateTime? calculatedEndTime;
    if (schedule.isNotEmpty) {
      calculatedEndTime = schedule.last.departureTime;
    }

    final tripData = {
      'userId': currentUser.uid,
      'tripName': tripName.trim(),
      'tripStartTime': Timestamp.fromDate(tripStartTime),
      'stops': stops.map((stop) => stop.toJson()).toList(),
      'selectedRouteIndices': selectedRouteIndices,
      'participantUserIds': _participantUserIds, // Save participant UIDs
      'endTime':
          calculatedEndTime != null
              ? Timestamp.fromDate(calculatedEndTime)
              : null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      if (_editingTripId != null) {
        // Update existing trip
        await FirebaseFirestore.instance
            .collection('trips')
            .doc(_editingTripId)
            .set(
              tripData,
              SetOptions(merge: true),
            ); // Use set to overwrite, or update for specific fields
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Trip "$tripName" updated successfully!')),
          );
        }
      } else {
        // Add new trip
        final newDocRef = await FirebaseFirestore.instance
            .collection('trips')
            .add(tripData);
        if (mounted) {
          setState(() {
            _editingTripId = newDocRef.id; // Store new ID for subsequent saves
            _initialTripName = tripName!.trim(); // Update initial name
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Trip "$tripName" saved successfully!')),
          );
        }
      }
      if (mounted) {
        // Refresh the list of saved trips after saving
        _fetchSavedTrips();
        await _fetchParticipantDetails(); // Refresh participant details display
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving trip: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save trip: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _fetchSavedTrips() async {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (mounted) setState(() => _savedTrips = []);
      return;
    }

    if (mounted) setState(() => _isLoadingSavedTrips = true);

    try {
      final querySnapshot =
          await FirebaseFirestore.instance
              .collection('trips')
              .where('userId', isEqualTo: currentUser.uid)
              .orderBy('createdAt', descending: true)
              .get();

      final List<Map<String, dynamic>> fetchedTrips =
          querySnapshot.docs.map((doc) {
            return {'id': doc.id, 'data': doc.data()};
          }).toList();

      if (mounted) {
        setState(() {
          _savedTrips = fetchedTrips;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error fetching saved trips: $e");
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching saved trips: ${e.toString()}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingSavedTrips = false);
    }
  }

  Future<void> _loadTrip(
    Map<String, dynamic> tripData,
    String tripDocId,
  ) async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
      // Clear current plan
      stops.clear();
      _tileControllers.clear();
      routes.clear();
      selectedRouteIndices.clear();
      _polylines.clear();
      _markers.clear();
      _routeLabelMarkers.clear();
      _expandedStopId = null;
      _participantUserIds.clear(); // Clear participants
      _participantUserDetails.clear(); // Clear participant details

      _editingTripId = tripDocId; // Set the ID of the trip being "edited"
      _initialTripName = tripData['tripName'] as String? ?? 'Unnamed Trip';
      tripStartTime = (tripData['tripStartTime'] as Timestamp).toDate();

      final List<dynamic> stopsData = tripData['stops'] as List<dynamic>? ?? [];
      for (var stopMap in stopsData) {
        final stop = LocationStop.fromJson(stopMap as Map<String, dynamic>);
        stops.add(stop);
        _tileControllers[stop.id] = ExpansionTileController();
      }

      selectedRouteIndices = Map<String, int>.from(
        tripData['selectedRouteIndices'] as Map<dynamic, dynamic>? ?? {},
      );

      _participantUserIds =
          (tripData['participantUserIds'] as List<dynamic>?)?.cast<String>() ??
          []; // Load participant UIDs
      await _fetchParticipantDetails(); // Fetch details for loaded UIDs
      await _triggerRouteAndMarkerUpdates(); // This will recalculate routes and update map
    } catch (e) {
      if (kDebugMode) {
        print("Error during _loadTrip: $e");
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading trip: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _fetchParticipantDetails() async {
    if (_participantUserIds.isEmpty) {
      if (mounted) {
        setState(() {
          _participantUserDetails = [];
          _isLoadingParticipants = false;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _isLoadingParticipants = true);

    List<Map<String, String>> userDetailsList = [];
    try {
      for (String userId in _participantUserIds) {
        // Avoid re-fetching if details already exist (simple check)
        if (_participantUserDetails.any((detail) => detail['id'] == userId)) {
          final existingDetail = _participantUserDetails.firstWhere(
            (detail) => detail['id'] == userId,
          );
          userDetailsList.add(existingDetail);
          continue;
        }
        final docSnapshot =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .get();
        if (docSnapshot.exists && docSnapshot.data() != null) {
          final data = docSnapshot.data()!;
          userDetailsList.add({
            'id': userId,
            'email': data['email'] as String? ?? 'N/A',
            'displayName':
                data['displayName'] as String? ??
                (data['email'] as String? ??
                    'User...${userId.substring(userId.length - 4)}'),
          });
        } else {
          userDetailsList.add({
            'id': userId,
            'email': 'Unknown User',
            'displayName': 'Unknown User',
          });
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error fetching participant details: $e");
      }
    }

    if (mounted) {
      setState(() {
        _participantUserDetails = userDetailsList;
        _isLoadingParticipants = false;
      });
    }
  }

  Future<void> _showAddParticipantDialog() async {
    if (!mounted) return;
    final TextEditingController emailController = TextEditingController();
    List<Map<String, String>> searchResults = [];
    bool searching = false;
    String? searchError;

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> searchUsersByEmail(String email) async {
              if (email.trim().isEmpty) {
                setDialogState(() {
                  searchResults = [];
                  searchError = null;
                });
                return;
              }
              setDialogState(() {
                searching = true;
                searchError = null;
              });
              try {
                final querySnapshot =
                    await FirebaseFirestore.instance
                        .collection('users')
                        .where('email', isEqualTo: email.trim().toLowerCase())
                        .limit(5)
                        .get();

                List<Map<String, String>> newResults = [];
                final currentAuthUser = FirebaseAuth.instance.currentUser;

                for (var doc in querySnapshot.docs) {
                  if (doc.exists) {
                    final data = doc.data();
                    // Exclude already added participants and the current trip owner
                    if (!_participantUserIds.contains(doc.id) &&
                        (currentAuthUser == null ||
                            currentAuthUser.uid != doc.id)) {
                      newResults.add({
                        'id': doc.id,
                        'email': data['email'] as String? ?? 'N/A',
                        'displayName':
                            data['displayName'] as String? ??
                            (data['email'] as String? ??
                                'User...${doc.id.substring(doc.id.length - 4)}'),
                      });
                    }
                  }
                }
                setDialogState(() {
                  searchResults = newResults;
                  if (newResults.isEmpty && email.trim().isNotEmpty) {
                    searchError =
                        "No new users found with that email, or user is already owner/participant.";
                  }
                });
              } catch (e) {
                setDialogState(() => searchError = "Error: ${e.toString()}");
              } finally {
                setDialogState(() => searching = false);
              }
            }

            return AlertDialog(
              title: const Text('Add Participant by Email'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: emailController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Enter user email',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search),
                          onPressed:
                              () => searchUsersByEmail(emailController.text),
                        ),
                      ),
                      onSubmitted: (value) => searchUsersByEmail(value),
                    ),
                    if (searching)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(),
                      ),
                    if (searchError != null)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          searchError!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (searchResults.isNotEmpty)
                      Expanded(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: searchResults.length,
                          itemBuilder: (context, index) {
                            final user = searchResults[index];
                            return ListTile(
                              title: Text(
                                user['displayName'] ?? user['email']!,
                              ),
                              subtitle: Text(user['email']!),
                              onTap: () {
                                if (mounted) {
                                  setState(() {
                                    if (!_participantUserIds.contains(
                                      user['id']!,
                                    )) {
                                      _participantUserIds.add(user['id']!);
                                      _participantUserDetails.add(user);
                                    }
                                  });
                                }
                                Navigator.of(dialogContext).pop();
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showDepartureSearchDialog(
    BuildContext dialogContext,
    String stopId,
    String stopName,
  ) async {
    _resetDepartureSessionToken(); // Ensure a fresh session for the dialog
    // Capture the current session token to pass to the dialog
    final String dialogSessionToken = _departureSessionToken;

    await showDialog(
      context: dialogContext,
      builder: (BuildContext context) {
        return DepartureSearchDialogContent(
          stopId: stopId,
          stopName: stopName,
          // apiKey: _apiKey, // No longer needed, API key is in CF
          initialSessionToken: dialogSessionToken,
          fetchPredictionsCallback:
              (input, sessionToken) =>
                  _fetchPlacePredictionsApi(input, sessionToken),
          onPlaceSelected: (String placeId) {
            _getPlaceDetails(placeId, stopIdToUpdateDeparture: stopId);
            // _getPlaceDetails will call _resetDepartureSessionToken
          },
          onDialogDismissedWithoutSelection: _resetDepartureSessionToken,
        );
      },
    );
  }

  Future<void> _deleteTripFromFirestore(String tripDocId) async {
    final confirmDelete = await showDialog<bool>(
      context: context,
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: const Text('Delete Trip?'),
            content: const Text(
              'Are you sure you want to delete this saved trip? This action cannot be undone.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(
                  'Delete',
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),
            ],
          ),
    );

    if (confirmDelete == true) {
      try {
        await FirebaseFirestore.instance
            .collection('trips')
            .doc(tripDocId)
            .delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Trip deleted successfully.')),
          );
          _fetchSavedTrips(); // Refresh the list
        }
      } catch (e) {
        if (kDebugMode) {
          print("Error deleting trip: $e");
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete trip: ${e.toString()}')),
          );
        }
      }
    }
  }

  void _removeParticipant(String userId) {
    if (!mounted) return;
    final currentUser = FirebaseAuth.instance.currentUser;
    // Prevent owner from being removed
    if (currentUser != null && userId == currentUser.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Trip owner cannot be removed from participants list."),
        ),
      );
      return;
    }
    setState(() {
      _participantUserIds.remove(userId);
      _participantUserDetails.removeWhere((detail) => detail['id'] == userId);
    });
  }

  Widget _buildTripSheetContentForDesktop() {
    // For desktop, TripSheetContent manages its own scrolling if its content overflows the Card.
    // No external scrollController from DraggableScrollableSheet is provided.
    return TripSheetContent(
      isSheetMode:
          false, // Crucial: informs TripSheetContent it's not in a sheet
      // scrollController: _desktopScrollController, // Only if you need to control it from here
      tripStartTime: tripStartTime,
      onTripStartTimeChanged: (newTime) {
        setState(() {
          tripStartTime = newTime;
          if (stops.isNotEmpty && stops.first.manualArrivalTime == null) {
            _calculateRoutes();
          }
        });
      },
      searchController: _searchController,
      placePredictions: _placePredictions,
      onPlaceSelected: (placeId) => _getPlaceDetails(placeId),
      isPickingNewStopOnMap: _isPickingNewStopOnMap,
      onTogglePickNewStopOnMap: () {
        /* ... same as mobile ... */
      },
      stops: stops,
      tileControllers: _tileControllers,
      expandedStopId: _expandedStopId,
      onExpansionChanged: (stopId, expanded) {
        /* ... same as mobile ... */
      },
      getStopScheduleSummary: _getStopScheduleSummary,
      getTravelModeIcon: MapDisplayHelpers.getTravelModeIcon,
      routes: routes,
      selectedRouteIndices: selectedRouteIndices,
      onStopActionSelected: (action, stopId, index, buildContext) {
        _handleStopAction(action, stopId, index, buildContext);
      },
      updateTravelMode: _updateTravelMode,
      updateStopDuration: _updateStopDuration,
      computeScheduleDetails: _computeScheduleDetails,
      updatePolylinesForSegment: _updatePolylinesForSegment,
      buildStepList: _buildStepList,
      onReorder: _onReorder,
      getTransitRouteSummaryFunction: _getTransitRouteSummary,
      getManeuverIconDataFunction: MapDisplayHelpers.getManeuverIconData,
      getTransitVehicleIconFunction: MapDisplayHelpers.getTransitVehicleIcon,
      stripHtmlFunction: MapDisplayHelpers.stripHtmlIfNeeded,
      minStopDuration: _minStopDuration,
      maxStopDuration: _maxStopDuration,
      durationStep: _durationStep,
      getStopOpeningHoursWarningFunction: _getStopOpeningHoursWarning,
      onSaveTrip: _saveTripToFirestore, // Pass the save function
      // --- Pass saved trips data and callbacks ---
      onUpdateStopNotes: _updateStopNotes,
      savedTrips: _savedTrips,
      isLoadingSavedTrips: _isLoadingSavedTrips,
      onLoadTrip: _loadTrip,
      onDeleteTrip: _deleteTripFromFirestore,
      // --- Pass participant data and callbacks ---
      participantUserDetails: _participantUserDetails,
      onAddParticipant: _showAddParticipantDialog,
      onRemoveParticipant: _removeParticipant,
      isLoadingParticipants: _isLoadingParticipants,
      tripOwnerId: _tripOwnerId,
    );
  }

  Widget _buildStepList(List<dynamic> steps) {
    return DirectionsList(
      steps: steps,
      getManeuverIconData: MapDisplayHelpers.getManeuverIconData,
      getTransitVehicleIcon: MapDisplayHelpers.getTransitVehicleIcon,
      stripHtmlIfNeeded: MapDisplayHelpers.stripHtmlIfNeeded,
      primaryColor:
          Theme.of(
            context,
          ).colorScheme.inversePrimary, // Pass theme dependent color
    );
  }
}
