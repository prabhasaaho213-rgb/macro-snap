import 'package:flutter/material.dart';
import '../screens/subscription_screen.dart';

/// Global navigator key attached to the app so notification taps and other
/// non-widget code can navigate when no BuildContext is available.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Shared index of the active tab in [MainShell]:
/// 0 = Home, 1 = Scan, 2 = Habits, 3 = Updates.
/// Notification taps set this so the shell switches to the Habits tab;
/// [MainShell] reads it in initState and listens for changes.
final ValueNotifier<int> shellTabIndex = ValueNotifier<int>(0);

/// Switches the app shell to the given tab [index].
///
/// The shell is the app's `home` route for authenticated users, so just
/// updating the shared index is enough — [MainShell] picks it up via its
/// initState read and the change listener. We deliberately never push a
/// shell over the login/onboarding gate here, so an unauthenticated tap
/// simply lands the user on the normal login flow instead of bypassing it.
void openShellTab(int index) {
  shellTabIndex.value = index;
}

/// Opens the Subscription (Pro) screen from notification taps and other
/// non-widget code where no BuildContext is available. Pushes through the
/// global navigator key; a no-op when the navigator isn't mounted (e.g. the
/// app is still on the login/onboarding gate).
void openSubscriptionScreen() {
  appNavigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
  );
}
