import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Import FirebaseAuth
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:route_force/models/trip.dart';
import 'package:route_force/widgets/trip_planner.dart';
import 'package:route_force/widgets/trip_viewer_page.dart'; // Import the new viewer page
import 'package:route_force/enums/travel_mode.dart'; // Import TravelMode
import 'package:route_force/widgets/account_page.dart'; // Import the AccountPage
// import 'package:route_force/constants/firestore_constants.dart'; // Assuming you create this file

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Trip> _upcomingTrips = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUpcomingTrips();
  }

  Future<void> _loadUpcomingTrips() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (mounted) {
        setState(() {
          _upcomingTrips = [];
          _isLoading = false;
          _error = "User not logged in.";
        });
      }
      return;
    }

    try {
      final now = DateTime.now();
      final todayStart = Timestamp.fromDate(
        DateTime(now.year, now.month, now.day),
      );

      // Query 1: Trips owned by the current user
      final ownedTripsQuery = FirebaseFirestore.instance
          .collection('trips')
          .where('userId', isEqualTo: currentUser.uid)
          .where('tripStartTime', isGreaterThanOrEqualTo: todayStart)
          .orderBy('tripStartTime', descending: false)
          .withConverter<Trip>(
            fromFirestore:
                (snapshots, options) => Trip.fromFirestore(snapshots, options),
            toFirestore: (trip, _) => trip.toFirestore(),
          );

      // Query 2: Trips where the current user is a participant
      final participantTripsQuery = FirebaseFirestore.instance
          .collection('trips')
          .where('participantUserIds', arrayContains: currentUser.uid)
          .where('tripStartTime', isGreaterThanOrEqualTo: todayStart)
          // Note: Firestore requires the orderBy field to be the first field
          // used in an inequality filter if there are multiple.
          // If 'tripStartTime' is not the first inequality, this might error.
          // However, since 'participantUserIds' is an array-contains (equality-like for this purpose)
          // and 'tripStartTime' is the inequality, this should be fine.
          // If issues arise, consider fetching all participant trips and then filtering by date client-side,
          // or restructuring data/queries.
          .orderBy('tripStartTime', descending: false)
          .withConverter<Trip>(
            fromFirestore:
                (snapshots, options) => Trip.fromFirestore(snapshots, options),
            toFirestore: (trip, _) => trip.toFirestore(),
          );

      final ownedTripsSnapshot = await ownedTripsQuery.get();
      final participantTripsSnapshot = await participantTripsQuery.get();

      final Set<String> tripIds = {}; // To handle duplicates
      final List<Trip> combinedTrips = [];

      for (var doc in ownedTripsSnapshot.docs) {
        if (tripIds.add(doc.id)) {
          // Add returns true if the element was added (not a duplicate)
          combinedTrips.add(doc.data());
        }
      }
      for (var doc in participantTripsSnapshot.docs) {
        if (tripIds.add(doc.id)) {
          combinedTrips.add(doc.data());
        }
      }

      // Sort the combined list by date as they came from two queries
      combinedTrips.sort((a, b) => a.date.compareTo(b.date));

      if (mounted) {
        setState(() {
          _upcomingTrips = combinedTrips;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "Failed to load trips: ${e.toString()}";
          _isLoading = false;
        });
      }
      // Log the error or show a user-friendly message
      if (kDebugMode) {
        print("Error loading trips: $e");
      }
    }
  }

  // Navigate to TripPlanner for new trips or editing existing ones
  void _navigateToTripPlanner({Trip? tripToEdit}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) =>
                TripPlannerApp(trip: tripToEdit), // Pass trip for editing
      ),
    ).then((_) {
      _loadUpcomingTrips(); // Refresh list after TripPlanner is popped
    });
  }

  // Navigate to TripViewerPage for viewing an existing trip
  void _navigateToTripViewer({required Trip tripToView}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => TripViewerPage(trip: tripToView)),
    ).then((_) {
      // Optional: Refresh if viewer could somehow lead to changes, though unlikely for a viewer.
      _loadUpcomingTrips();
    });
  }

  IconData _getTravelModeIcon(TravelMode mode) {
    switch (mode) {
      case TravelMode.driving:
        return Icons.directions_car;
      case TravelMode.walking:
        return Icons.directions_walk;
      case TravelMode.bicycling:
        return Icons.directions_bike;
      case TravelMode.transit:
        return Icons.directions_transit;
    }
  }

  Widget _buildTripTimelineWidget(Trip trip) {
    if (trip.stops.isEmpty) {
      return const SizedBox.shrink();
    }

    List<Widget> timelineWidgets = [];

    for (int i = 0; i < trip.stops.length; i++) {
      final stop = trip.stops[i];
      // Display stop name
      timelineWidgets.add(
        Text(
          stop.name,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
          overflow: TextOverflow.ellipsis, // Allow ellipsis if needed
          maxLines: 1,
        ),
      );

      if (i < trip.stops.length - 1) {
        // Add spacing before the travel mode icon
        timelineWidgets.add(const SizedBox(width: 4));

        final nextStop = trip.stops[i + 1];
        // Display travel mode icon
        timelineWidgets.add(
          Icon(
            _getTravelModeIcon(nextStop.travelMode),
            size: 14,
            color: Colors.grey.shade700,
          ),
        );
        // Add spacing before the arrow icon
        timelineWidgets.add(const SizedBox(width: 4));
        // Display arrow icon
        timelineWidgets.add(
          Icon(Icons.arrow_forward_ios, size: 10, color: Colors.grey.shade600),
        );
        // Add spacing before the next stop name (handled by the start of the loop)
      }
    }
    // Add padding at the end of the row to prevent the last item from being cut off
    timelineWidgets.add(const SizedBox(width: 8));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center, // Align items vertically
        children: timelineWidgets,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upcoming Trips'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.account_circle,
              color: Theme.of(context).colorScheme.inversePrimary,
            ),
            tooltip: 'My Account',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AccountPage()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadUpcomingTrips,
        child:
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 60,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _loadUpcomingTrips,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
                : _upcomingTrips.isEmpty
                ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.luggage_outlined,
                        size: 80,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'No upcoming trips yet!',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add_road_rounded),
                        label: const Text('Plan a New Trip'),
                        onPressed: () => _navigateToTripPlanner(),
                      ),
                    ],
                  ),
                )
                : ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: _upcomingTrips.length,
                  itemBuilder: (context, index) {
                    final trip = _upcomingTrips[index];
                    trip.stops.fold(
                      0,
                      (total, stop) => total + stop.durationMinutes,
                    );
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        vertical: 8.0,
                        horizontal: 4.0,
                      ),
                      elevation: 2.0,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).primaryColorLight,
                          child: Text(
                            DateFormat('d').format(trip.date),
                            style: TextStyle(
                              color: Theme.of(context).primaryColorDark,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          trip.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('MMMM yyyy, EEEE').format(trip.date),
                            ),
                            if (trip.stops.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Text(
                                  '${DateFormat('h:mm a').format(trip.date)}${trip.endTime != null ? " - ${DateFormat('h:mm a').format(trip.endTime!)}" : ""}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            if (trip.stops.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              _buildTripTimelineWidget(trip),
                            ],
                            const SizedBox(height: 2),
                            if (trip.description != null &&
                                trip.description!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  trip.description!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_note),
                              tooltip: "Edit Trip",
                              onPressed:
                                  () =>
                                      _navigateToTripPlanner(tripToEdit: trip),
                            ),
                            const Icon(Icons.arrow_forward_ios, size: 16),
                          ],
                        ),
                        onTap:
                            () => _navigateToTripViewer(
                              tripToView: trip,
                            ), // Tap to View
                      ),
                    );
                  },
                ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed:
            () =>
                _navigateToTripPlanner(), // FAB always opens planner for a new trip
        tooltip: 'Plan New Trip',
        child: const Icon(Icons.add),
      ),
    );
  }
}
