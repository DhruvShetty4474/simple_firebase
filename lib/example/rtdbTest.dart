import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:simple_firebase/rtdb.dart';
import 'dart:async';

/// A widget that tests Firebase Realtime Database (RTDB) operations.
///
/// This page demonstrates how to perform CRUD operations (Create, Read, Update, Delete)
/// and observe real-time changes in the Firebase Realtime Database.
class RTDBTestPage extends StatefulWidget {
  /// Authenticated Firebase [User] object.
  final User user;

  /// Base URL of the Firebase Realtime Database.
  /// Example: `https://your-database-url.firebaseio.com/`
  final String baseUrl;

  const RTDBTestPage({
    Key? key,
    required this.user,
    required this.baseUrl,
  }) : super(key: key);

  @override
  _RTDBTestPageState createState() => _RTDBTestPageState();
}

class _RTDBTestPageState extends State<RTDBTestPage> {
  late RTDB rtdb; // Helper instance for RTDB operations
  late ValueNotifier<dynamic> observedValueNotifier; // Observes real-time changes

  /// The path in the database where test data is stored.
  final String testPath = "/testData";

  /// Sample data used for write and update operations.
  final Map<String, dynamic> testData = {"name": "Test User", "age": 25};

  @override
  void initState() {
    super.initState();
    // Initialize RTDB helper and start observing real-time changes.
    rtdb = RTDB(widget.user, widget.baseUrl);
    observedValueNotifier = ValueNotifier(null);
    _observeRealtimeData();
  }

  @override
  void dispose() {
    // Clean up resources
    observedValueNotifier.dispose();
    super.dispose();
  }

  /// Retrieves data from the specified path in the RTDB.
  Future<void> _getData() async {
    final data = await rtdb.getData(testPath);
    _showResultDialog("Get Data", data);
  }

  /// Writes sample data to the specified path in the RTDB.
  Future<void> _writeData() async {
    final success = await rtdb.writeData(testPath, testData);
    _showResultDialog("Write Data", success ? "Success" : "Failed");
  }

  /// Updates specific fields in the data at the specified path in the RTDB.
  Future<void> _updateData() async {
    final updatedData = {"age": 30};
    final success = await rtdb.updateData(testPath, updatedData);
    _showResultDialog("Update Data", success ? "Success" : "Failed");
  }

  /// Deletes the data at the specified path in the RTDB.
  Future<void> _deleteData() async {
    final success = await rtdb.deleteData(testPath);
    _showResultDialog("Delete Data", success ? "Success" : "Failed");
  }

  /// Observes real-time changes at the specified path in the RTDB.
  ///
  /// Updates the `observedValueNotifier` whenever the data changes.
  Future<void> _observeRealtimeData() async {
    observedValueNotifier = await rtdb.observeRealtimeDBValue(testPath);
    observedValueNotifier.addListener(() {
      setState(() {}); // Trigger UI updates on data changes
    });
  }

  /// Displays a dialog with the result of an operation.
  void _showResultDialog(String title, dynamic message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message?.toString() ?? "No data"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("RTDB Test Page"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _getData,
              child: const Text("Get Data"),
            ),
            ElevatedButton(
              onPressed: _writeData,
              child: const Text("Write Data"),
            ),
            ElevatedButton(
              onPressed: _updateData,
              child: const Text("Update Data"),
            ),
            ElevatedButton(
              onPressed: _deleteData,
              child: const Text("Delete Data"),
            ),
            const SizedBox(height: 16),
            const Text(
              "Observed Realtime Data:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<dynamic>(
              valueListenable: observedValueNotifier,
              builder: (context, value, child) {
                return Text(value?.toString() ?? "No data observed");
              },
            ),
          ],
        ),
      ),
    );
  }
}
