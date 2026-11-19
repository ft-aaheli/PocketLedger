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
      rows = _collect(ledger, month),
      contact = (
        name: ledger.profile.name,
        phone: ledger.profile.phone,
        email: ledger.profile.email,
        address: ledger.profile.address,
      );

  final DateTime month;
  final String currency;
  final List<ReportEntry> rows;
  final ({String name, String phone, String email, String address}) contact;

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
    const ink = PdfColor.fromInt(0xFF17243A);
    const accent = PdfColor.fromInt(0xFF087F8C);
    const paper = PdfColor.fromInt(0xFFF1F6F8);
    final document = pw.Document(title: 'PocketLedger | $period');
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
    String singleLine(String value) =>
        value.replaceAll(RegExp(r'\s+'), ' ').trim();

    pw.Widget heading(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 16, bottom: 8),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 15, color: accent),
      ),
    );

    pw.Table table(
      List<String> columns,
      List<List<String>> data, {
      Map<int, pw.TableColumnWidth>? widths,
    }) => pw.TableHelper.fromTextArray(
      headers: columns,
      data: data,
      columnWidths: widths,
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: .35),
      ),
      headerDecoration: const pw.BoxDecoration(color: ink),
      headerStyle: const pw.TextStyle(color: PdfColors.white, fontSize: 9),
      cellStyle: const pw.TextStyle(color: ink, fontSize: 9),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      cellAlignments: {columns.length - 1: pw.Alignment.centerRight},
      headerAlignments: {columns.length - 1: pw.Alignment.centerRight},
    );

    final details = [
      if (contact.phone.isNotEmpty) 'Phone: ${singleLine(contact.phone)}',
      if (contact.email.isNotEmpty) 'Email: ${singleLine(contact.email)}',
      if (contact.address.isNotEmpty) 'Address: ${singleLine(contact.address)}',
    ];

    document.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 28, 36, 26),
        maxPages: rows.length + categories.length + 4,
        header: (_) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 10),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: accent, width: 2)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'PocketLedger',
                style: const pw.TextStyle(fontSize: 20, color: ink),
              ),
              pw.Text(
                period,
                style: const pw.TextStyle(fontSize: 11, color: accent),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Monthly ledger statement  |  $currency',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ),
        ),
        build: (_) => [
          if (contact.name.isNotEmpty || details.isNotEmpty)
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 14),
              padding: const pw.EdgeInsets.all(12),
              color: paper,
              width: double.infinity,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (contact.name.isNotEmpty)
                    pw.Text(
                      singleLine(contact.name),
                      style: const pw.TextStyle(fontSize: 15, color: ink),
                    ),
                  for (final item in details)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 3),
                      child: pw.Text(
                        item,
                        style: const pw.TextStyle(fontSize: 9, color: ink),
                      ),
                    ),
                ],
              ),
            ),
          heading('Monthly summary'),
          table(
            ['Cash flow', 'Amount'],
            [
              ['Income', display(income)],
              ['Expenses', display(expenses)],
              ['Net cash flow', display(income - expenses)],
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Transfers are excluded from cash-flow totals.',
            style: const pw.TextStyle(fontSize: 9),
          ),
          if (categories.isNotEmpty) ...[
            heading('Expense breakdown'),
            table(
              ['Category', 'Amount'],
              [
                for (final (name, amount) in categories)
                  [singleLine(name), display(amount)],
              ],
            ),
          ],
          heading('Transaction statement'),
          if (rows.isEmpty)
            pw.Text('No transactions for this month.')
          else
            table(
              ['Date', 'Type', 'Details', 'Amount'],
              [
                for (final row in rows)
                  [
                    row.day,
                    switch (row.kind) {
                      Kind.income => 'Income',
                      Kind.expense => 'Expense',
                      Kind.transfer => 'Transfer',
                    },
                    [
                      if (row.category.isNotEmpty) singleLine(row.category),
                      if (row.destination.isEmpty)
                        singleLine(row.account)
                      else
                        '${singleLine(row.account)} to ${singleLine(row.destination)}',
                      if (row.note.trim().isNotEmpty) singleLine(row.note),
                    ].join('\n'),
                    display(row.amount),
                  ],
              ],
              widths: const {
                0: pw.FixedColumnWidth(69),
                1: pw.FixedColumnWidth(63),
                2: pw.FlexColumnWidth(),
                3: pw.FixedColumnWidth(104),
              },
            ),
        ],
      ),
    );
    return document.save();
  }
}
