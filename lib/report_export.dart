import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'ledger.dart';

enum ReportFormat {
  excel(
    'Excel',
    'xlsx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  ),
  pdf('PDF', 'pdf', 'application/pdf');

  const ReportFormat(this.label, this.extension, this.mimeType);
  final String label, extension, mimeType;
}

typedef ReportEntry = ({
  String day,
  Kind kind,
  String category,
  String account,
  String destination,
  int amount,
  String note,
});

class MonthlyReport {
  MonthlyReport(Ledger ledger, this.month)
    : currency = ledger.currency,
      rows = _collect(ledger, month);

  final DateTime month;
  final String currency;
  final List<ReportEntry> rows;

  static List<ReportEntry> _collect(Ledger ledger, DateTime month) {
    final accounts = {
      for (final account in ledger.accounts) account.id: account.name,
    };
    final categories = {
      for (final category in ledger.categories) category.id: category.name,
    };
    return [
      for (final entry in ledger.monthly(month))
        (
          day: entry.day,
          kind: entry.kind,
          category: categories[entry.category] ?? '',
          account: accounts[entry.source] ?? '',
          destination: accounts[entry.destination] ?? '',
          amount: entry.amount,
          note: entry.note,
        ),
    ];
  }

  String get period => DateFormat('MMMM yyyy').format(month);

  String filename(ReportFormat format) =>
      'PocketLedger-${DateFormat('yyyy-MM').format(month)}.${format.extension}';

  int total(Kind kind) => rows
      .where((row) => row.kind == kind)
      .fold(0, (sum, row) => sum + row.amount);

  List<(String, int)> get categoryExpenses {
    final totals = <String, int>{};
    for (final row in rows.where((row) => row.kind == Kind.expense)) {
      totals.update(
        row.category,
        (total) => total + row.amount,
        ifAbsent: () => row.amount,
      );
    }
    return totals.entries.map((item) => (item.key, item.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
  }

  Uint8List excel() {
    final book = Excel.createExcel();
    book.rename('Sheet1', 'Summary');
    final summary = book['Summary'];
    final transactions = book['Transactions'];
    summary.setColumnWidth(0, 28);
    summary.setColumnWidth(1, 20);
    for (final (index, width) in <double>[14, 12, 22, 22, 22, 18, 40].indexed) {
      transactions.setColumnWidth(index, width);
    }
    final income = total(Kind.income);
    final expenses = total(Kind.expense);

    void textRow(Sheet sheet, List<String> values) =>
        sheet.appendRow(values.map(TextCellValue.new).toList());

    void amountRow(String label, int minor) =>
        summary.appendRow([TextCellValue(label), DoubleCellValue(minor / 100)]);

    textRow(summary, ['PocketLedger', period]);
    textRow(summary, ['Currency', currency]);
    amountRow('Income', income);
    amountRow('Expenses', expenses);
    amountRow('Net cash flow', income - expenses);
    summary.appendRow([]);
    textRow(summary, ['Expense category', 'Amount ($currency)']);
    for (final (name, amount) in categoryExpenses) {
      amountRow(name, amount);
    }
    textRow(transactions, [
      'Date',
      'Type',
      'Category',
      'Account',
      'To account',
      'Amount ($currency)',
      'Note',
    ]);
    for (final row in rows) {
      transactions.appendRow([
        TextCellValue(row.day),
        TextCellValue(row.kind.name),
        TextCellValue(row.category),
        TextCellValue(row.account),
        TextCellValue(row.destination),
        DoubleCellValue(row.amount / 100),
        TextCellValue(row.note),
      ]);
    }
    final bytes = book.encode();
    if (bytes == null) throw StateError('Could not encode the spreadsheet.');
    return Uint8List.fromList(bytes);
  }

  Future<Uint8List> pdf(ByteData latinFont, ByteData devanagariFont) {
    final document = pw.Document(title: 'PocketLedger – $period');
    final font = pw.Font.ttf(latinFont);
    final theme = pw.ThemeData.withFont(
      base: font,
      bold: font,
      fontFallback: [pw.Font.ttf(devanagariFont)],
    );
    final income = total(Kind.income);
    final expenses = total(Kind.expense);
    final categories = categoryExpenses;
    String display(int value) => '$currency ${decimalAmount(value)}';

    document.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        maxPages: categories.length + 2,
        header: (_) => pw.Text(
          'PocketLedger  |  $period',
          style: pw.TextStyle(fontSize: 20, color: PdfColors.blueGrey900),
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
        build: (_) => [
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: ['Cash flow', 'Amount'],
            data: [
              ['Income', display(income)],
              ['Expenses', display(expenses)],
              ['Net cash flow', display(income - expenses)],
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Text('Transfers are excluded from cash-flow totals.'),
          pw.SizedBox(height: 20),
          if (categories.isEmpty)
            pw.Text('No expenses for this month.')
          else
            pw.TableHelper.fromTextArray(
              headers: ['Expense category', 'Amount'],
              data: [
                for (final (name, amount) in categories)
                  [name, display(amount)],
              ],
            ),
        ],
      ),
    );
    return document.save();
  }
}
