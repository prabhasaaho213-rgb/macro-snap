import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/widgets/nickname_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pins the "ask for a nickname ONLY for new users" contract end-to-end at
/// the storage layer, replicating the exact prefs sequence the login flow
/// performs:
///
/// 1. Brand-new user (empty prefs) → prompt shown.
/// 2. User picks "Prabhas" → saved under `nickname` + `name`.
/// 3. Logout (removes phone/email, keeps nickname) → login again with the
///    SAME email → NO prompt (this used to re-ask on fresh installs and
///    clobber the greeting with the Google display name).
/// 4. Reinstall (prefs wiped) → nickname gone locally → prompt again — but
///    the login now restores it from the server before deciding, so a
///    returning user is restored, not re-asked.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('brand-new user with empty prefs is asked for a nickname', () async {
    final prefs = await SharedPreferences.getInstance();
    expect(NicknameStore.shouldAskNickname(prefs), isTrue);
  });

  test('after saving a nickname the user is never asked again', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nickname', 'Prabhas');
    await prefs.setString('name', 'Prabhas');

    expect(NicknameStore.shouldAskNickname(prefs), isFalse);
  });

  test('logout → re-login with the same email does NOT re-ask', () async {
    final prefs = await SharedPreferences.getInstance();

    // ── login #1 (fresh install) ─────────────────────────────
    expect(NicknameStore.shouldAskNickname(prefs), isTrue);
    // Google display name is written first…
    await NicknameStore.persistLoginName(prefs, 'Prabhas Aaho');
    // …then the user picks a nickname.
    await prefs.setString('nickname', 'Prabhas');
    await prefs.setString('name', 'Prabhas');

    // ── logout: only auth/session keys are cleared ───────────
    await prefs.remove('phone');
    await prefs.remove('email');

    // ── login #2 (same email, same install) ──────────────────
    expect(
      NicknameStore.shouldAskNickname(prefs),
      isFalse,
      reason: 'a returning user on the same device must never be re-asked',
    );
  });

  test(
    'a second login never overwrites the nickname with the Google name',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('nickname', 'Prabhas');
      await prefs.setString('name', 'Prabhas');

      // The Google account's display name differs from the chosen nickname.
      await NicknameStore.persistLoginName(prefs, 'Prabhas Aaho');

      expect(
        prefs.getString('name'),
        'Prabhas',
        reason:
            'the greeting must keep the chosen nickname, not the Google '
            'display name',
      );
    },
  );

  test(
    'reinstall (prefs wiped) prompts again — server restore fills it in',
    () async {
      final prefs = await SharedPreferences.getInstance();
      // A wiped install: nothing local.
      expect(NicknameStore.shouldAskNickname(prefs), isTrue);

      // The login first restores the nickname saved on the server…
      await prefs.setString('nickname', 'Prabhas');
      // …and only then decides whether to prompt.
      expect(
        NicknameStore.shouldAskNickname(prefs),
        isFalse,
        reason: 'after a server restore the existing user must not be asked',
      );
    },
  );

  test(
    'restoreFromServer returns null on any failure (never throws)',
    () async {
      // No server in the test environment → the http call fails → null.
      final restored = await NicknameStore.restoreFromServer(
        'nobody@nowhere.invalid',
      );
      expect(restored, isNull);
    },
  );
}
