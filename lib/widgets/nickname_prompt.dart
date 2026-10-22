import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_http.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../services/gemini_service.dart';

/// Maximum nickname length (limited characters).
const int kNicknameMaxLength = 15;

/// Storage + restore for the first-login nickname.
///
/// The nickname is saved locally (prefs, under `nickname`) AND uploaded to
/// the server during registration (`/register`). Login consults this store so
/// the rules are testable and identical everywhere:
///
/// 1. Only users with NO nickname anywhere are asked (never returning users).
/// 2. A saved nickname is never overwritten by the account display name —
///    the greeting keeps the user's chosen nickname forever.
/// 3. On a fresh install (local prefs empty) the nickname is restored from
///    the server, so an existing user is never re-asked.
class NicknameStore {
  /// True when the first-login nickname prompt should be shown: only when
  /// NO nickname exists anywhere. Returning users are never asked again.
  static bool shouldAskNickname(SharedPreferences prefs) {
    final nickname = prefs.getString('nickname');
    return nickname == null || nickname.trim().isEmpty;
  }

  /// Persists the display name after a login so a saved nickname is NEVER
  /// clobbered by the Google/account display name. Returns the name stored.
  static Future<String> persistLoginName(
    SharedPreferences prefs,
    String fallbackName,
  ) async {
    final nickname = prefs.getString('nickname');
    final stored = (nickname != null && nickname.trim().isNotEmpty)
        ? nickname.trim()
        : fallbackName;
    await prefs.setString('name', stored);
    return stored;
  }

  /// Best-effort restore of the nickname the user chose during a previous
  /// registration (`/register` stores it server-side). Called when local
  /// prefs are empty — reinstall / new device — so an existing user isn't
  /// re-asked. Never throws: any failure means "no nickname known" and login
  /// simply proceeds to the first-time prompt.
  static Future<String?> restoreFromServer(String emailOrPhone) async {
    try {
      // The token identifies the caller, so no identifier goes in the URL.
      final res = await AuthHttp.get(
        Uri.parse('${GeminiService.serverUrl}/user/profile'),
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final name = data['name'] as String?;
      if (name == null || name.trim().isEmpty) return null;
      return name.trim();
    } catch (_) {
      return null;
    }
  }
}

/// Shows the first-login nickname picker. Returns the chosen nickname
/// (trimmed), or null when the user taps Skip.
///
/// Enforced [kNicknameMaxLength]-character limit so a nickname can never
/// overflow the home greeting or other UI that displays it.
Future<String?> showNicknamePrompt(BuildContext context) async {
  // The controller lives for the life of the one-shot modal — it must not be
  // disposed when `showDialog` resolves, because the dialog's exit animation
  // still rebuilds the TextField and would touch a disposed controller.
  final controller = TextEditingController();
  final chosen = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: Theme.of(ctx).brightness == Brightness.dark
          ? MacroSnapTheme.cardDark
          : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Pick a nickname'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: kNicknameMaxLength,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          hintText: 'e.g. MacroChamp 💪',
          counterText: '',
        ),
        onSubmitted: (v) {
          // Dismiss the keyboard BEFORE popping so it doesn't linger after
          // the dialog closes (the TextField still had focus).
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.pop(ctx, v);
        },
      ),
      actions: [
        TextButton(
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.pop(ctx);
          },
          child: const Text('Skip'),
        ),
        FilledButton(
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.pop(ctx, controller.text);
          },
          style: FilledButton.styleFrom(
            backgroundColor: MacroSnapTheme.neonGreen,
            foregroundColor: Colors.black,
          ),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  return chosen?.trim().isEmpty ?? true ? null : chosen!.trim();
}
