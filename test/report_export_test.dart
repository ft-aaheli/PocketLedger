import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketledger/ledger.dart';
import 'package:pocketledger/report_export.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'exports monthly totals, numeric Excel cells and literal notes',
    () async {
      final ledger = await Ledger.open(inMemoryDatabasePath);
      addTearDown(ledger.db.close);
      await ledger.setup('INR', 'Cash', 10000);
      final cash = ledger.accounts.single.id;
      await ledger.saveAccount(const Account('bank', 'Bank', 'Bank', 0, false));
      final expense = ledger.categories.firstWhere(
        (c) => c.kind == Kind.expense,
      );
      final income = ledger.categories.firstWhere((c) => c.kind == Kind.income);
      for (final entry in [
        LedgerEntry(
          'a',
          Kind.expense,
          525,
          '2026-11-04',
          cash,
          null,
          expense.id,
          '=1+1',
        ),
        LedgerEntry(
          'b',
          Kind.income,
          1500,
          '2026-11-03',
          cash,
          null,
          income.id,
          '',
        ),
        LedgerEntry(
          'c',
          Kind.transfer,
          1000,
          '2026-11-02',
          cash,
          'bank',
          null,
          '',
        ),
        LedgerEntry(
          'd',
          Kind.income,
          9900,
          '2026-10-31',
          cash,
          null,
          income.id,
          '',
        ),
      ]) {
        await ledger.saveEntry(entry);
      }

      final report = MonthlyReport(ledger, DateTime(2026, 11));
      final workbook = Excel.decodeBytes(report.excel());
      final summary = workbook['Summary'].rows;
      final transactions = workbook['Transactions'].rows;
      expect(report.filename(ReportFormat.excel), 'PocketLedger-2026-11.xlsx');
      expect(summary[2][1]!.value, IntCellValue(15));
      expect(summary[3][1]!.value, DoubleCellValue(5.25));
      expect(summary[4][1]!.value, DoubleCellValue(9.75));
      expect(transactions, hasLength(4));
      expect(transactions[1][6]!.value, TextCellValue('=1+1'));
      expect(transactions[3][4]!.value, TextCellValue('Bank'));

      final pdf = await report.pdf(
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
        await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf'),
      );
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      expect(pdf.length, greaterThan(1000));
    },
  );
}
