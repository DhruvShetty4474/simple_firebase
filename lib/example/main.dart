import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:simple_firebase/auth.dart';
import 'package:simple_firebase/example/rtdbTest.dart';

import 'firestoretest.dart';

/// The main entry point of the application.
///
/// This initializes Firebase before running the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initializes Firebase. Make sure the correct configuration files (google-services.json, GoogleService-Info.plist)
  // are in place for Android and iOS.
  await Firebase.initializeApp();
  runApp(const MyApp());
}

/// The root widget of the application.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Firebase Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(), // Directs to the home page
    );
  }
}

/// The main page of the application where the user can log in and test different Firebase features.
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late final Auth _auth; // Firebase Authentication helper
  User? _user; // Tracks the authenticated user
  String _selectedPage = "RTDB"; // Tracks the selected test page

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _auth = Auth(); // Initializes the Auth helper
  }

  /// Attempts to authenticate the user using Firebase.
  ///
  /// [email] and [password] are taken from the TextField inputs.
  Future<void> _initializeAuth(String email, String password) async {
    try {
      // Sign in the user with the provided email and password
      User? user = await _auth.signInWithEmail(email, password);
      setState(() {
        _user = user; // Update the authenticated user state
      });
    } catch (e) {
      // Show an error dialog if authentication fails
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Error"),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("OK"),
            ),
          ],
        ),
      );
    }
  }

  /// Updates the selected page in the dropdown menu.
  void _onPageSelectionChanged(String? selectedPage) {
    if (selectedPage != null) {
      setState(() {
        _selectedPage = selectedPage; // Update the selected page state
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show login screen if the user is not authenticated
    if (_user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Login'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _initializeAuth(
                  _emailController.text,
                  _passwordController.text,
                ),
                child: const Text('Login'),
              ),
            ],
          ),
        ),
      );
    }

    // Show test pages after successful login
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Pages'),
        actions: [
          DropdownButton<String>(
            value: _selectedPage,
            items: const [
              DropdownMenuItem(
                value: "RTDB",
                child: Text("RTDB Test Page"),
              ),
              DropdownMenuItem(
                value: "Firestore",
                child: Text("Firestore Test Page"),
              ),
            ],
            onChanged: _onPageSelectionChanged,
          ),
        ],
      ),
      body: _selectedPage == "RTDB"
          ? RTDBTestPage(
        user: _user!,
        baseUrl: "https://your-database-url.firebaseio.com/", // Replace with your RTDB URL
      )
          : const FirestoreTestPage(), // Replace with your Firestore test page logic
    );
  }
}
