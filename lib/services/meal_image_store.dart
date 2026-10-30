import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crash_reporting.dart';

/// Keeps the photo a meal was logged from — for a configurable duration
/// (24 hours by default, 7 or 30 days, or forever on Pro).
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
///
/// The window itself is the user's choice since 1.5.9: Settings → Meal Photos
/// offers 24 hours / 7 days / 30 days / Forever (the last is Pro-only — keeping
/// a camera roll of every meal sold for free was the privacy trade-off the
/// original 24-hour rule deliberately avoided). [loadRetention] reads the
/// chosen window once at startup; [retention] then returns it everywhere the
/// widget and the sweep previously hardcoded a day.
class MealImageStore {
  MealImageStore._();
  static final MealImageStore instance = MealImageStore._();

  /// Prefs key for the chosen window, in hours. `0` means "keep forever".
  static const String retentionPrefKey = 'meal_photo_retention_hours';

  /// The shipped default: photos last a day.
  static const Duration defaultRetention = Duration(hours: 24);

  /// The configured window. Defaults to [defaultRetention]; [loadRetention]
  /// replaces it from prefs at startup, and [setRetentionHours] at change
  /// time (both cache and disk together).
  static int _hours = defaultRetention.inHours;

  /// The window in hours as stored: 24 / 168 / 720, or 0 for forever.
  static int get retentionHours => _hours;

  /// True when the user chose "Forever" — nothing is ever swept.
  static bool get keepForever => _hours == 0;

  /// [keepForever] in duration terms: a window no real meal history reaches,
  /// so prune and the widget's live-check both simply never expire a photo.
  /// (100 years. A cleaner mechanism would be a boolean in [prune], but one
  /// huge window keeps every readsite — MealPhoto, MealStore, isLive — on the
  /// exact same code path it already runs.)
  static const Duration _forever = Duration(days: 36500);

  /// How long a snapped meal photo stays on disk. Read by [prune], [isLive]
  /// and the [MealPhoto] widget.
  static Duration get retention =>
      keepForever ? _forever : Duration(hours: _hours);

  /// Reads the stored window once at startup. Never throws: an unusable prefs
  /// store keeps the shipped 24-hour default.
  static Future<void> loadRetention() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(retentionPrefKey);
      if (stored != null) {
        _hours = stored;
      }
    } catch (e, st) {
      logError('MealImageStore.loadRetention', e, st);
    }
  }

  /// Persists a new window (24 / 168 / 720 / 0) and applies it to the memory
  /// cache so the next sweep honors it without waiting for a restart. Never
  /// throws: a failed disk write still updates the session.
  static Future<void> setRetentionHours(int hours) async {
    _hours = hours;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(retentionPrefKey, hours);
    } catch (e, st) {
      logError('MealImageStore.setRetentionHours', e, st);
    }
  }

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

  /// Writes [bytes] into app storage as `{mealId}.{ext}`. The cloud-photo
  /// restore path: the backup arrives as base64 through the backend rather
  /// than as a file on disk, so it needs its own way in — and it must land
  /// under exactly the same name [save] produces, so the widget and the
  /// sweep treat a restored photo like one copied at log time. [at] stamps
  /// the capture time so the retention window starts at the MEAL, not the
  /// download.
  ///
  /// Never throws: a failed restore costs one photo, not one meal.
  Future<String?> saveBytes({
    required String mealId,
    required List<int> bytes,
    DateTime? at,
    String extension = '.jpg',
  }) async {
    final dir = await _imagesDir();
    if (dir == null || bytes.isEmpty) return null;
    try {
      final ext = _imageExtensions.contains(extension.toLowerCase())
          ? extension.toLowerCase()
          : '.jpg';
      final file = File('${dir.path}/$mealId$ext');
      await file.writeAsBytes(bytes);
      await file.setLastModified(at ?? DateTime.now());
      return file.path;
    } catch (e, st) {
      logError('MealImageStore.saveBytes', e, st);
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

  /// Copies [path] into the device's photo gallery through the platform
  /// channel MainActivity owns ("macrosnap/launcher", method saveToGallery). A
  /// gallery-saver plugin would be a whole dependency for the same job.
  /// Best-effort: false on any failure, so the caller shows one honest
  /// snackbar instead of a stack trace.
  static const MethodChannel _launcherChannel = MethodChannel(
    'macrosnap/launcher',
  );

  static Future<bool> saveToGallery(String path) async {
    try {
      final ok = await _launcherChannel
          .invokeMethod<bool>('saveToGallery', {'path': path});
      return ok ?? false;
    } catch (e, st) {
      logError('MealImageStore.saveToGallery', e, st);
      return false;
    }
  }
}
