import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

import 'crash_reporting.dart';

/// Keeps the photo a meal was logged from — for 24 hours.
///
/// The scanner hands Gemini a file in the OS temp directory (image_picker's
/// cache), and Android is free to delete it at any moment. So the moment a
/// meal is actually logged, the photo is copied into this app's own storage
/// under the meal's id, which is what lets the logged-meal card and the
/// history show the picture that was taken.
///
/// The copy is deliberately short-lived. A photo of every meal a person has
/// ever eaten is a lot of private data to keep on a phone for no gain, so
/// [retention] caps it at a day: the image is useful while the meal is still
/// being reviewed and forgotten the next day, exactly as the product intends.
/// [prune] enforces that on every launch, and [MealStore.load] drops the
/// reference from any record whose file is gone, so a meal outlives its photo
/// without ever pointing at a file that is not there.
class MealImageStore {
  MealImageStore._();
  static final MealImageStore instance = MealImageStore._();

  /// How long a snapped meal photo stays on disk.
  static const Duration retention = Duration(hours: 24);

  static const String _dirName = 'meal_images';

  Directory? _dir;

  /// Extensions we are willing to store the copy under. Anything else falls
  /// back to `.jpg`, which is what the in-app camera produces.
  static const Set<String> _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.heic',
  };

  /// The image directory, or null when app storage is unavailable at all
  /// (a test harness without path_provider, say).
  ///
  /// A missing store is deliberately NOT reported as an error: the feature
  /// simply degrades to "no photo", which is the ordinary state for most meals
  /// anyway. Real failures once the directory exists still go through
  /// [logError] in the callers below.
  Future<Directory?> _imagesDir() async {
    final cached = _dir;
    if (cached != null && await cached.exists()) return cached;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/$_dirName');
      if (!await dir.exists()) await dir.create(recursive: true);
      _dir = dir;
      return dir;
    } catch (e) {
      debugPrint('MealImageStore: no app storage available ($e)');
      return null;
    }
  }

  static String _extensionFor(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '.jpg';
    final ext = path.substring(dot).toLowerCase();
    return _imageExtensions.contains(ext) ? ext : '.jpg';
  }

  /// Copies [sourcePath] into app storage as `{mealId}.{ext}` and returns the
  /// new path, or null when the source is missing/unreadable.
  ///
  /// Never throws: a meal must still log when its photo cannot be kept.
  Future<String?> save({
    required String mealId,
    required String sourcePath,
    DateTime? at,
  }) async {
    final dir = await _imagesDir();
    if (dir == null) return null;
    try {
      final source = File(sourcePath);
      if (!await source.exists()) return null;
      final dest = File('${dir.path}/$mealId${_extensionFor(sourcePath)}');
      await source.copy(dest.path);
      // The copy is stamped with the capture time rather than "now", so the
      // retention sweep measures the photo and not the moment it was copied.
      await dest.setLastModified(at ?? DateTime.now());
      return dest.path;
    } catch (e, st) {
      logError('MealImageStore.save', e, st);
      return null;
    }
  }

  /// Deletes every stored image past [retention] and returns the paths that
  /// survived, so the caller can drop the rest from its records.
  Future<Set<String>> prune({DateTime? now}) async {
    final survivors = <String>{};
    final dir = await _imagesDir();
    if (dir == null) return survivors;
    try {
      final cutoff = (now ?? DateTime.now()).subtract(retention);
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete();
          } else {
            survivors.add(entity.path);
          }
        } catch (_) {
          // Unreadable or already gone — leave it out of the survivors.
        }
      }
    } catch (e, st) {
      logError('MealImageStore.prune', e, st);
    }
    return survivors;
  }

  /// Whether [path] is a stored photo that is still inside its 24 hours.
  /// A missing file is not live; that is the ordinary end of the lifetime,
  /// not an error.
  Future<bool> isLive(String? path, {DateTime? now}) async {
    if (path == null || path.isEmpty) return false;
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final stat = await file.stat();
      return !stat.modified.isBefore(
        (now ?? DateTime.now()).subtract(retention),
      );
    } catch (_) {
      return false;
    }
  }

  /// Deletes one stored photo. Used when its meal is deleted, so the image
  /// does not linger for a day behind a record that no longer exists.
  Future<void> remove(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e, st) {
      logError('MealImageStore.remove', e, st);
    }
  }

  /// Drops every stored photo. Used when the account's data is wiped on
  /// logout/deletion.
  Future<void> clearAll() async {
    final dir = await _imagesDir();
    if (dir == null) return;
    try {
      await for (final entity in dir.list()) {
        if (entity is File) {
          try {
            await entity.delete();
          } catch (_) {
            // Best effort.
          }
        }
      }
    } catch (e, st) {
      logError('MealImageStore.clearAll', e, st);
    }
  }
}
