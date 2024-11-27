import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// A utility class for handling file uploads to Firebase Storage.
///
/// This class provides methods to upload single or multiple images, retrieve download URLs,
/// check file existence, and select images using the ImagePicker package.
class BucketStorage {
  // FirebaseStorage instance for interacting with Firebase Storage
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  // File extension for uploaded images (default: .png)
  static const String _imageExtension = '.png';

  // Error message for unsupported web uploads
  static const String _unsupportedErrorMessage = "Web uploads are not yet implemented.";

  /// Uploads a single image file to Firebase Storage under a user-specific path.
  ///
  /// - [imageFile]: The image file to upload.
  /// - [userId]: The user ID used to construct the storage path.
  /// - [customPath]: A custom storage path (optional). If provided, this will override the default path.
  ///
  /// Returns the download URL of the uploaded image on success, or `null` on failure.
  static Future<String?> uploadImage(File imageFile, String userId, {String? customPath}) async {
    try {
      // Generate a unique filename based on the current timestamp
      String filename = DateTime.now().millisecondsSinceEpoch.toString();

      // Construct the storage file path
      String filePath = customPath ?? 'users/$userId/images/$filename$_imageExtension';

      // Check if running on web (unsupported for this method)
      if (kIsWeb) {
        throw UnsupportedError(_unsupportedErrorMessage);
      }

      // Upload the file to Firebase Storage
      UploadTask uploadTask = _storage.ref(filePath).putFile(imageFile);
      TaskSnapshot snapshot = await uploadTask;

      // Return the download URL of the uploaded file
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint("Error uploading image: $e");
      return null;
    }
  }

  /// Uploads multiple image files to Firebase Storage.
  ///
  /// - [imageFiles]: A list of image files to upload.
  /// - [userId]: The user ID used to construct the storage path for each image.
  /// - [customPath]: A custom storage path (optional). If provided, this will override the default path.
  ///
  /// Returns a list of download URLs for successfully uploaded images.
  static Future<List<String>> uploadMultipleImages(
      List<File> imageFiles, String userId, {String? customPath}) async {
    List<String> uploadedPaths = [];
    for (var imageFile in imageFiles) {
      String? imagePath = await uploadImage(imageFile, userId, customPath: customPath);
      if (imagePath != null) {
        uploadedPaths.add(imagePath);
      }
    }
    return uploadedPaths;
  }

  /// Retrieves the download URL for a file stored in Firebase Storage.
  ///
  /// - [filePath]: The storage path of the file.
  ///
  /// Returns the download URL on success, or `null` on failure.
  static Future<String?> getImageUrl(String filePath) async {
    try {
      return await _storage.ref(filePath).getDownloadURL();
    } catch (e) {
      debugPrint("Error fetching image URL: $e");
      return null;
    }
  }

  /// Checks if a file exists in Firebase Storage.
  ///
  /// - [path]: The full storage path of the file.
  ///
  /// Returns `true` if the file exists, `false` otherwise.
  static Future<bool> checkIfFileExists(String path) async {
    try {
      await _storage.ref(path).getDownloadURL();
      return true; // File exists if the download URL is retrievable
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') {
        return false; // File does not exist
      }
      debugPrint("Error checking file existence: $e");
      return false;
    }
  }

  /// Picks multiple images from the device using the ImagePicker package.
  ///
  /// Returns a list of `File` objects representing the selected images.
  /// Returns an empty list if no images are selected or an error occurs.
  static Future<List<File>> pickImages() async {
    try {
      final ImagePicker picker = ImagePicker();
      final List<XFile> images = await picker.pickMultiImage();

      return images.map((xfile) => File(xfile.path)).toList();
        } catch (e) {
      debugPrint("Error picking images: $e");
    }
    return [];
  }
}
