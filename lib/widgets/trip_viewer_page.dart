import 'dart:async';
import 'dart:ui' as ui;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math'; // Added for pi, sin, cos
import 'package:flutter/foundation.dart' show ByteData, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:route_force/models/location_stop.dart';
import 'package:route_force/models/route_info.dart';
import 'package:route_force/models/scheduled_stop_info.dart';
import 'package:route_force/models/trip.dart';
import 'package:route_force/widgets/directions_list.dart';
import 'package:route_force/enums/travel_mode.dart' as travel_mode_enum;
import 'package:route_force/utils/map_display_helpers.dart';
import 'package:route_force/map_styles/map_style_definitions.dart'
    as map_styles;

class TripViewerPage extends StatefulWidget {
  final Trip trip;

  const TripViewerPage({super.key, required this.trip});

  @override
  State<TripViewerPage> createState() => _TripViewerPageState();
}

class _TripViewerPageState extends State<TripViewerPage> {
  GoogleMapController? _mapController;
  late List<LocationStop> _stops;
  late DateTime _tripStartTime;
  Map<String, RouteInfo> _routes = {}; // routeId to a single selected RouteInfo
  late Map<String, int> _selectedRouteIndices;

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  List<ScheduledStopInfo> _scheduleDetails = [];
  bool _isLoading = true;

  // API Key will be handled by Firebase Functions
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  String _selectedMapStyleName = map_styles.styleStandardName;
  final Map<String, BitmapDescriptor> _markerIconCache = {};
  final Set<Marker> _routeLabelMarkers = {};
  Map<String, ExpansionTileController> _tileControllers = {};
  String? _expandedStopId;

