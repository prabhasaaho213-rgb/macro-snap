import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/razorpay_service.dart';

/// The money path: a retry must never mint a second subscription, and someone
/// who is already Pro must never be sent to checkout again. Both are
/// regression guards for the in-app Razorpay flow shipped in 1.4.96.
void main() {
  tearDown(() {
    RazorpayService.createSubscriptionForTest = null;
    RazorpayService.refreshStatusForTest = null;
  });

  test(
    'a second tap while checkout is opening creates no second subscription',
    () async {
      var created = 0;
      final gate = Completer<Map<String, dynamic>>();
      RazorpayService.refreshStatusForTest = () async => false;
      RazorpayService.createSubscriptionForTest = ({required String name}) {
        created++;
        return gate.future;
      };

      final first = RazorpayService.purchase(name: 'Ada');
      // Let the first call get as far as the server request.
      await Future<void>.delayed(Duration.zero);

      final second = await RazorpayService.purchase(name: 'Ada');
      expect(second.outcome, PaymentOutcome.pending);
      expect(second.message, contains('already in progress'));
      expect(created, 1, reason: 'one purchase attempt, one subscription');

      gate.completeError(Exception('test stops the flow here'));
      await expectLater(first, throwsA(isA<Exception>()));
    },
  );

  test(
    'already subscribed → success, and no subscription is created',
    () async {
      var created = 0;
      RazorpayService.refreshStatusForTest = () async => true;
      RazorpayService
          .createSubscriptionForTest = ({required String name}) async {
        created++;
        return {'subscription_id': 'sub_test', 'razorpay_key': 'rzp_test_key'};
      };

      final result = await RazorpayService.purchase(name: 'Ada');
      expect(result.outcome, PaymentOutcome.success);
      expect(created, 0, reason: 'a paid user is never charged twice');
    },
  );

  test('a fresh purchase still reaches the server create call', () async {
    var created = 0;
    RazorpayService.refreshStatusForTest = () async => false;
    RazorpayService.createSubscriptionForTest = ({required String name}) async {
      created++;
      return {'subscription_id': '', 'razorpay_key': ''};
    };

    final result = await RazorpayService.purchase(name: 'Ada');
    // An empty subscription id is a failed start, but the call did happen.
    expect(result.outcome, PaymentOutcome.failed);
    expect(created, 1);
  });
}
