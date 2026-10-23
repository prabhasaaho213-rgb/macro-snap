import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/diet_profile.dart';
import 'account_partition.dart';
import 'auth_http.dart';
import 'gemini_service.dart';
import 'habit_store.dart';
import 'meal_store.dart';

/// Thrown by [GuruService.send] when the backend answers 403 `pro_required`.
///
/// Guru is a Pro feature (every turn is billed to Gemini), so the server — not
/// the client — decides who may chat. The screen catches this and shows the
/// upgrade path instead of a raw error code.
class GuruProRequiredException implements Exception {
  /// The server's own wording when it sent one; a sensible default otherwise.
  final String message;

  const GuruProRequiredException([
    this.message = 'Guru is a Pro feature. Upgrade to keep chatting.',
  ]);

  @override
  String toString() => message;
}

/// Backs the in-app nutrition assistant "Guru" (Ask Guru on Home).
///
/// Besides the message + history the screen used to send, every request
/// carries a compact [buildGuruContext] snapshot of the user's OWN day —
/// today's meals and macro totals, their targets, habits, water and first
/// name — so the assistant can answer "how am I doing today?" instead of
/// only generic nutrition questions. The backend renders that snapshot into
/// the system instruction (and still refuses non-food topics).
class GuruService {
  GuruService._();

  /// Widget/integration-test hook: when set, [send] hands the request payload
  /// to this function instead of the network, so a test can assert the
  /// personalized snapshot without a live backend (mirrors
  /// [GeminiService.mockResult], which does the same for scanning).
  @visibleForTesting
  static Future<Map<String, dynamic>> Function(Map<String, dynamic> payload)?
  mockSender;

  /// Posts one turn to `POST /chat` and returns the decoded response body.
  /// Throws on transport failure — the screen shows its offline message then.
  static Future<Map<String, dynamic>> send({
    required String message,
    required List<Map<String, String>> history,
  }) async {
    final payload = <String, dynamic>{
      'message': message,
      'history': history,
      'context': await buildGuruContext(),
    };
    final mock = mockSender;
    if (mock != null) return mock(payload);

    final resp = await AuthHttp.post(
      Uri.parse('${GeminiService.serverUrl}/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 45));

    // 403 pro_required is not an error to print — it is the Pro gate. Surface
    // it as a typed exception so the screen can offer the upgrade.
    if (resp.statusCode == 403) {
      String? serverMessage;
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map<String, dynamic>) {
          if (decoded['error'] == 'pro_required') {
            final msg = decoded['message'];
            if (msg is String && msg.trim().isNotEmpty) serverMessage = msg;
            throw serverMessage == null
                ? const GuruProRequiredException()
                : GuruProRequiredException(serverMessage);
          }
        }
      } on GuruProRequiredException {
        rethrow;
      } catch (_) {
        // Unparseable body — fall through and report it generically below.
      }
    }

    final decoded = jsonDecode(resp.body);
    return decoded is Map<String, dynamic>
        ? decoded
        : const {'error': 'Something went wrong. Please try again.'};
  }

  /// Best-effort snapshot of the active account's day.
  ///
  /// Every section is loaded independently and a store that has not loaded
  /// yet (or is empty) simply contributes nothing — a hiccup here must never
  /// block the user from chatting. Deliberately excludes the phone/email and
  /// anything that identifies the account to the AI provider.
  static Future<Map<String, dynamic>> buildGuruContext() async {
    final ctx = <String, dynamic>{};

    try {
      final prefs = await SharedPreferences.getInstance();
      final name = (prefs.getString('name') ?? '').trim();
      if (name.isNotEmpty) ctx['name'] = _clip(name, 40);
    } catch (_) {
      // No prefs -> just no name in the snapshot.
    }

    try {
      final store = MealStore.instance;
      await store.load();
      ctx['today'] = <String, dynamic>{
        'calories': store.todayCalories,
        'protein_g': _round1(store.todayProtein),
        'carbs_g': _round1(store.todayCarbs),
        'fats_g': _round1(store.todayFats),
        'meals': [
          for (final m in store.todayMeals.take(12))
            <String, dynamic>{
              'name': _clip(m.name, 60),
              'calories': m.calories,
              'protein_g': _round1(m.protein),
            },
        ],
      };
    } catch (_) {
      // Meals unavailable -> the assistant just won't see today's log.
    }

    try {
      final habits = HabitStore.instance;
      final due = habits.todayHabits;
      ctx['habits'] = <String, dynamic>{
        'due': due.length,
        'completed': habits.todayCompleted,
        'names': [for (final h in due.take(8)) _clip(h.name, 40)],
      };
      ctx['water'] = <String, dynamic>{
        'glasses': habits.waterToday,
        'goal': habits.waterGoal,
      };
    } catch (_) {
      // Habits unavailable -> omit.
    }

    try {
      final profile = DietPlanService.instance.profile;
      if (profile != null) {
        ctx['goal'] = DietPlanService.goalLabel(profile.goal);
        ctx['diet'] = DietPlanService.dietLabel(profile.diet);
        ctx['targets'] = <String, dynamic>{
          'calories': profile.targetCalories,
          'protein_g': _round1(profile.targetProtein),
          'carbs_g': _round1(profile.targetCarbs),
          'fats_g': _round1(profile.targetFats),
        };
      }
    } catch (_) {
      // No diet profile -> generic answers only.
    }

    return ctx;
  }

  /// Persisted Guru transcript, per account. The user asked for chat memory:
  /// reopening Ask Guru restores the last conversation instead of starting
  /// blank every time. Capped to the newest [maxHistoryMessages] turns.
  static const int maxHistoryMessages = 24;
  static const String _chatPrefsKey = 'guru_chat';

  static Future<String> _chatSuffix() async {
    final prefs = await SharedPreferences.getInstance();
    return AccountPartition.suffix(AccountPartition.activeFromPrefs(prefs));
  }

  /// Loads the saved transcript ({'role': 'user'|'model', 'text': ...}).
  /// Best-effort: any failure means "nothing saved" and Guru just starts
  /// fresh — a corrupt transcript must never stop the chat from opening.
  static Future<List<Map<String, String>>> loadChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs
          .getString(AccountPartition.key(_chatPrefsKey, await _chatSuffix()));
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final e in decoded)
          if (e is Map &&
              (e['role'] == 'user' || e['role'] == 'model') &&
              e['text'] is String &&
              (e['text'] as String).trim().isNotEmpty)
            {
              'role': e['role'] as String,
              'text': e['text'] as String,
            },
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Overwrites the saved transcript with [messages]. Drops everything
  /// beyond the newest [maxHistoryMessages], so the file (and the context
  /// the backend gets) stays small.
  static Future<void> saveChatHistory(
    List<Map<String, String>> messages,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = AccountPartition.key(_chatPrefsKey, await _chatSuffix());
      final keep = messages.length > maxHistoryMessages
          ? messages.sublist(messages.length - maxHistoryMessages)
          : messages;
      await prefs.setString(key, jsonEncode(keep));
    } catch (_) {
      // Saving is best-effort — a failed write only means an older
      // transcript shows up next time.
    }
  }

  static String _clip(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);

  static double _round1(double v) => (v * 10).roundToDouble() / 10;
}
