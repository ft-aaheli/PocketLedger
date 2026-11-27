import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import 'app_lock.dart';
import 'ledger.dart';
import 'profile.dart';
import 'report_actions.dart';
import 'forms.dart';
import 'settings.dart';
import 'wallet_mascot.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    runApp(PocketLedger(await Ledger.open()));
  } catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack),
    );
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'PocketLedger could not open its local data. Close the app and try again.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const navy = Color(0xFF17243A);
const teal = Color(0xFF087F8C);

ThemeData appTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: teal, brightness: brightness);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: brightness == Brightness.light
        ? const Color(0xFFF7F9FC)
        : scheme.surface,
    textTheme: base.textTheme.copyWith(
      bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 16),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 25,
        fontWeight: FontWeight.w700,
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        textStyle: const TextStyle(fontSize: 16),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: brightness == Brightness.light
          ? Colors.white
          : scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .65)),
      ),
    ),
  );
}

class PocketLedger extends StatelessWidget {
  const PocketLedger(this.ledger, {super.key});
  final Ledger ledger;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ledger,
    builder: (context, _) => MaterialApp(
      title: 'PocketLedger',
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      themeMode: ThemeMode.values.byName(ledger.theme),
      builder: (context, child) => AppLockGate(
        enabled: DeviceLock.supported && ledger.appLockEnabled,
        child: child!,
      ),
      home: ledger.accounts.isEmpty ? SetupPage(ledger) : LedgerHome(ledger),
    ),
  );
}

class LedgerHome extends StatefulWidget {
  const LedgerHome(this.ledger, {super.key});
  final Ledger ledger;
  @override
  State<LedgerHome> createState() => _LedgerHomeState();
}

class _LedgerHomeState extends State<LedgerHome> {
  int tab = 0;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String search = '';
  Kind? filter;
  Ledger get ledger => widget.ledger;
  String format(int amount) => money(amount, ledger.currency);

