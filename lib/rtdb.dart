import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'PlatformClients/rest_api_io.dart'
if (dart.library.html) 'PlatformClients/rest_api_web.dart';

/// A utility class for interacting with Firebase Realtime Database (RTDB).
///
/// This class provides methods to perform CRUD operations (Create, Read, Update, Delete),
/// observe real-time data changes, and enforce rate limiting to manage API usage.
///
/// **Note**: The implementation differs between web and non-web platforms due to
/// platform-specific constraints on maintaining persistent connections.
///
/// For more information on the Firebase Realtime Database plugin, see the
/// [documentation](https://pub.dev/packages/firebase_database).
class RTDB {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final http.Client _client = getClient(); // Platform-specific HTTP client

  /// Map to keep track of listened values and their corresponding ValueNotifiers.
  final Map<String, ValueNotifier> _listenedValues = {};

  /// Map to manage active stream controllers for running streams.
  final Map<String, StreamController> _runningStreams = {};

  /// Enables or disables debug logging.
  bool debug = false;

  /// Rate limiting configurations.
  final int maxConnections = 50;
  final int pollingIntervalMs = 2000;
  final int maxReadsPerMinute = 600; // Maximum reads per minute
  final int maxWritesPerMinute = 300; // Maximum writes per minute
  final int maxDataPerMinute = 50000; // Maximum data in bytes per minute

  int _currentReads = 0;
  int _currentWrites = 0;
  int _currentDataTransferred = 0; // Tracks data in bytes
  Timer? _resetTimer;
  int _currentHttpConnections = 0;

  late final String _baseUrl;
  final Map<String, String> _jsonHeaders = {'Content-Type': 'application/json'};

  /// The authenticated Firebase [User] associated with this RTDB instance.
  final User user;

  /// List to track the order of active connections for managing rate limits.
  final List<String> _connectionOrder = [];

  /// Constructs an [RTDB] instance.
  ///
  /// - [user]: The authenticated Firebase user.
  /// - [_baseUrl]: The base URL of the Firebase Realtime Database.
  ///
  /// **Example**:
  /// ```dart
  /// final rtdb = RTDB(user, 'https://your-database-url.firebaseio.com/');
  /// ```
  RTDB(this.user, this._baseUrl);

  //////////////////////
  // Rate Limiting and Reset //
  //////////////////////

  /// Starts a periodic timer to reset rate limits.
  ///
  /// This method ensures that rate limits are reset at regular intervals,
  /// allowing new requests to be processed.
  void _startRateLimitResetTimer() {
    if (_resetTimer == null || !_resetTimer!.isActive) {
      _resetTimer = Timer.periodic(
        const Duration(minutes: 1),
            (timer) {
          if (debug) {
            debugPrint(
                "Current rates - Reads: $_currentReads, Writes: $_currentWrites, Data Transferred: $_currentDataTransferred Bytes, Connections: $_currentHttpConnections");
          }
          _currentReads = 0;
          _currentWrites = 0;
          _currentDataTransferred = 0;
        },
      );
    }
  }

  /// Determines whether a new request can proceed based on current rate limits.
  ///
  /// - [dataSize]: The size of the data being transferred in bytes.
  /// - [isWrite]: Indicates if the request is a write operation.
  ///
  /// Returns `true` if the request is within rate limits, `false` otherwise.
  bool _canProceedWithRequest(int dataSize, {bool isWrite = false}) {
    if (_currentReads >= maxReadsPerMinute && !isWrite) {
      return false;
    }
    if (_currentWrites >= maxWritesPerMinute && isWrite) {
      return false;
    }
    if (_currentDataTransferred + dataSize > maxDataPerMinute) {
      return false;
    }

    // If all limits are within bounds, proceed
    return true;
  }

  /// Retrieves the current user's ID token for authenticated requests.
  ///
  /// Returns the ID token as a `String` on success, or `null` if retrieval fails.
  Future<String?> _getAuthToken() async {
    try {
      return await user.getIdToken();
    } catch (e) {
      debugPrint('Error retrieving user ID token: $e');
      return null;
    }
  }

