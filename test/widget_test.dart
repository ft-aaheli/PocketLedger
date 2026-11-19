import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketledger/ledger.dart';
import 'package:pocketledger/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('first run creates a ledger and saves one expense', (
    tester,
  ) async {
    final ledger = await tester.runAsync(
      () => Ledger.open(inMemoryDatabasePath),
    );
    addTearDown(() => ledger!.db.close());
    await tester.pumpWidget(PocketLedger(ledger!));
    expect(find.text('Set up your ledger'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Create ledger'));
      await ledger.db.transaction((_) async {});
    });
    await tester.pumpAndSettle();
    expect(find.text('Total balance'), findsOneWidget);

    await tester.tap(find.text('Add entry'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '250.25');
    await tester.tap(find.text('Category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food').last);
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await ledger.db.transaction((_) async {});
    });
    await tester.pumpAndSettle();
    expect(ledger.entries.single.amount, 25025);
    expect(ledger.balances.values.single, -25025);
    expect(find.text('Food'), findsOneWidget);
  });
}
