import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:simple_firebase/firestore.dart';

class FirestoreTestPage extends StatefulWidget {
  const FirestoreTestPage({Key? key}) : super(key: key);

  @override
  _FirestoreTestPageState createState() => _FirestoreTestPageState();
}

class _FirestoreTestPageState extends State<FirestoreTestPage> {
  final String testDocumentPath = "testCollection/testDocument";
  final Map<String, dynamic> testData = {"name": "John Doe", "age": 30};
  final String testCollectionPath = "testCollection";
  SimpleFirestore firestore = SimpleFirestore();
  late ValueNotifier<Map<String, dynamic>?> observedDocumentNotifier;

  @override
  void initState() {
    super.initState();
    observedDocumentNotifier =
        firestore.observeFirestoreDocument(testDocumentPath);
    observedDocumentNotifier.addListener(() {
      setState(() {}); // Update UI when the observed document changes
    });
  }

  @override
  void dispose() {
    observedDocumentNotifier.dispose();
    super.dispose();
  }

  Future<void> _writeData() async {
    final success =
    await firestore.writeData(testDocumentPath, testData, merge: true);
    _showResultDialog("Write Data", success ? "Success" : "Failed");
  }

  Future<void> _getData() async {
    final data = await firestore.getData(testDocumentPath);
    _showResultDialog("Get Data", data?.toString() ?? "No data found");
  }

  Future<void> _deleteData() async {
    final success = await firestore.deleteData(testDocumentPath);
    _showResultDialog("Delete Data", success ? "Success" : "Failed");
  }

  Future<void> _createUniqueDocument() async {
    final uniqueDocId = await firestore.createUniqueDocument(
        testCollectionPath, {"timestamp": Timestamp.now()});
    _showResultDialog(
        "Create Unique Document",
        uniqueDocId != null
            ? "Document created with ID: $uniqueDocId"
            : "Failed to create document");
  }

  void _showResultDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
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
        title: const Text("Firestore Test Page"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _writeData,
              child: const Text("Write Data"),
            ),
            ElevatedButton(
              onPressed: _getData,
              child: const Text("Get Data"),
            ),
            ElevatedButton(
              onPressed: _deleteData,
              child: const Text("Delete Data"),
            ),
            ElevatedButton(
              onPressed: _createUniqueDocument,
              child: const Text("Create Unique Document"),
            ),
            const SizedBox(height: 16),
            const Text(
              "Observed Document:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<Map<String, dynamic>?>(
              valueListenable: observedDocumentNotifier,
              builder: (context, value, child) {
                if (value == null) {
                  return const Text("No document observed");
                }
                return Text(value.toString());
              },
            ),
          ],
        ),
      ),
    );
  }
}