  //////////////////
  // CRUD Operations //
  //////////////////

  /// Retrieves data from the specified [path] in the RTDB.
  ///
  /// - [path]: The database path to fetch data from.
  /// - [shallow]: If `true`, only the keys are fetched without the data (default: `true`).
  /// - [query]: Additional query parameters for the request.
  ///
  /// Returns the fetched data as a dynamic object, or `null` on failure.
  Future<dynamic> getData(
      String path, {
        bool shallow = true,
        Map<String, String>? query,
      }) async {
    _startRateLimitResetTimer();
    final authToken = await _getAuthToken();

    if (authToken == null) {
      debugPrint('Error: Unable to fetch auth token.');
      return null; // Abort if no auth token
    }

    // Construct the query parameters
    final queryParams = {
      'shallow': shallow.toString(),
      'auth': authToken,
      ...?query, // Merge with additional query parameters if provided
    };

    // Construct the full URL
    final url = Uri.parse('$_baseUrl$path.json').replace(queryParameters: queryParams);

    // Enforce rate limits and connection constraints
    if (!_canProceedWithRequest(0)) {
      debugPrint('Rate limit exceeded.');
      return null; // Abort if rate limits exceeded
    }

    if (_currentHttpConnections >= maxConnections) {
      String oldestConnection = _connectionOrder.removeAt(0); // Remove the least active connection
      _runningStreams[oldestConnection]?.close(); // Close the stream controller
      _runningStreams.remove(oldestConnection);
    }

    try {
      _currentHttpConnections++;
      _connectionOrder.add(path); // Track the new connection
      final response = await _client.get(url);
      _currentHttpConnections--;

      final dataSize = response.body.length;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _currentReads++;
        _currentDataTransferred += dataSize;
        return data;
      } else {
        debugPrint('Error: Failed to fetch data. Status code: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      _currentHttpConnections--;
      debugPrint('Error during GET request: $e');
      return null;
    }
  }

  /// Writes [data] to the specified [path] in the RTDB.
  ///
  /// - [path]: The database path to write data to.
  /// - [data]: The data to write as a `Map<String, dynamic>`.
  ///
  /// Returns `true` if the operation is successful, `false` otherwise.
  Future<bool> writeData(String path, Map<String, dynamic> data) async {
    _startRateLimitResetTimer();
    final authToken = await _getAuthToken();
    if (authToken == null) return false; // Abort if no token is available

    final url = Uri.parse('$_baseUrl$path.json?auth=$authToken');
    final jsonData = json.encode(data);
    final dataSize = jsonData.length;

    if (!_canProceedWithRequest(dataSize, isWrite: true)) {
      debugPrint('Rate limit exceeded for write operation.');
      return false;
    }

    // Manage connection limit
    if (_currentHttpConnections >= maxConnections) {
      String oldestConnection = _connectionOrder.removeAt(0);
      _runningStreams[oldestConnection]?.close();
      _runningStreams.remove(oldestConnection);
    }

    try {
      _currentHttpConnections++;
      _connectionOrder.add(path);
      final response = await _client.put(
        url,
        headers: _jsonHeaders,
        body: jsonData,
      );
      _currentHttpConnections--;

      if (response.statusCode == 200) {
        _currentWrites++;
        _currentDataTransferred += dataSize;
        debugPrint('Document written successfully at $path.');
        return true;
      } else {
        debugPrint('Error writing data. Status code: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      _currentHttpConnections--;
      debugPrint('Error writing data: $e');
      return false;
    }
  }

  /// Deletes data from the specified [path] in the RTDB.
  ///
  /// - [path]: The database path to delete data from.
  ///
  /// Returns `true` if the operation is successful, `false` otherwise.
  Future<bool> deleteData(String path) async {
    _startRateLimitResetTimer();
    final authToken = await _getAuthToken();
    if (authToken == null) return false;

    final url = Uri.parse('$_baseUrl$path.json?auth=$authToken');

    if (!_canProceedWithRequest(0, isWrite: true)) {
      debugPrint('Rate limit exceeded for delete operation.');
      return false;
    }

    // Manage connection limit
    if (_currentHttpConnections >= maxConnections) {
      String oldestConnection = _connectionOrder.removeAt(0);
      _runningStreams[oldestConnection]?.close();
      _runningStreams.remove(oldestConnection);
    }

    try {
      _currentHttpConnections++;
      _connectionOrder.add(path);
      final response = await _client.delete(url);
      _currentHttpConnections--;

      if (response.statusCode == 200) {
        _currentWrites++;
        debugPrint('Document deleted successfully at $path.');
        return true;
      } else {
        debugPrint('Error deleting data. Status code: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      _currentHttpConnections--;
      debugPrint('Error deleting data: $e');
      return false;
    }
  }

  /// Updates existing [data] at the specified [path] in the RTDB.
  ///
  /// - [path]: The database path to update data at.
  /// - [data]: The data to update as a `Map<String, dynamic>`.
  ///
  /// Returns `true` if the operation is successful, `false` otherwise.
  Future<bool> updateData(String path, Map<String, dynamic> data) async {
    _startRateLimitResetTimer();
    final authToken = await _getAuthToken();
    if (authToken == null) return false;

    final url = Uri.parse('$_baseUrl$path.json?auth=$authToken');
    final jsonData = json.encode(data);
    final dataSize = jsonData.length;

    if (!_canProceedWithRequest(dataSize, isWrite: true)) {
      debugPrint('Rate limit exceeded for update operation.');
      return false;
    }

    // Manage connection limit
    if (_currentHttpConnections >= maxConnections) {
      String oldestConnection = _connectionOrder.removeAt(0);
      _runningStreams[oldestConnection]?.close();
      _runningStreams.remove(oldestConnection);
    }

    try {
      _currentHttpConnections++;
      _connectionOrder.add(path);
      final response = await _client.patch(
        url,
        headers: _jsonHeaders,
        body: jsonData,
      );
      _currentHttpConnections--;

      if (response.statusCode == 200) {
        _currentWrites++;
        _currentDataTransferred += dataSize;
        debugPrint('Document updated successfully at $path.');
        return true;
      } else {
        debugPrint('Error updating data. Status code: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      _currentHttpConnections--;
      debugPrint('Error updating data: $e');
      return false;
    }
  }

  /// Creates a new unique document at the specified [path] in the RTDB.
  ///
  /// - [path]: The database path where the document should be created.
  /// - [data]: The data to write as a `Map<String, dynamic>`.
  ///
  /// Returns the unique document ID on success, or `null` if an error occurs.
  Future<String?> createUniqueDoc(String path, Map<String, dynamic> data) async {
    _startRateLimitResetTimer();
    final authToken = await _getAuthToken();
    if (authToken == null) return null;

    final url = Uri.parse('$_baseUrl$path.json?auth=$authToken');

    try {
      _currentHttpConnections++;
      _connectionOrder.add(path);
      final response = await _client.post(
        url,
        headers: _jsonHeaders,
        body: json.encode(data),
      );
      _currentHttpConnections--;

      if (response.statusCode == 200) {
        final responseBody = json.decode(response.body);
        debugPrint('Document created with ID: ${responseBody['name']}');
        return responseBody['name'];
      } else {
        debugPrint('Error creating document. Status code: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      _currentHttpConnections--;
      debugPrint('Error creating unique document: $e');
      return null;
    }
  }

  //////////////////
  // Real-Time Observation //
  //////////////////

  /// Observes a specific field in a Firestore document in real-time.
  ///
  /// - [documentPath]: Path to the Firestore document.
  /// - [fieldPath]: Path to the nested field within the document (e.g., "data/lastUpdatedTime").
  ///
  /// Returns a [ValueNotifier] that emits updates whenever the specified field changes.
  ///
  /// **Usage Example**:
  /// ```dart
  /// ValueNotifier<String?> notifier = rtdb.observeRealtimeDBValue<String>('users/user123', 'profile/name');
  /// notifier.addListener(() {
  ///   print('Name updated to: ${notifier.value}');
  /// });
  /// ```
  Future<ValueNotifier<T?>> observeRealtimeDBValue<T>(String path) async {
    if (_listenedValues.containsKey(path)) {
      return _listenedValues[path] as ValueNotifier<T?>;
    }

    final notifier = ValueNotifier<T?>(null);

    // Fetch initial data
    try {
      final initialData = await getData(path);
      if (initialData is T) {
        notifier.value = initialData;
      } else {
        notifier.value = null;
        if (debug) {
          debugPrint(
              'Type mismatch: Expected type $T, but got ${initialData.runtimeType} for path $path.');
        }
      }
    } catch (error) {
      debugPrint('Error fetching initial data for $path: $error');
    }

    // Set up real-time observation using streams
    final streamController = _observeData(path);
    streamController.stream.listen((data) {
      if (data is T && data != notifier.value) {
        notifier.value = data;
      } else if (data is! T) {
        debugPrint(
            'Type mismatch: Expected type $T, but got ${data.runtimeType} for path $path.');
        notifier.value = null;
      }
    }, onError: (error) {
      debugPrint('Error observing Realtime Database value at $path: $error');
      notifier.value = null;
    });

    // Clean up when there are no listeners
    notifier.addListener(() {
      if (!notifier.hasListeners) {
        streamController.close();
        if (debug) {
          debugPrint('Subscription canceled for $path');
        }
      }
    });

    _listenedValues[path] = notifier;
    return notifier;
  }

  /// Observes data changes at the specified [path] in the RTDB.
  ///
  /// This method handles both web and non-web platforms by using polling
  /// for web and persistent streams for other platforms.
  ///
  /// - [path]: The database path to observe.
  ///
  /// Returns a [StreamController] that emits data updates.
  StreamController<dynamic> _observeData(String path) {
    _startRateLimitResetTimer();

    // Store the subscription to allow cancellation
    StreamSubscription<String>? httpStreamSubscription;
    Timer? pollingTimer;

    // Initialize the StreamController with onListen and onCancel callbacks
    StreamController<dynamic>? controller;

    controller = StreamController<dynamic>(
      onListen: () {
        // Asynchronously get the auth token
        _getAuthToken().then((authToken) {
          final url = Uri.parse(
              '$_baseUrl$path.json${authToken != null ? "?auth=$authToken" : ""}');

          if (kIsWeb) {
            // Polling for web platform
            var pollingInterval = Duration(milliseconds: pollingIntervalMs);

            // Function to perform polling
            Future<void> performPolling() async {
              try {
                _currentHttpConnections++;
                final response = await _client.get(url);
                _currentHttpConnections--;

                final dataSize = response.body.length;

                if (_canProceedWithRequest(dataSize)) {
                  if (response.statusCode == 200) {
                    final jsonData = json.decode(response.body);
                    _currentReads++;
                    _currentDataTransferred += dataSize;
                    if (!controller!.isClosed) {
                      controller.add(jsonData);
                    }
                  } else {
                    if (!controller!.isClosed) {
                      controller.addError(
                          'Failed to load data. Status code: ${response.statusCode}');
                    }
                  }
                } else {
                  pollingTimer?.cancel();
                  if (!controller!.isClosed) {
                    controller.addError('Rate limit exceeded');
                    controller.close();
                  }
                }
              } catch (e) {
                _currentHttpConnections--;
                if (!controller!.isClosed) {
                  controller.addError('Error while polling data: $e');
                }
              }
            }

            // Execute the initial polling
            performPolling();

            // Set up the polling timer
            pollingTimer = Timer.periodic(pollingInterval, (timer) {
              performPolling();
            });
          } else {
            // Event streaming for non-web platforms
            try {
              final request = http.Request('GET', url);
              request.headers['Accept'] = 'text/event-stream';

              _currentHttpConnections++;
              _client.send(request).then((response) {
                if (response.statusCode == 200) {
                  // Listen to the event stream
                  httpStreamSubscription = response.stream
                      .transform(utf8.decoder)
                      .listen((data) {
                    final lines = data.split('\n');
                    String? eventType;
                    String? eventData;

                    for (var line in lines) {
                      if (line.startsWith('event:')) {
                        eventType = line.substring(7).trim();
                      } else if (line.startsWith('data:')) {
                        eventData = line.substring(5).trim();

                        if (eventType != null) {
                          final dataSize = eventData.length;

                          if (_canProceedWithRequest(dataSize)) {
                            try {
                              final jsonData = json.decode(eventData);
                              if (jsonData != null && jsonData.containsKey('data')) {
                                final value = jsonData['data'];
                                _currentReads++;
                                _currentDataTransferred += dataSize;
                                if (!controller!.isClosed) {
                                  controller.add(value);
                                }
                              }
                            } catch (e) {
                              // Error decoding JSON data
                              debugPrint('Error decoding JSON data: $e');
                            }

                            eventType = null;
                            eventData = null;
                          } else {
                            if (!controller!.isClosed) {
                              controller.addError('Streaming rate limit exceeded');
                              controller.close();
                            }
                            break;
                          }
                        }
                      }
                    }
                  }, onError: (error) {
                    if (!controller!.isClosed) {
                      controller.addError('Error: $error');
                    }
                  });
                } else {
                  if (!controller!.isClosed) {
                    controller.addError(
                        'Failed to connect to Firebase. Status code: ${response.statusCode}');
                  }
                }
              }).catchError((e) {
                if (!controller!.isClosed) {
                  controller.addError('Error connecting to Firebase streaming: $e');
                }
              });
            } catch (e) {
              _currentHttpConnections--;
              if (!controller!.isClosed) {
                controller.addError('Error connecting to Firebase streaming: $e');
              }
            }
          }
        }).catchError((e) {
          if (!controller!.isClosed) {
            controller.addError('Error obtaining auth token: $e');
            controller.close();
          }
        });
      },
      onCancel: () {
        // Clean up resources when the stream is canceled
        if (kIsWeb) {
          pollingTimer?.cancel();
        } else {
          httpStreamSubscription?.cancel();
          _currentHttpConnections--;
        }
        controller?.close();
      },
    );

    return controller;
  }

  /// Parses Firestore-specific data types into standard Dart types.
  ///
  /// - [data]: The data to parse.
  ///
  /// Returns the parsed data.
  dynamic parseFirestoreData(dynamic data) {
    if (data is Timestamp) {
      // Convert Firestore Timestamp to Dart DateTime
      return data.toDate();
    } else if (data is GeoPoint) {
      // Convert Firestore GeoPoint to a Map with latitude and longitude
      return {'latitude': data.latitude, 'longitude': data.longitude};
    } else if (data is DocumentReference) {
      // Convert DocumentReference to its path
      return data.path;
    } else if (data is Map<String, dynamic>) {
      // Recursively parse each item in the map
      return data.map((key, value) => MapEntry(key, parseFirestoreData(value)));
    } else if (data is List) {
      // Recursively parse each item in the list
      return data.map((item) => parseFirestoreData(item)).toList();
    } else {
      // Return the data as-is if it's a standard Dart type (e.g., String, int, bool)
      return data;
    }
  }

  /// Retrieves a nested field from a JSON-like Firestore document.
  ///
  /// - [data]: The document data as a `Map<String, dynamic>`.
  /// - [path]: The JSON path to the nested field (e.g., "data/lastUpdatedTime").
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

  /// Disposes of all active stream subscriptions and resets rate limits.
  ///
  /// This method should be called when the RTDB instance is no longer needed
  /// to free up resources.
  void dispose() {
    for (var subscription in _runningStreams.values) {
      subscription.close();
    }
    _runningStreams.clear();
    _listenedValues.clear();
    _resetTimer?.cancel();
    _client.close();
  }
}