  void show(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  Future<void> addEntry() async {
    final saved = await Navigator.of(context)
        .push<Kind>(MaterialPageRoute<Kind>(builder: (_) => EntryPage(ledger)));
    if (!mounted || saved == null) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (ledger.mascotEnabled) ...[
              const WalletMascot(celebrating: true),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(switch (saved) {
                Kind.expense => 'Expense recorded!',
                Kind.income => 'Income recorded!',
                Kind.transfer => 'Transfer complete!',
              }),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthly = ledger.monthly(month);
    final visibleEntries = monthly.where((entry) {
      if (filter != null && filter != entry.kind) return false;
      final searchable =
          '${entryTitle(ledger, entry)} ${entry.note} ${accountName(ledger, entry.source)} ${accountName(ledger, entry.destination)} ${format(entry.amount)}';
      return searchable.toLowerCase().contains(search.trim().toLowerCase());
    }).toList();
    final balances = ledger.balances;
    final titles = ['PocketLedger', 'Transactions', 'Accounts', 'Reports'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[tab]),
        actions: [
          if (tab == 0)
            IconButton(
              onPressed: () => show(ProfilePage(ledger)),
              tooltip: 'Your profile',
              icon: ProfileAvatar(photo: ledger.profile.photo, radius: 16),
            ),
          IconButton(
            onPressed: () => show(SettingsPage(ledger)),
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: 'Accounts',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            label: 'Reports',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addEntry,
        icon: const Icon(Icons.add),
        label: const Text('Add entry'),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (tab == 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: balanceCard(balances),
              ),
            Expanded(
              child: ListView(
                key: ValueKey(tab),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: switch (tab) {
                  0 => [
                    monthPicker(),
                    summary(monthly),
                    section(
                      'Recent entries',
                      TextButton(
                        onPressed: openStatement,
                        child: const Text('View all'),
                      ),
                    ),
                    if (monthly.isEmpty)
                      empty(
                        'No entries this month',
                        ledger.entries.isEmpty
                            ? 'Tap Add entry to record your first transaction.'
                            : 'Select another month to view earlier entries.',
                      ),
                    ...monthly.take(5).map((entry) => entryTile(entry)),
                  ],
                  1 => [
                    monthPicker(),
                    TextFormField(
                      initialValue: search,
                      onChanged: (value) => setState(() => search = value),
                      decoration: const InputDecoration(
                        labelText: 'Search transactions',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final kind in <Kind?>[null, ...Kind.values])
                          ChoiceChip(
                            label: Text(kind == null ? 'All' : kindLabel(kind)),
                            selected: filter == kind,
                            onSelected: (_) => setState(() => filter = kind),
                          ),
                      ],
                    ),
                    if (visibleEntries.isEmpty)
                      empty(
                        'No matching entries',
                        'Try a different month or search.',
                      ),
                    for (
                      var index = 0;
                      index < visibleEntries.length;
                      index++
                    ) ...[
                      if (index == 0 ||
                          visibleEntries[index - 1].day !=
                              visibleEntries[index].day)
                        section(
                          DateFormat(
                            'EEE, d MMM',
                          ).format(DateTime.parse(visibleEntries[index].day)),
                        ),
                      entryTile(visibleEntries[index]),
                    ],
                  ],
                  2 => [
                    section(
                      'Your accounts',
                      TextButton.icon(
                        onPressed: () => show(AccountPage(ledger)),
                        icon: const Icon(Icons.add),
                        label: const Text('New account'),
                      ),
                    ),
                    for (final account in ledger.accounts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(
                                Icons.account_balance_wallet_outlined,
                              ),
                            ),
                            title: Text(account.name),
                            subtitle: Text(
                              '${account.type}${account.archived ? ' · Archived' : ''}',
                            ),
                            trailing: SizedBox(
                              width: 132,
                              child: Text(
                                format(balances[account.id]!),
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            onTap: () =>
                                show(AccountPage(ledger, account: account)),
                          ),
                        ),
                      ),
                  ],
                  _ => [
                    monthPicker(),
                    section('Monthly summary'),
                    summary(monthly),
                    const SizedBox(height: 8),
                    figure(
                      'Net cash flow',
                      format(
                        Ledger.total(monthly, Kind.income) -
                            Ledger.total(monthly, Kind.expense),
                      ),
                      Icons.account_balance_wallet_outlined,
                      Theme.of(context).colorScheme.primary,
                    ),
                    section(
                      'Transaction statement',
                      TextButton(
                        onPressed: openStatement,
                        child: const Text('View transactions'),
                      ),
                    ),
                    if (monthly.isEmpty)
                      const Text('No transactions for this month.'),
                    ReportActions(ledger, month),
                    section('Expenses by category'),
                    ExpenseBreakdown(ledger, monthly),
                  ],
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void openStatement() => setState(() {
    tab = 1;
    search = '';
    filter = null;
  });

  Widget balanceCard(Map<String, int> balances) {
    int totalFor(String type) => ledger.accounts
        .where((account) => account.type == type)
        .fold(0, (sum, account) => sum + balances[account.id]!);

    Widget amount(int cents, double fontSize) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        format(cents),
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    Widget subtotal(String label, int cents) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFFCFDBED))),
          amount(cents, 19),
        ],
      ),
    );

    return Card(
      color: navy,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total balance',
                        style: TextStyle(color: Color(0xFFCFDBED)),
                      ),
                      amount(
                        balances.values.fold(0, (sum, value) => sum + value),
                        32,
                      ),
                    ],
                  ),
                ),
                if (ledger.mascotEnabled) ...[
                  const SizedBox(width: 12),
                  const WalletMascot(),
                ],
              ],
            ),
            const Divider(color: Color(0xFF45546D), height: 16),
            Row(
              children: [
                subtotal('Bank', totalFor('Bank')),
                const SizedBox(width: 12),
                subtotal('Cash', totalFor('Cash')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget monthPicker() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          onPressed: () => changeMonth(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            DateFormat('MMMM yyyy').format(month),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          onPressed: () => changeMonth(1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    ),
  );

  void changeMonth(int step) =>
      setState(() => month = DateTime(month.year, month.month + step));

  Widget summary(List<LedgerEntry> entries) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: figure(
          'Income',
          format(Ledger.total(entries, Kind.income)),
          Icons.south_west,
          const Color(0xFF16865D),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: figure(
          'Expenses',
          format(Ledger.total(entries, Kind.expense)),
          Icons.north_east,
          const Color(0xFFD94F59),
        ),
      ),
    ],
  );

  Widget entryTile(LedgerEntry entry) {
    final sign = switch (entry.kind) {
      Kind.income => '+',
      Kind.expense => '−',
      Kind.transfer => '',
    };
    final source = accountName(ledger, entry.source);
    final route = entry.destination == null
        ? source
        : '$source → ${accountName(ledger, entry.destination)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: CircleAvatar(
            child: Icon(switch (entry.kind) {
              Kind.income => Icons.south_west,
              Kind.expense => Icons.north_east,
              Kind.transfer => Icons.swap_horiz,
            }),
          ),
          title: Text(entryTitle(ledger, entry)),
          subtitle: Text(
            entry.note.isEmpty ? route : '$route · ${entry.note}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: SizedBox(
            width: 125,
            child: Text(
              '$sign${format(entry.amount)}',
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
          onTap: () => show(EntryPage(ledger, entry: entry)),
        ),
      ),
    );
  }
}

