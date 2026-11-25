import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/league_invite.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The link shape a shared league invite uses, and the rules that keep a
/// random deep link from reaching the join call.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('reads the code from a /join/ link', () {
    expect(
      LeagueInvite.codeFromUri(
        Uri.parse('https://macro-snap-backend.vercel.app/join/ABC123'),
      ),
      'ABC123',
    );
  });

  test('lowercase codes are normalised to the server form', () {
    expect(
      LeagueInvite.codeFromUri(
        Uri.parse('https://macro-snap-backend.vercel.app/join/abc123'),
      ),
      'ABC123',
    );
  });

  test('reads the code from the custom-scheme fallback', () {
    expect(
      LeagueInvite.codeFromUri(Uri.parse('macrosnap://join/ABC123')),
      'ABC123',
    );
  });

  test('ignores non-invite paths and malformed codes', () {
    expect(
      LeagueInvite.codeFromUri(
        Uri.parse('https://macro-snap-backend.vercel.app/'),
      ),
      isNull,
    );
    expect(LeagueInvite.codeFromUri(Uri.parse('https://x/join/ABC')), isNull);
    expect(
      LeagueInvite.codeFromUri(Uri.parse('https://x/join/ABC1234')),
      isNull,
    );
    expect(
      LeagueInvite.codeFromUri(Uri.parse('https://x/join/ABC-12')),
      isNull,
    );
  });

  test('reads the code from a Play install referrer', () {
    expect(LeagueInvite.codeFromReferrer('join_code=ABC123'), 'ABC123');
    expect(
      LeagueInvite.codeFromReferrer('utm_source=share&join_code=abc123'),
      'ABC123',
    );
    // A referrer written by hand, without the query wrapper.
    expect(LeagueInvite.codeFromReferrer('ABC123'), 'ABC123');
    // Still percent-encoded on arrival.
    expect(LeagueInvite.codeFromReferrer('join_code%3DABC123'), 'ABC123');
  });

  test('ignores an empty or unrelated install referrer', () {
    expect(LeagueInvite.codeFromReferrer(''), isNull);
    expect(LeagueInvite.codeFromReferrer('   '), isNull);
    expect(LeagueInvite.codeFromReferrer('utm_source=whatsapp'), isNull);
    expect(LeagueInvite.codeFromReferrer('join_code=ABC'), isNull);
  });

  test('a pending invite is taken exactly once', () async {
    await LeagueInvite.save('ABC123');

    expect(await LeagueInvite.take(), 'ABC123');
    expect(await LeagueInvite.take(), isNull);
  });
}
