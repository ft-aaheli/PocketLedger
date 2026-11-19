import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketledger/ledger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('closing and reopening keeps ledger data', () async {
    final folder = await Directory.systemTemp.createTemp('pocketledger-test-');
    addTearDown(() => folder.delete(recursive: true));
    final path = '${folder.path}/ledger.sqlite';
    final original = await Ledger.open(path);
    try {
      await original.setup('EUR', 'Cash', 2850);
      final cash = original.accounts.single.id;
      final expense = original.categories.firstWhere(
        (c) => c.kind == Kind.expense,
      );
      await original.saveEntry(
        LedgerEntry(
          newId(),
          Kind.expense,
          195,
          '2026-11-19',
          cash,
          null,
          expense.id,
          'Coffee',
        ),
      );
      await original.setting('theme', 'dark');
    } finally {
      await original.db.close();
    }
    final reopened = await Ledger.open(path);
    addTearDown(reopened.db.close);
    expect(reopened.currency, 'EUR');
    expect(reopened.theme, 'dark');
    expect(reopened.balances.values.single, 2655);
    expect(reopened.entries.single.note, 'Coffee');
  });

  test('parses integer minor units and rejects excess precision', () {
    expect(minorUnits('250.25'), 25025);
    expect(minorUnits('-0.05'), -5);
    expect(minorUnits('7.2'), 720);
    expect(minorUnits('2.009'), isNull);
    expect(minorUnits('1e4'), isNull);
    expect(money(123456789, 'INR'), '₹12,34,567.89');
  });

  test(
    'balances, archived references, monthly totals and authenticated restore',
    () async {
      final ledger = await Ledger.open(inMemoryDatabasePath);
      addTearDown(ledger.db.close);
      await ledger.setup('INR', 'Cash', 100000);
      final cash = ledger.accounts.single.id;
      final food = ledger.categories.firstWhere((c) => c.name == 'Food');
      final salary = ledger.categories.firstWhere((c) => c.name == 'Salary');
      const day = '2026-11-19';
      LedgerEntry expense(int amount) => LedgerEntry(
        'expense',
        Kind.expense,
        amount,
        day,
        cash,
        null,
        food.id,
        'Lunch',
      );

      await ledger.saveEntry(expense(25000));
      expect(ledger.balances[cash], 75000);
      await ledger.saveEntry(
        LedgerEntry(
          'income',
          Kind.income,
          50000,
          day,
          cash,
          null,
          salary.id,
          '',
        ),
      );
      expect(ledger.balances[cash], 125000);
      await ledger.saveAccount(
        const Account('bank', 'Bank', 'Bank', 200000, false),
      );
      await ledger.saveEntry(
        LedgerEntry(
          'transfer',
          Kind.transfer,
          30000,
          day,
          cash,
          'bank',
          null,
          '',
        ),
      );
      expect(ledger.balances, {cash: 95000, 'bank': 230000});
      await expectLater(
        ledger.saveEntry(
          LedgerEntry('bad', Kind.transfer, 30000, day, cash, cash, null, ''),
        ),
        throwsStateError,
      );
      await expectLater(
        ledger.saveEntry(
          LedgerEntry('bad', Kind.expense, 10, day, cash, null, salary.id, ''),
        ),
        throwsA(isA<DatabaseException>()),
      );
      await ledger.saveEntry(expense(35000));
      expect(ledger.balances[cash], 85000);
      await ledger.deleteEntry('transfer');
      expect(ledger.balances, {cash: 115000, 'bank': 200000});
      final monthly = ledger.monthly(DateTime(2026, 11));
      expect(Ledger.total(monthly, Kind.income), 50000);
      expect(Ledger.total(monthly, Kind.expense), 35000);
      expect(ledger.monthly(DateTime(2026, 10)), isEmpty);

      await ledger.saveCategory(Category(food.id, food.name, food.kind, true));
      await ledger.saveEntry(expense(35000));
      await expectLater(
        ledger.saveEntry(
          LedgerEntry('new', Kind.expense, 10, day, cash, null, food.id, ''),
        ),
        throwsStateError,
      );
      final backup = await ledger.export('correct password');
      await ledger.setAppLock(true);
      final expected = ledger.entries.map((e) => e.row).toList();
      await ledger.deleteEntry('expense');
      await expectLater(
        ledger.restore(backup, 'wrong password'),
        throwsA(anything),
      );
      expect(ledger.entries.single.id, 'income');
      await ledger.restore(backup, 'correct password');
      expect(ledger.appLockEnabled, isTrue);
      expect(ledger.entries.map((e) => e.row), expected);
      expect(ledger.balances, {cash: 115000, 'bank': 200000});
      expect(
        ledger.categories.singleWhere((c) => c.id == food.id).archived,
        isTrue,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