Widget figure(String label, String value, IconData icon, Color color) => Card(
  child: Padding(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 8),
        Text(label),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  ),
);

Widget section(String label, [Widget? action]) => Padding(
  padding: const EdgeInsets.only(top: 16, bottom: 8),
  child: Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      ?action,
    ],
  ),
);

Widget empty(String title, String description) => Card(
  child: Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(description),
      ],
    ),
  ),
);

class ExpenseBreakdown extends StatelessWidget {
  const ExpenseBreakdown(this.ledger, this.entries, {super.key});
  final Ledger ledger;
  final List<LedgerEntry> entries;

  static const colors = [
    Color(0xFF087F8C),
    Color(0xFF8A5BB8),
    Color(0xFFD94F59),
    Color(0xFF477AC2),
    Color(0xFFB46D13),
    Color(0xFF16865D),
  ];

  @override
  Widget build(BuildContext context) {
    final totals = <String, int>{};
    for (final entry in entries.where((e) => e.kind == Kind.expense)) {
      totals.update(
        entry.category!,
        (amount) => amount + entry.amount,
        ifAbsent: () => entry.amount,
      );
    }
    if (totals.isEmpty) {
      return empty(
        'No expenses this month',
        'Your spending breakdown will appear here.',
      );
    }
    final items = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = items.fold(0, (sum, item) => sum + item.value);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ExcludeSemantics(
              child: SizedBox(
                width: 146,
                height: 146,
                child: CustomPaint(
                  painter: _Donut(
                    items.map((item) => item.value / total).toList(),
                  ),
                  child: const Center(
                    child: Icon(Icons.pie_chart_outline, size: 32),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            for (final (index, item) in items.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.circle,
                  color: colors[index % colors.length],
                  size: 16,
                ),
                title: Text(
                  ledger.categories.firstWhere((c) => c.id == item.key).name,
                ),
                subtitle: Text(
                  '${(100 * item.value / total).round()}% of expenses',
                ),
                trailing: Text(
                  money(item.value, ledger.currency),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Donut extends CustomPainter {
  const _Donut(this.shares);
  final List<double> shares;

  @override
  void paint(Canvas canvas, Size size) {
    const turn = 6.283185307179586;
    var start = -turn / 4;
    final rect = (Offset.zero & size).deflate(10);
    for (final (index, share) in shares.indexed) {
      final sweep = turn * share;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 17
          ..color =
              ExpenseBreakdown.colors[index % ExpenseBreakdown.colors.length],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _Donut oldDelegate) =>
      shares != oldDelegate.shares;
}
