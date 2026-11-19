import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketledger/app_lock.dart';

void main() {
  testWidgets(
    'lock conceals the ledger until verified and relocks on background',
    (tester) async {
      const channel = MethodChannel('pocketledger/device_lock');
      final messenger = tester.binding.defaultBinaryMessenger;
      var attempts = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'confirm');
        attempts++;
        if (attempts == 1) throw PlatformException(code: 'no_screen_lock');
        return attempts > 2;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              AppLockGate(enabled: true, child: child!),
          home: const Scaffold(body: Text('Private ledger')),
        ),
      );
      final unlock = find.text('Unlock PocketLedger');
      final content = find.text('Private ledger');
      expect(content, findsNothing);

      await tester.tap(unlock);
      await tester.pumpAndSettle();
      expect(find.textContaining('Set a PIN'), findsOneWidget);
      expect(content, findsNothing);

      await tester.tap(unlock);
      await tester.pumpAndSettle();
      expect(content, findsNothing);
      await tester.tap(unlock);
      await tester.pumpAndSettle();
      expect(content, findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(content, findsNothing);
      expect(unlock, findsOneWidget);
    },
  );
}
