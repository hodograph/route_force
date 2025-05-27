import 'dart:async';
import 'package:flutter/material.dart';

class DepartureSearchDialogContent extends StatefulWidget {
  final String stopId;
  final String stopName;
  // final String apiKey; // API Key will be handled by Firebase Functions
  final String initialSessionToken;
  final Future<List<dynamic>> Function(String input, String sessionToken)
  fetchPredictionsCallback;
  final Function(String placeId) onPlaceSelected;
  final VoidCallback onDialogDismissedWithoutSelection;

  const DepartureSearchDialogContent({
    super.key,
    required this.stopId,
    required this.stopName,
    // required this.apiKey,
    required this.initialSessionToken,
    required this.fetchPredictionsCallback,
    required this.onPlaceSelected,
    required this.onDialogDismissedWithoutSelection,
  });

  @override
  State<DepartureSearchDialogContent> createState() =>
      _DepartureSearchDialogContentState();
}

class _DepartureSearchDialogContentState
    extends State<DepartureSearchDialogContent> {
  late TextEditingController _searchController;
  List<dynamic> _predictions = [];
  bool _isLoading = false;
  late String _sessionToken;
  Timer? _debounce;
  bool _placeWasSelected = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _sessionToken = widget.initialSessionToken;
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      if (_searchController.text.isNotEmpty) {
        setState(() {
          _isLoading = true;
        });
        final newPredictions = await widget.fetchPredictionsCallback(
          _searchController.text,
          _sessionToken,
        );
        if (!mounted) return;
        setState(() {
          _predictions = newPredictions;
          _isLoading = false;
        });
      } else {
        setState(() {
          _predictions = [];
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    if (!_placeWasSelected) {
      widget.onDialogDismissedWithoutSelection();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Set Departure for ${widget.stopName}'),
      content: SizedBox(
        width: double.maxFinite, // Use available width
        height: 300, // Fixed height for the content area
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              autofocus:
                  false, // Changed from true to generally false for dialogs unless specifically needed
              decoration: InputDecoration(
                labelText: 'Search departure location',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon:
                    _isLoading
                        ? const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : null,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child:
                  _isLoading && _predictions.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : _predictions.isEmpty &&
                          _searchController.text.isNotEmpty &&
                          !_isLoading
                      ? const Center(child: Text('No results found.'))
                      : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _predictions.length,
                        itemBuilder: (context, index) {
                          return ListTile(
                            title: Text(_predictions[index]['description']),
                            onTap: () {
                              _placeWasSelected = true;
                              widget.onPlaceSelected(
                                _predictions[index]['place_id'],
                              );
                              Navigator.of(context).pop(); // Close dialog
                            },
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: const Text('Cancel'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
