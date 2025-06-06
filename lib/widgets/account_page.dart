import 'dart:async'; // For StreamSubscription

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth; // Aliased
import 'package:firebase_ui_auth/firebase_ui_auth.dart'; // For ProfileScreen and UI actions
import 'package:flutter/material.dart';
import 'package:route_force/enums/distance_unit.dart'; // Import DistanceUnit

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  StreamSubscription<fb_auth.User?>? _userChangesSubscription;
  DistanceUnit _selectedDistanceUnit = DistanceUnit.kilometers; // Default
  bool _isLoadingPreferences = true;

  @override
  void initState() {
    super.initState();
    _initStateAsync();
  }

  Future<void> _initStateAsync() async {
    await _loadUserPreferences();
    // Listen to user changes to keep Firestore in sync with Auth profile updates
    _userChangesSubscription = fb_auth.FirebaseAuth.instance.userChanges().listen((
      fb_auth.User? user,
    ) async {
      if (user != null && !user.isAnonymous) {
        await _updateUserDocumentInFirestore(user);
        // Re-load preferences if user changes, e.g., email update might trigger this
        await _loadUserPreferences();
      }
    });
  }

  Future<void> _loadUserPreferences() async {
    setState(() => _isLoadingPreferences = true);
    final currentUser = fb_auth.FirebaseAuth.instance.currentUser;
    if (currentUser != null && !currentUser.isAnonymous) {
      try {
        final userDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(currentUser.uid)
                .get();
        if (userDoc.exists && userDoc.data() != null) {
          final data = userDoc.data()!;
          final String? unitStr = data['distanceUnit'] as String?;
          if (unitStr != null) {
            _selectedDistanceUnit = DistanceUnit.values.firstWhere(
              (e) => e.toString().split('.').last == unitStr,
              orElse: () => DistanceUnit.kilometers,
            );
          }
        }
      } catch (e) {
        // Handle error, e.g., show a snackbar
        debugPrint("Error loading distance unit preference: $e");
      }
    }
    if (mounted) setState(() => _isLoadingPreferences = false);
  }

  Future<void> _updateUserDocumentInFirestore(fb_auth.User user) async {
    // This function is called when user details change via ProfileScreen
    // (e.g., displayName, email, photoURL).
    // It ensures the Firestore 'users' collection is kept in sync.
    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
    try {
      // Prepare data for Firestore update.
      // AuthGate's _createUserDocumentIfNotExists handles initial creation with defaults
      // like 'createdAt' and 'lastMapStyle'. Here, we merge updates for mutable fields.
      Map<String, dynamic> userDataToUpdate = {
        'uid': user.uid, // Explicitly include uid
        'displayName': user.displayName ?? user.email?.split('@').first,
        'email': user.email,
        'photoURL': user.photoURL,
        'distanceUnit':
            _selectedDistanceUnit
                .toString()
                .split('.')
                .last, // Save selected unit
      };

      // Firestore does not allow setting a field to null if it's not explicitly nullable
      // or if you want to remove it. Setting to null is generally fine.
      // If email can be null (e.g. phone auth user), this will set it to null.
      // If you'd rather remove the field if user.email is null, you'd do:
      // if (user.email == null) userDataToUpdate.remove('email');

      await userRef.set(userDataToUpdate, SetOptions(merge: true));
    } catch (e) {
      // Avoid showing snackbar if widget is disposed during async operation
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error syncing profile to database: ${e.toString()}'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _userChangesSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Account')),
      body: ProfileScreen(
        // ProfileScreen shows default options for email/password users.
        // To enable OAuth provider linking/unlinking, list them in `providers`.
        // e.g., providers: [EmailAuthProvider(), GoogleProvider(clientId: "YOUR_CLIENT_ID")],
        actions: [
          SignedOutAction((context) {
            // AuthGate will handle navigation after sign-out.
            // Pop all routes until the first one.
            Navigator.of(context).popUntil((route) => route.isFirst);
          }),
          AccountDeletedAction((context, user) async {
            // This callback is after Firebase Auth user is deleted.
            // Now, delete the corresponding Firestore document.
            if (!user.isAnonymous) {
              try {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .delete();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Account data removed from our records.'),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Error removing account data: ${e.toString()}',
                      ),
                    ),
                  );
                }
              }
            }
            // AuthGate will handle navigation.
            if (mounted) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          }),
        ],
        children: [
          Text('Preferences', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          DropdownButtonFormField<DistanceUnit>(
            decoration: const InputDecoration(
              labelText: 'Distance Unit',
              border: OutlineInputBorder(),
            ),
            value: _selectedDistanceUnit,
            items:
                DistanceUnit.values.map((DistanceUnit unit) {
                  return DropdownMenuItem<DistanceUnit>(
                    value: unit,
                    child: Text(
                      unit
                          .toString()
                          .split('.')
                          .last
                          .replaceFirstMapped(
                            RegExp(r'^[a-z]'),
                            (match) => match.group(0)!.toUpperCase(),
                          ),
                    ),
                  );
                }).toList(),
            onChanged: (DistanceUnit? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedDistanceUnit = newValue;
                });
                // Save immediately or provide a save button
                final currentUser = fb_auth.FirebaseAuth.instance.currentUser;
                if (currentUser != null) {
                  _updateUserDocumentInFirestore(currentUser);
                }
              }
            },
          ),
        ],
      ),
    );
  }
}
