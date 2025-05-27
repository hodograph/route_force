import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _displayNameController;
  final TextEditingController _passwordController = TextEditingController();

  User? _currentUser;
  bool _isLoading = false;
  String _initialDisplayName = '';

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
    _initialDisplayName = _currentUser?.displayName ?? '';
    _displayNameController = TextEditingController(text: _initialDisplayName);
  }

  Future<void> _updateDisplayName() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_displayNameController.text.trim() == _initialDisplayName) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Display name is already up to date.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _currentUser?.updateDisplayName(_displayNameController.text.trim());
      // Update in Firestore users collection
      if (_currentUser != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser!.uid)
            .update({'displayName': _displayNameController.text.trim()});
      }
      setState(() {
        _initialDisplayName = _displayNameController.text.trim();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Display name updated successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating display name: ${e.toString()}'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Log Out'),
            content: const Text('Are you sure you want to log out?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Log Out'),
              ),
            ],
          ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      // AuthGate will handle navigation
      if (mounted) {
        // Pop AccountPage after logout to ensure AuthGate rebuilds correctly
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  Future<void> _deleteAccount() async {
    if (_currentUser == null) return;

    final confirmDelete = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Account?'),
            content: const Text(
              'This action is permanent and cannot be undone. Are you sure you want to delete your account?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  'Delete',
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),
            ],
          ),
    );

    if (confirmDelete != true) return;

    // Re-authentication
    // For simplicity, this example only handles email/password re-authentication.
    // Google/other providers would need their specific re-auth flows.
    bool reauthenticated = false;
    if (_currentUser!.providerData.any(
      (userInfo) => userInfo.providerId == 'password',
    )) {
      _passwordController.clear();
      final String? password = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => AlertDialog(
              title: const Text('Re-authenticate to Delete Account'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Please enter your password to confirm account deletion.',
                  ),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed:
                      () => Navigator.of(context).pop(_passwordController.text),
                  child: const Text('Confirm'),
                ),
              ],
            ),
      );

      if (password == null || password.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Re-authentication cancelled.')),
          );
        }
        return;
      }

      setState(() => _isLoading = true);
      try {
        AuthCredential credential = EmailAuthProvider.credential(
          email: _currentUser!.email!,
          password: password,
        );
        await _currentUser!.reauthenticateWithCredential(credential);
        reauthenticated = true;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Re-authentication failed: ${e.toString()}'),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } else {
      // For non-password providers, re-authentication is more complex.
      // We can proceed with a warning or implement provider-specific re-auth.
      // For now, we'll allow deletion with a strong warning if not email/password.
      final confirmNonPassword = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Confirm Deletion'),
              content: const Text(
                'You are signed in with a third-party provider. Re-authentication is not directly supported for account deletion in this flow. Proceed with caution.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(
                    'Proceed to Delete',
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ),
              ],
            ),
      );
      if (confirmNonPassword == true) {
        reauthenticated = true; // Assume user accepts the risk
      }
    }

    if (!reauthenticated) return;

    setState(() => _isLoading = true);
    try {
      String userId = _currentUser!.uid;
      await _currentUser!.delete();
      // Delete Firestore document
      await FirebaseFirestore.instance.collection('users').doc(userId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account deleted successfully.')),
        );
        // AuthGate will handle navigation
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error deleting account: ${e.toString()}. You may need to log out and log back in.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Account')),
      body:
          _currentUser == null
              ? const Center(child: Text('Not logged in.'))
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Email: ${_currentUser!.email}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _displayNameController,
                        decoration: const InputDecoration(
                          labelText: 'Display Name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Display name cannot be empty.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _updateDisplayName,
                        child:
                            _isLoading
                                ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                : const Text('Save Display Name'),
                      ),
                      const SizedBox(height: 30),
                      const Divider(),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _logout,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade700,
                        ),
                        child: const Text('Log Out'),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _deleteAccount,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                        ),
                        child: const Text('Delete Account'),
                      ),
                    ],
                  ),
                ),
              ),
    );
  }
}