  // --- State for Participants ---
  List<Map<String, String>> _participantUserDetails = [];
  bool _isLoadingParticipants = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _loadUserPreferences(); // Load preferences first
      await _loadTripData(); // Then load trip data which might use map
    });
  }

  Future<void> _loadTripData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _stops = widget.trip.stops.map((s) => s.copyWith()).toList(); // Deep copy
      _tripStartTime = widget.trip.date;
      _selectedRouteIndices = Map<String, int>.from(
        widget.trip.selectedRouteIndices,
      );
      _tileControllers = {
        for (var stop in _stops) stop.id: ExpansionTileController(),
      };
    });

    try {
      await _initializePageData();
      await _fetchParticipantDetails(); // Fetch participant details
    } catch (e, s) {
      if (kDebugMode) {
        print("Error during trip data initialization: $e\n$s");
      }
      if (mounted) {
        // Optionally, set an error state here to display a message to the user
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _initializePageData() async {
    // Calculate routes and schedule first, as markers might depend on schedule info
    await _calculateAndDisplayRoutes();
    // Then update markers
    await _updateMarkers();
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
                });
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print(
            "Error loading user map style preference in TripViewerPage: $e",
          );
        }
      }
    }
  }

  Future<void> _onGoogleMapCreated(GoogleMapController controller) async {
    _mapController = controller;
    try {
      if (!mounted) return;
      final initialStyleJson =
          map_styles.availableMapStyles[_selectedMapStyleName];
      await _mapController?.setMapStyle(initialStyleJson);
      if (_stops.isNotEmpty && _mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(
            _calculateBounds(_stops.map((s) => s.position).toList()),
            50.0, // Padding
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error applying initial map style onMapCreated: $e");
      }
    }
  }

  LatLngBounds _calculateBounds(List<LatLng> points) {
    if (points.isEmpty) {
      return LatLngBounds(
        southwest: const LatLng(0, 0),
        northeast: const LatLng(0, 0),
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

  Future<void> _applySelectedStyleToMap() async {
    if (_mapController == null) return;
    try {
      if (_selectedMapStyleName == map_styles.styleSatelliteName) {
        await _mapController!.setMapStyle(null); // Clears JSON style
        // MapType change will be handled by widget rebuild if necessary
      } else {
        await _mapController!.setMapStyle(
          map_styles.availableMapStyles[_selectedMapStyleName],
        );
      }
      if (kDebugMode) {
        print(
          "Applied style '$_selectedMapStyleName' to map in TripViewerPage.",
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print(
          "Error applying style '$_selectedMapStyleName' to map in TripViewerPage: $e",
        );
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

  Future<void> _selectMapStyle(String styleName) async {
    if (styleName == _selectedMapStyleName ||
        !map_styles.availableMapStyles.containsKey(styleName)) {
      return;
    }
    final String oldStyle = _selectedMapStyleName;
    if (mounted) {
      setState(() {
        _selectedMapStyleName = styleName;
      });
    } else {
      return;
    }
    if (_mapController != null) {
      try {
        await _applySelectedStyleToMap(); // This uses the new _selectedMapStyleName

        final User? currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null && !currentUser.isAnonymous) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .set({'lastMapStyle': styleName}, SetOptions(merge: true));
        }
      } catch (e) {
        if (kDebugMode) {
          print("Error applying map style $styleName: $e");
        }
        if (mounted) {
          setState(() => _selectedMapStyleName = oldStyle); // Revert
          await _applySelectedStyleToMap(); // Re-apply old style
        }
      }
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
    final String cacheKey = "viewer-$number-${color.value}";
    if (_markerIconCache.containsKey(cacheKey)) {
      return _markerIconCache[cacheKey]!;
    }

    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    const double canvasWidth = 60.0;
    const double canvasHeight = 75.0;
    const double circleRadius = canvasWidth / 2.5;
    const double circleCenterY = circleRadius + 2;
    const double circleCenterX = canvasWidth / 2;

    final Paint pinPaint = Paint()..color = color;
    canvas.drawCircle(
      Offset(circleCenterX, circleCenterY),
      circleRadius,
      pinPaint,
    );

    final Path triangle =
        Path()
          ..moveTo(
            circleCenterX - circleRadius / 2.5,
            circleCenterY + circleRadius / 1.5,
          )
          ..lineTo(
            circleCenterX + circleRadius / 2.5,
            circleCenterY + circleRadius / 1.5,
          )
          ..lineTo(circleCenterX, canvasHeight)
          ..close();
    canvas.drawPath(triangle, pinPaint);

    final TextPainter textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    );
    final String text = number.toString();
    textPainter.text = TextSpan(
      text: text,
      style: TextStyle(
        fontSize: circleRadius * (text.length > 1 ? 0.7 : 0.9),
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
      ),
    );

    final ui.Image image = await pictureRecorder.endRecording().toImage(
      canvasWidth.toInt(),
      canvasHeight.toInt(),
    );
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );

    if (byteData == null) return BitmapDescriptor.defaultMarker;

    final BitmapDescriptor descriptor = BitmapDescriptor.fromBytes(
      byteData.buffer.asUint8List(),
    );
    _markerIconCache[cacheKey] = descriptor;
    return descriptor;
  }

  Future<void> _updateMarkers() async {
    if (!mounted) return;
    Set<Marker> newMarkers = {};
    List<Future<Marker>> markerFutures = [];
    final Set<LatLng> finalMarkerDisplayPositions =
        {}; // Tracks actual LatLngs used on map
    final Map<LatLng, int> originalPositionReferences =
        {}; // Tracks how many markers originate from the same LatLng

    final Color markerColor = Theme.of(context).colorScheme.inversePrimary;

    for (int i = 0; i < _stops.length; i++) {
      final stop = _stops[i];

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

      final Future<BitmapDescriptor> iconFuture = _createNumberedMarkerIcon(
        i + 1,
        markerColor,
      );
      markerFutures.add(
        iconFuture.then((icon) {
          return Marker(
            markerId: MarkerId(stop.id),
            position: displayArrivalPos, // Use potentially adjusted position
            icon: icon,
            anchor: const Offset(0.5, 1.0),
            infoWindow: InfoWindow(
              title: '${stop.name} (Stop ${i + 1})',
              snippet: _getStopScheduleSummary(i),
            ),
            zIndex: 1.0,
          );
        }),
      );

      // --- Departure Marker (if distinct) ---
      if (stop.departurePosition != null &&
          stop.departurePosition != stop.position) {
        final LatLng originalDeparturePos = stop.effectiveDeparturePosition;
        final int departureInstanceNum =
            (originalPositionReferences[originalDeparturePos] ?? 0) + 1;
        originalPositionReferences[originalDeparturePos] = departureInstanceNum;

        final LatLng displayDeparturePos = _getAdjustedMarkerPosition(
          originalDeparturePos,
          departureInstanceNum,
          pi / 6.0, // Slightly different angle seed for departures
          finalMarkerDisplayPositions,
        );
        finalMarkerDisplayPositions.add(displayDeparturePos);

        final Future<BitmapDescriptor> departureIconFuture =
            _createNumberedMarkerIcon(i + 1, Colors.orange.shade700);
        markerFutures.add(
          departureIconFuture.then((icon) {
            return Marker(
              markerId: MarkerId('${stop.id}_departure_viewer'),
              position:
                  displayDeparturePos, // Use potentially adjusted position
              icon: icon,
              anchor: const Offset(0.5, 1.0),
              infoWindow: InfoWindow(
                title:
                    'Departure for ${stop.name}: ${stop.effectiveDepartureName}',
              ),
              zIndex: 0.5,
            );
          }),
        );
      }
    }

    final List<Marker> resolvedMarkers = await Future.wait(markerFutures);
    newMarkers.addAll(resolvedMarkers);

    if (mounted) {
      setState(() {
        _markers = newMarkers;
      });
    }
  }

  Future<void> _calculateAndDisplayRoutes() async {
    if (_stops.length < 2) {
      if (mounted) {
        setState(() {
          _routes.clear();
          _polylines.clear();
          _routeLabelMarkers.clear();
          _scheduleDetails = _computeScheduleDetails();
        });
      }
      return;
    }

    Map<String, RouteInfo> newRoutes = {};
    Set<Polyline> newPolylines = {};
    final List<Color> baseRouteColors = [
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.purple,
      Colors.orange,
    ];

    DateTime currentExpectedArrivalTimeForNextStop = _tripStartTime;
    if (_stops.isNotEmpty && _stops.first.manualArrivalTime != null) {
      currentExpectedArrivalTimeForNextStop = _stops.first.manualArrivalTime!;
    }

    for (int i = 0; i < _stops.length - 1; i++) {
      final currentStop = _stops[i];
      final nextStop = _stops[i + 1];
      final routeId = '${currentStop.id}-${nextStop.id}';

      DateTime actualArrivalTimeAtCurrentStop;
      if (currentStop.manualArrivalTime != null) {
        actualArrivalTimeAtCurrentStop = currentStop.manualArrivalTime!;
      } else {
        actualArrivalTimeAtCurrentStop = currentExpectedArrivalTimeForNextStop;
      }

      DateTime departureTimeForThisSegment;
      if (currentStop.manualDepartureTime != null) {
        departureTimeForThisSegment = currentStop.manualDepartureTime!;
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

      final List<RouteInfo>? routeOptions = await _getDirections(
        currentStop.effectiveDeparturePosition,
        nextStop.position,
        nextStop.travelMode, // Travel mode TO nextStop
        departureTime: departureTimeForThisSegment,
      );

      if (routeOptions != null && routeOptions.isNotEmpty) {
        int selectedIdx = _selectedRouteIndices[routeId] ?? 0;
        if (selectedIdx >= routeOptions.length) selectedIdx = 0;

        final selectedRoute = routeOptions[selectedIdx];
        newRoutes[routeId] = selectedRoute;

        newPolylines.add(
          Polyline(
            polylineId: PolylineId(routeId),
            points: selectedRoute.polylinePoints,
            color: baseRouteColors[i % baseRouteColors.length],
            width: 5,
          ),
        );
        currentExpectedArrivalTimeForNextStop = departureTimeForThisSegment.add(
          Duration(minutes: _parseDurationString(selectedRoute.duration)),
        );
      } else {
        currentExpectedArrivalTimeForNextStop = departureTimeForThisSegment;
      }
    }

    if (mounted) {
      setState(() {
        _routes = newRoutes;
        _polylines = newPolylines;
        _scheduleDetails = _computeScheduleDetails();
      });
    }
  }

  List<ScheduledStopInfo> _computeScheduleDetails() {
    if (_stops.isEmpty) return [];
    List<ScheduledStopInfo> schedule = [];
    DateTime currentExpectedArrivalTime = _tripStartTime;

    for (int i = 0; i < _stops.length; i++) {
      final stop = _stops[i];
      DateTime actualArrivalTime;
      bool arrivalIsManual = false;
      String? travelTimeText;

      if (stop.manualArrivalTime != null) {
        actualArrivalTime = stop.manualArrivalTime!;
        arrivalIsManual = true;
      } else {
        actualArrivalTime = currentExpectedArrivalTime;
      }

      if (i > 0) {
        final prevStop = _stops[i - 1];
        final routeId = '${prevStop.id}-${stop.id}';
        if (_routes.containsKey(routeId)) {
          travelTimeText = _routes[routeId]!.duration;
        }
      }

      DateTime actualDepartureTime;
      bool departureIsManual = false;
      if (stop.manualDepartureTime != null) {
        actualDepartureTime = stop.manualDepartureTime!;
        departureIsManual = true;
        if (actualDepartureTime.isBefore(actualArrivalTime)) {
          actualDepartureTime = actualArrivalTime.add(
            Duration(minutes: stop.durationMinutes),
          );
          departureIsManual = false;
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

      if (i < _stops.length - 1) {
        final nextStop = _stops[i + 1];
        final routeId = '${stop.id}-${nextStop.id}';
        if (_routes.containsKey(routeId)) {
          currentExpectedArrivalTime = actualDepartureTime.add(
            Duration(minutes: _parseDurationString(_routes[routeId]!.duration)),
          );
        } else {
          currentExpectedArrivalTime = actualDepartureTime;
        }
      }
    }
    return schedule;
  }

  String _getStopScheduleSummary(int stopIndex) {
    if (stopIndex < 0 || stopIndex >= _scheduleDetails.length) {
      return 'Schedule N/A';
    }
    final scheduledStop = _scheduleDetails[stopIndex];
    String arrivalStr = DateFormat('h:mm a').format(scheduledStop.arrivalTime);
    String departureStr = DateFormat(
      'h:mm a',
    ).format(scheduledStop.departureTime);
    String arrivalSuffix = scheduledStop.isArrivalManual ? " (M)" : "";
    String departureSuffix = scheduledStop.isDepartureManual ? " (M)" : "";
    return 'Arrival: $arrivalStr$arrivalSuffix | Depart: $departureStr$departureSuffix';
  }

  // --- Helper methods copied/adapted from TripPlannerApp ---
  // (Include _getDirections, _parseDurationString, _formatDurationFromSecondsString,
  // _formatDistanceMeters, _getTravelModeIcon, _getManeuverIconData,
  // _getTransitVehicleIcon, _stripHtmlIfNeeded, _buildStepList)

  Future<List<RouteInfo>?> _getDirections(
    LatLng origin,
    LatLng destination,
    travel_mode_enum.TravelMode mode, {
    DateTime? departureTime,
  }) async {
    String travelModeStr;
    // Ensure travelModeStr matches what the Cloud Function expects
    switch (mode) {
      case travel_mode_enum.TravelMode.driving:
        travelModeStr = 'DRIVE'; // Matches CF
        break;
      case travel_mode_enum.TravelMode.walking:
        travelModeStr = 'WALK'; // Matches CF
        break;
      case travel_mode_enum.TravelMode.bicycling:
        travelModeStr = 'BICYCLE'; // Matches CF
        break;
      case travel_mode_enum.TravelMode.transit:
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
            PolylinePoints polylinePoints = PolylinePoints();
            List<LatLng> polylineCoordinates = [];
            if (encodedPolyline != null) {
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
              'Directions Function (TripViewer): No routes found or unexpected response format.',
            );
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print(
          "Error calling getDirections Firebase Function (TripViewerPage): $e",
        );
      }
    }
    return null;
  }

  int _parseDurationString(String durationStr) {
    int travelMinutes = 0;
    final hourMatch = RegExp(
      r'(\d+)\s*hr',
    ).firstMatch(durationStr); // Adjusted regex
    final minMatch = RegExp(
      r'(\d+)\s*min',
    ).firstMatch(durationStr); // Adjusted regex

    if (hourMatch?.group(1) != null) {
      travelMinutes += int.parse(hourMatch!.group(1)!) * 60;
    }
    if (minMatch?.group(1) != null) {
      travelMinutes += int.parse(minMatch!.group(1)!);
    }
    return travelMinutes;
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
          ).colorScheme.inversePrimary, // Changed from highlightColor
    );
  }

  Future<void> _fetchParticipantDetails() async {
    if (widget.trip.participantUserIds.isEmpty) {
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
      for (String userId in widget.trip.participantUserIds) {
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
          // Fallback for users not found or if 'users' collection structure is different
          userDetailsList.add({
            'id': userId,
            'email': 'Unknown User',
            'displayName': 'User ID: ${userId.substring(0, 5)}...',
          });
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error fetching participant details in TripViewerPage: $e");
      }
      // Optionally, set an error state to display to the user
    }

    if (mounted) {
      setState(() {
        _participantUserDetails = userDetailsList;
        _isLoadingParticipants = false;
      });
    }
  }

  Widget _buildReadOnlyStopItem(BuildContext context, int index) {
    final stop = _stops[index];
    final scheduledInfo =
        (index < _scheduleDetails.length) ? _scheduleDetails[index] : null;
    final routeIdFromPrevious =
        (index > 0) ? '${_stops[index - 1].id}-${stop.id}' : null;
    final RouteInfo? routeToThisStop =
        (routeIdFromPrevious != null &&
                _routes.containsKey(routeIdFromPrevious))
            ? _routes[routeIdFromPrevious]
            : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ExpansionTile(
        key: ValueKey(stop.id), // Important for ExpansionTile state
        controller: _tileControllers[stop.id],
        initiallyExpanded: _expandedStopId == stop.id,
        onExpansionChanged: (expanded) {
          setState(() {
            if (expanded) {
              String? oldExpandedStopId = _expandedStopId;
              _expandedStopId = stop.id;
              if (oldExpandedStopId != null && oldExpandedStopId != stop.id) {
                _tileControllers[oldExpandedStopId]?.collapse();
              }
            } else {
              if (_expandedStopId == stop.id) _expandedStopId = null;
            }
          });
        },
        leading: CircleAvatar(child: Text('${index + 1}')),
        title: Text(
          stop.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (scheduledInfo != null) Text(_getStopScheduleSummary(index)),
            if (index > 0)
              Row(
                children: [
                  Icon(
                    MapDisplayHelpers.getTravelModeIcon(stop.travelMode),
                    size: 16,
                    color: Colors.grey[700],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    scheduledInfo?.travelDurationToThisStopText ??
                        '(Route info N/A)',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            if (stop.departurePosition != null &&
                stop.departurePosition != stop.position)
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: Text(
                  'Departs from: ${stop.effectiveDepartureName}',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            if (stop.notes != null && stop.notes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  'Notes: ${stop.notes}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        children:
            (routeToThisStop != null && routeToThisStop.steps.isNotEmpty)
                ? [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: _buildStepList(routeToThisStop.steps),
                  ),
                ]
                : [
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text("No directions available for this segment."),
                  ),
                ],
      ),
    );
  }

  Widget _buildDetailsPanel(
    BuildContext context, {
    ScrollController? scrollController,
  }) {
    Widget columnContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize:
          MainAxisSize
              .min, // Important for SingleChildScrollView wrapping a Column
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.trip.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Date: ${DateFormat('MMM dd, yyyy - h:mm a').format(_tripStartTime)}',
              ),
              if (widget.trip.description != null &&
                  widget.trip.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Description: ${widget.trip.description}'),
              ],
              // --- Updated Section for Participants ---
              if (_isLoadingParticipants) ...[
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Text('Participants: '),
                    SizedBox(width: 8),
                    SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ),
              ] else if (_participantUserDetails.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Participants:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8.0,
                  runSpacing: 4.0,
                  children:
                      _participantUserDetails.map((user) {
                        bool isOwner = user['id'] == widget.trip.userId;
                        return Chip(
                          avatar: CircleAvatar(
                            backgroundColor:
                                isOwner
                                    ? Theme.of(
                                      context,
                                    ).primaryColor.withAlpha(100)
                                    : null,
                            child: Text(
                              user['displayName']![0].toUpperCase(),
                              style: TextStyle(
                                color:
                                    isOwner
                                        ? Theme.of(context).primaryColorDark
                                        : null,
                              ),
                            ),
                          ),
                          label: Text(
                            user['displayName']! + (isOwner ? " (Owner)" : ""),
                          ),
                        );
                      }).toList(),
                ),
              ] else if (widget.trip.participantUserIds.isNotEmpty) ...[
                // Fallback if details couldn't be fetched
                const SizedBox(height: 8),
                Text(
                  'Participants: Could not load details.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Stops:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        _stops.isEmpty
            ? ListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: 48.0,
                    horizontal: 16.0,
                  ),
                  child: Center(child: Text('This trip has no stops.')),
                ),
              ],
            )
            : ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _stops.length,
              itemBuilder:
                  (context, index) => _buildReadOnlyStopItem(context, index),
            ),
      ],
    );

    return SingleChildScrollView(
      controller:
          scrollController, // Uses provided controller, or creates its own if null
      child: columnContent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveBreakpoints.of(context).isDesktop;

    final appBar = AppBar(
      title: Text('View Trip: ${widget.trip.name}'),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.layers),
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
    );

    if (_isLoading) {
      return Scaffold(
        appBar: appBar,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // If not loading, then _stops, _tripStartTime etc. are initialized.
    Widget mapWidget = GoogleMap(
      mapType:
          _selectedMapStyleName == map_styles.styleSatelliteName
              ? MapType.satellite
              : MapType.normal,
      initialCameraPosition: CameraPosition(
        target:
            _stops
                    .isNotEmpty // Now safe to access _stops
                ? _stops.first.position
                : const LatLng(
                  37.7749,
                  -122.4194,
                ), // Default if _stops is empty
        zoom: 12.0,
      ),
      onMapCreated: _onGoogleMapCreated,
      markers: _markers.union(_routeLabelMarkers),
      polylines: _polylines,
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      zoomControlsEnabled: true,
      compassEnabled: true,
    );
    if (kIsWeb) {
      // mapWidget = PointerInterceptor(child: mapWidget); // PointerInterceptor should be on the overlay, not the map itself.
    }

    Widget detailsPanelWidget = SizedBox(
      width: 450, // Keep the fixed width
      child: Card(
        elevation: 4.0,
        margin: EdgeInsets.zero, // Ensure card fills the SizedBox
        clipBehavior: Clip.antiAlias, // Clip content to card shape
        child: _buildDetailsPanel(context),
      ),
    );

    if (kIsWeb) {
      detailsPanelWidget = PointerInterceptor(child: detailsPanelWidget);
    }

    return Scaffold(
      appBar: appBar,
      body:
          isDesktop
              ? Stack(
                // Desktop layout
                children: [
                  mapWidget,
                  Positioned(
                    top: 8.0,
                    right: 8.0,
                    bottom: 8.0,
                    child: detailsPanelWidget,
                  ),
                ],
              )
              : Stack(
                // Mobile layout
                children: [
                  mapWidget,
                  DraggableScrollableSheet(
                    initialChildSize: 0.4,
                    minChildSize: 0.2,
                    maxChildSize: 0.9,
                    builder: (
                      BuildContext context,
                      ScrollController scrollController,
                    ) {
                      Widget sheetContent = Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withValues(alpha: 0.5),
                              spreadRadius: 3,
                              blurRadius: 5,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: _buildDetailsPanel(
                          context,
                          scrollController: scrollController,
                        ),
                      );
                      if (kIsWeb) {
                        return PointerInterceptor(child: sheetContent);
                      }
                      return sheetContent;
                    },
                  ),
                ],
              ),
    );
  }
}
