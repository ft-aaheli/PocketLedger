import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import 'ledger.dart';
import 'report_export.dart';

class ReportActions extends StatefulWidget {
  const ReportActions(this.ledger, this.month, {super.key});
  final Ledger ledger;
  final DateTime month;

  @override
  State<ReportActions> createState() => _ReportActionsState();
}

class _ReportActionsState extends State<ReportActions> {
  bool busy = false;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final format in ReportFormat.values)
              OutlinedButton.icon(
                onPressed: busy ? null : () => _export(format, share: false),
                icon: const Icon(Icons.download_outlined),
                label: Text(format.label),
              ),
            Builder(
              builder: (buttonContext) => FilledButton.tonalIcon(
                onPressed: busy
                    ? null
                    : () => _chooseShareFormat(buttonContext),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share report'),
              ),
            ),
          ],
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(semanticsLabel: 'Preparing report'),
          ),
      ],
    ),
  );

  Future<void> _chooseShareFormat(BuildContext buttonContext) async {
    final box = buttonContext.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    final format = await showModalBottomSheet<ReportFormat>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final format in ReportFormat.values)
              ListTile(
                leading: Icon(
                  format == ReportFormat.pdf
                      ? Icons.picture_as_pdf_outlined
                      : Icons.table_chart_outlined,
                ),
                title: Text('Share ${format.label}'),
                subtitle: Text(
                  format == ReportFormat.excel
                      ? 'Summary and transaction details'
                      : 'Monthly summary and expense breakdown',
                ),
                onTap: () => Navigator.pop(context, format),
              ),
          ],
        ),
      ),
    );
    if (mounted && format != null) {
      await _export(format, share: true, origin: origin);
    }
  }

  Future<void> _export(
    ReportFormat format, {
    required bool share,
    Rect? origin,
  }) async {
    if (busy) return;

    final report = MonthlyReport(widget.ledger, widget.month);
    final name = report.filename(format);
    setState(() => busy = true);
    try {
      final bytes = switch (format) {
        ReportFormat.excel => await compute((report) => report.excel(), report),
        ReportFormat.pdf => await _createPdf(report),
      };
      if (!mounted) return;
      if (share) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile.fromData(bytes, mimeType: format.mimeType)],
            fileNameOverrides: [name],
            sharePositionOrigin: origin,
          ),
        );
      } else {
        final saved = await FilePicker.saveFile(
          fileName: name,
          bytes: bytes,
          mimeType: format.mimeType,
        );
        if (saved != null) _notice('${format.label} report saved.');
      }
    } catch (_) {
      _notice(
        'Could not ${share ? 'share' : 'save'} the ${format.label} report.',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<Uint8List> _createPdf(MonthlyReport report) async {
    final fonts = await Future.wait([
      rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
      rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf'),
    ]);
    return compute((input) => input.$1.pdf(input.$2[0], input.$2[1]), (
      report,
      fonts,
    ));
  }

  void _notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }
}
