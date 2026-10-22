import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:macro_snap/navigation/route_observer.dart';

/// Minimal stand-in for [HomeScreen]'s header: shows a prefs-backed name and
/// re-reads it on [RouteAware.didPopNext] exactly like [HomeScreen] does
/// (subscription in didChangeDependencies, refresh in didPopNext). Keeps the
/// test hermetic — no MealStore/DietPlan/camera dependencies.
class _NameWidget extends StatefulWidget {
  const _NameWidget();

  @override
  State<_NameWidget> createState() => _NameWidgetState();
}

class _NameWidgetState extends State<_NameWidget> with RouteAware {
  String _name = '';

  @override
  void initState() {
    super.initState();
    _loadName();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    _loadName();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  Future<void> _loadName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('name') ?? '';
    if (mounted && name != _name) {
      setState(() => _name = name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(_name)));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'a name change made on a pushed screen shows after popping back',
    (tester) async {
      SharedPreferences.setMockInitialValues({'name': 'Alice'});

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [routeObserver],
          home: const _NameWidget(),
        ),
      );
      await tester.pump();
      expect(
        find.text('Alice'),
        findsOneWidget,
        reason: 'initial name from prefs must render',
      );

      // Settings would write the new name to prefs (as _editName does):
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('name', 'Bob');

      // Push a screen on top, then pop back (like Settings → back):
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: SizedBox()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      nav.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text('Bob'),
        findsOneWidget,
        reason: 'didPopNext must re-read the name from prefs',
      );
      expect(
        find.text('Alice'),
        findsNothing,
        reason: 'stale name must be gone after returning',
      );
    },
  );
}
