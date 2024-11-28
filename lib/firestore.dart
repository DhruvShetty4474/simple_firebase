import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;

/// A utility class for interacting with Firestore.
///
/// This class provides methods for common Firestore operations such as
/// reading, writing, observing real-time updates, and parsing Firestore-specific data types.
class SimpleFirestore {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final List<StreamSubscription> streams = [];

  /// Checks if the device has an active internet connection via pinging cloudFlare's 1.1.1.1
  ///
  /// Returns `true` if online, `false` if offline or if an error occurs.
  Future<bool> isOnline() async {
    try {
      // Ping a globally available webpage like CloudFlare's 1.1.1.1
      final response = await http.get(Uri.parse('https://1.1.1.1'));
      return response.statusCode == 200;
    } on SocketException {
      debugPrint('No internet connection.');
      return false;
    } catch (e) {
      debugPrint('Unknown error while checking connectivity: $e');
      return false;
    }
  }

  /// Writes data to a Firestore document via set
  ///
  /// - [documentPath]: Path to the Firestore document.
  /// - [data]: The data to write.
  /// - [merge]: Whether to merge data with existing content (default: `true`).
  ///
  /// Returns `true` if the operation is successful, `false` otherwise.
  Future<bool> writeData(String documentPath, Map<String, dynamic> data, {bool merge = false}) async {
    try {
      await _firestore.doc(documentPath).set(data, SetOptions(merge: merge));
      debugPrint('Document created or merged successfully.');
      return true;
    } catch (e) {
      debugPrint('Error writing data to Firestore with set: $e');
      return false;
    }
  }

  /// Updates data in Firestore for an existing document using `update`.
  /// - [documentPath]: Path to the Firestore document.
  /// - [data]: The data to update.
  ///
  /// Returns `true` if the operation is successful, `false` otherwise.
  Future<bool> updateData(String documentPath, Map<String, dynamic> data) async {
    try {
      await _firestore.doc(documentPath).update(data);
      debugPrint('Document updated successfully.');
      return true;
    } catch (e) {
      debugPrint('Error updating data in Firestore: $e');
      return false;
    }
  }

  /// Reads data from a Firestore document.
  ///
  /// - [documentPath]: Path to the Firestore document.
  ///
  /// Returns the document data as a `Map<String, dynamic>` or `null` if the document doesn't exist or an error occurs.
  Future<Map<String, dynamic>?> getData(String documentPath) async {
    try {
      final snapshot = await _firestore.doc(documentPath).get();
      if (snapshot.exists) {
        return snapshot.data() as Map<String, dynamic>?;
      } else {
        debugPrint('Document not found at path: $documentPath');
        return null;
      }
    } catch (e) {
      debugPrint('Error fetching document: $e');
      return null;
    }
  }

  /// Deletes a Firestore document.
  ///
  /// - [documentPath]: Path to the Firestore document.
  ///
  /// Returns `true` if successful, `false` otherwise.
  Future<bool> deleteData(String documentPath) async {
    try {
      await _firestore.doc(documentPath).delete();
      debugPrint('Document deleted successfully.');
      return true;
    } catch (e) {
      debugPrint('Error deleting document: $e');
      return false;
    }
  }

  /// Creates a new document in a Firestore collection with a unique ID.
  ///
  /// - [collectionPath]: Path to the Firestore collection.
  /// - [data]: The data to write to the new document.
  ///
  /// Returns the unique document ID on success, or `null` if an error occurs.
  Future<String?> createUniqueDocument(String collectionPath, Map<String, dynamic> data) async {
    try {
      final docRef = await _firestore.collection(collectionPath).add(data);
      debugPrint('Document created with ID: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('Error creating document: $e');
      return null;
    }
  }

  /// Observes a specific field in a Firestore document in real-time.
  ///
  /// - [documentPath]: Path to the Firestore document.
  /// - [fieldPath]: Path to the nested field in the document.
  ///
  /// Returns a `ValueNotifier` that emits updates whenever the field changes.
  ValueNotifier<T?> observeFirestoreValue<T>(String documentPath, String fieldPath) {
    final notifier = ValueNotifier<T?>(null);
    final docRef = _firestore.doc(documentPath);

    final subscription = docRef.snapshots().listen((snapshot) {
      if (!snapshot.exists) {
        debugPrint('Document at $documentPath does not exist.');
        notifier.value = null;
        return;
      }

      final data = snapshot.data();
      if (data == null) {
        debugPrint("No data found at path $documentPath");
        notifier.value = null;
        return;
      }

      final nestedField = getNestedField(data, fieldPath);
      if (nestedField is T) {
        notifier.value = nestedField;
      } else {
        debugPrint(
          'Type mismatch: Expected $T, but got ${nestedField.runtimeType} for field $fieldPath.',
        );
        notifier.value = null;
      }
    }, onError: (error) {
      debugPrint('Error observing Firestore value at $documentPath: $error');
      notifier.value = null;
    });

    streams.add(subscription);

    notifier.addListener(() {
      if (!notifier.hasListeners) {
        subscription.cancel();
        debugPrint('Subscription canceled for $documentPath');
      }
    });

    return notifier;
  }

  /// Observes a Firestore document in real-time.
  ///
  /// - [documentPath]: Path to the Firestore document.
  ///
  /// Returns a `ValueNotifier` that emits updates whenever the document changes.
  ValueNotifier<Map<String, dynamic>?> observeFirestoreDocument(String documentPath) {
    final notifier = ValueNotifier<Map<String, dynamic>?>(null);
    final docRef = _firestore.doc(documentPath);

    final subscription = docRef.snapshots().listen((snapshot) {
      if (!snapshot.exists) {
        debugPrint('Document at $documentPath does not exist.');
        SchedulerBinding.instance.addPostFrameCallback((_) {
          notifier.value = null;
        });
        return;
      }

      final data = snapshot.data();
      SchedulerBinding.instance.addPostFrameCallback((_) {
        notifier.value = data;
      });
    }, onError: (error) {
      debugPrint('Error observing Firestore document at $documentPath: $error');
      SchedulerBinding.instance.addPostFrameCallback((_) {
        notifier.value = null;
      });
    });

    streams.add(subscription);

    notifier.addListener(() {
      if (!notifier.hasListeners) {
        subscription.cancel();
        debugPrint('Subscription canceled for $documentPath');
      }
    });

    return notifier;
  }

  /// Parses Firestore data types into standard Dart types.
  dynamic parseFirestoreData(dynamic data) {
    if (data is Timestamp) {
      return data.toDate();
    } else if (data is GeoPoint) {
      return {'latitude': data.latitude, 'longitude': data.longitude};
    } else if (data is DocumentReference) {
      return data.path;
    } else if (data is Map<String, dynamic>) {
      return data.map((key, value) => MapEntry(key, parseFirestoreData(value)));
    } else if (data is List) {
      return data.map((item) => parseFirestoreData(item)).toList();
    } else {
      return data;
    }
  }

  /// Retrieves a nested field from a JSON-like Firestore document.
  ///
  /// - [data]: The document data as a `Map<String, dynamic>`.
  /// - [path]: The JSON path to the nested field.
  ///
  /// Returns the field value, or `null` if the path doesn't exist.
  dynamic getNestedField(Map<String, dynamic> data, String path) {
    final keys = path.split('/');
    dynamic current = data;

    for (var key in keys) {
      if (current is Map<String, dynamic> && current.containsKey(key)) {
        current = current[key];
      } else {
        debugPrint("Key '$key' not found in path $path.");
        return null;
      }
    }

    return parseFirestoreData(current);
  }
}
