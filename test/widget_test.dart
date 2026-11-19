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
    await tester.ensureVisible(find.text('Category'));
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
  testWidgets(
    'creates and selects a bank account without losing the entry draft',
    (tester) async {
      final ledger = (await tester.runAsync(() async {
        final opened = await Ledger.open(inMemoryDatabasePath);
        await opened.setup('INR', 'Cash', 0);
        return opened;
      }))!;
      addTearDown(ledger.db.close);
      await tester.pumpWidget(PocketLedger(ledger));
      await tester.tap(find.text('Add entry'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '22.50');
      final add = find.text('Add Bank, Online or other account');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'My Bank');
      await tester.tap(find.text('Account type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bank').last);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Save'));
        await ledger.db.transaction((_) async {});
      });
      await tester.pumpAndSettle();
      expect(ledger.accounts.last.type, 'Bank');
      expect(find.text('My Bank'), findsOneWidget);
      expect(find.text('22.50'), findsOneWidget);
    },
  );
  testWidgets('home balance stays fixed while the entry list scrolls', (
    tester,
  ) async {
    final ledger = (await tester.runAsync(() async {
      final opened = await Ledger.open(inMemoryDatabasePath);
      await opened.setup('INR', 'Cash box', 12345);
      await opened.saveAccount(
        const Account('bank', 'Savings', 'Bank', 54321, false),
      );
      final category = opened.categories.firstWhere(
        (item) => item.kind == Kind.expense,
      );
      for (var index = 0; index < 5; index++) {
        await opened.saveEntry(
          LedgerEntry(
            'expense-$index',
            Kind.expense,
            1,
            dayKey(DateTime.now()),
            'bank',
            null,
            category.id,
            'Entry $index',
          ),
        );
      }
      return opened;
    }))!;
    addTearDown(ledger.db.close);
    await tester.pumpWidget(PocketLedger(ledger));
    final balance = find.text('Total balance');
    expect(find.text('Bank'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text(money(54316, 'INR')), findsOneWidget);
    expect(find.text(money(12345, 'INR')), findsOneWidget);
    final before = tester.getTopLeft(balance);
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      greaterThan(0),
    );
    expect(tester.getTopLeft(balance), before);
  });
  testWidgets('Settings creates a bank account with Bank selected by default', (
    tester,
  ) async {
    final ledger = (await tester.runAsync(() async {
      final opened = await Ledger.open(inMemoryDatabasePath);
      await opened.setup('INR', 'Cash', 0);
      return opened;
    }))!;
    addTearDown(ledger.db.close);
    await tester.pumpWidget(PocketLedger(ledger));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add bank account'));
    await tester.pumpAndSettle();
    expect(find.text('Bank'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Savings');
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await ledger.db.transaction((_) async {});
    });
    await tester.pumpAndSettle();
    expect(ledger.accounts.last.name, 'Savings');
    expect(ledger.accounts.last.type, 'Bank');
  });
}
