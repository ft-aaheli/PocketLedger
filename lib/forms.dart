import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import 'ledger.dart';

String kindLabel(Kind kind) => switch (kind) {
  Kind.expense => 'Expense',
  Kind.income => 'Income',
  Kind.transfer => 'Transfer',
};

String accountName(Ledger ledger, String? id) =>
    ledger.accounts.where((a) => a.id == id).firstOrNull?.name ?? '';

String entryTitle(Ledger ledger, LedgerEntry entry) =>
    entry.kind == Kind.transfer
    ? 'Transfer'
    : ledger.categories
          .firstWhere((category) => category.id == entry.category)
          .name;

Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
  String action,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

class FormPage extends StatelessWidget {
  const FormPage({
    super.key,
    required this.title,
    required this.formKey,
    required this.fields,
    required this.onSave,
    this.action = 'Save',
    this.saving = false,
  });
  final String title, action;
  final GlobalKey<FormState> formKey;
  final List<Widget> fields;
  final VoidCallback onSave;
  final bool saving;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      child: Form(
        key: formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            for (final field in fields)
              Padding(padding: const EdgeInsets.only(bottom: 16), child: field),
            FilledButton(
              onPressed: saving ? null : onSave,
              child: Text(saving ? 'Saving…' : action),
            ),
          ],
        ),
      ),
    ),
  );
}

mixin FormSave<T extends StatefulWidget> on State<T> {
  final formKey = GlobalKey<FormState>();
  bool saving = false;

  Future<void> save(
    Future<void> Function() write, {
    bool close = true,
    bool validate = true,
  }) async {
    if (saving || (validate && !formKey.currentState!.validate())) return;
    FocusScope.of(context).unfocus();
    setState(() => saving = true);
    try {
      await write();
      if (mounted && close && ModalRoute.isCurrentOf(context) == true) {
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError
                  ? error.message.toString()
                  : 'Could not save. Check the form and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

Widget amountField(
  TextEditingController controller,
  String label, {
  bool signed = false,
}) => TextFormField(
  controller: controller,
  keyboardType: TextInputType.numberWithOptions(decimal: true, signed: signed),
  decoration: InputDecoration(labelText: label, hintText: '0.00'),
  validator: (value) {
    final amount = minorUnits(value ?? '');
    if (amount == null) return 'Enter an amount with up to two decimal places.';
    if (!signed && amount <= 0) return 'Enter an amount greater than zero.';
    return null;
  },
);

Widget nameField(TextEditingController controller, String label) =>
    TextFormField(
      controller: controller,
      textCapitalization: TextCapitalization.words,
      maxLength: 60,
      decoration: InputDecoration(labelText: label, counterText: ''),
      validator: (value) =>
          (value ?? '').trim().isEmpty ? 'Enter a name.' : null,
    );

DropdownButtonFormField<String> dropdown(
  String label,
  String? value,
  Map<String, String> choices,
  ValueChanged<String?>? changed, {
  Key? key,
}) => DropdownButtonFormField<String>(
  key: key,
  isExpanded: true,
  initialValue: choices.containsKey(value) ? value : null,
  decoration: InputDecoration(labelText: label),
  items: [
    for (final option in choices.entries)
      DropdownMenuItem(
        value: option.key,
        child: Text(option.value, overflow: TextOverflow.ellipsis),
      ),
  ],
  onChanged: choices.isEmpty ? null : changed,
  validator: (value) => value == null ? 'Choose an option.' : null,
);

class SetupPage extends StatefulWidget {
  const SetupPage(this.ledger, {super.key});
  final Ledger ledger;
  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> with FormSave<SetupPage> {
  final name = TextEditingController(text: 'Cash');
  final opening = TextEditingController(text: '0.00');
  String currency = 'INR';
  String type = 'Cash';

  @override
  void dispose() {
    name.dispose();
    opening.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: 'PocketLedger',
    formKey: formKey,
    saving: saving,
    action: 'Create ledger',
    fields: [
      const Align(
        alignment: Alignment.centerLeft,
        child: CircleAvatar(
          radius: 30,
          child: Icon(Icons.account_balance_wallet_outlined, size: 28),
        ),
      ),
      Text(
        'Set up your ledger',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const Text(
        'Choose a currency and add the account you’ll use first. Your records stay on this device.',
      ),
      dropdown('Currency', currency, {
        for (final code in currencies) code: code,
      }, (value) => setState(() => currency = value!)),
      dropdown(
        'Account type',
        type,
        {for (final choice in accountTypes) choice: choice},
        (value) {
          if (value == null) return;
          setState(() {
            if (name.text == type) name.text = value;
            type = value;
          });
        },
      ),
      nameField(name, 'First account'),
      amountField(opening, 'Opening balance', signed: true),
    ],
    onSave: () => save(
      () => widget.ledger.setup(
        currency,
        name.text.trim(),
        minorUnits(opening.text)!,
        type: type,
      ),
      close: false,
    ),
  );
}

class EntryPage extends StatefulWidget {
  const EntryPage(this.ledger, {super.key, this.entry});
  final Ledger ledger;
  final LedgerEntry? entry;
  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<EntryPage> with FormSave<EntryPage> {
  late Kind kind;
  String? source, destination, category;
  late DateTime date;
  late TextEditingController amount, note;
  Ledger get ledger => widget.ledger;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    kind = entry?.kind ?? Kind.expense;
    source =
        entry?.source ??
        ledger.accounts.where((a) => !a.archived).firstOrNull?.id;
    destination = entry?.destination;
    category = entry?.category;
    date = entry == null ? DateTime.now() : DateTime.parse(entry.day);
    amount = TextEditingController(
      text: entry == null ? '' : decimalAmount(entry.amount),
    );
    note = TextEditingController(text: entry?.note ?? '');
  }

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Map<String, String> accountChoices(String? original) => {
    for (final a in ledger.accounts)
      if (!a.archived || a.id == original)
        a.id: '${a.name}${a.archived ? ' (archived)' : ''}',
  };

  @override
  Widget build(BuildContext context) {
    final sources = accountChoices(widget.entry?.source);
    final destinations = accountChoices(widget.entry?.destination)
      ..remove(source);
    final categories = {
      for (final c in ledger.categories)
        if (c.kind == kind && (!c.archived || c.id == widget.entry?.category))
          c.id: '${c.name}${c.archived ? ' (archived)' : ''}',
    };
    return FormPage(
      title: widget.entry == null ? 'Add entry' : 'Edit entry',
      formKey: formKey,
      saving: saving,
      fields: [
        Wrap(
          spacing: 8,
          children: [
            for (final option in Kind.values)
              ChoiceChip(
                label: Text(kindLabel(option)),
                selected: kind == option,
                onSelected: (_) {
                  if (kind != option) {
                    setState(() {
                      kind = option;
                      category = null;
                    });
                  }
                },
              ),
          ],
        ),
        amountField(amount, 'Amount (${ledger.currency})'),
        OutlinedButton.icon(
          onPressed: saving ? null : selectDate,
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text(DateFormat('EEE, d MMM yyyy').format(date)),
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
        ),
        if (sources.isEmpty)
          const Text('Create or restore an active account from Accounts.'),
        dropdown(
          kind == Kind.transfer ? 'From account' : 'Account',
          source,
          sources,
          (value) => setState(() {
            source = value;
            if (destination == value) destination = null;
          }),
        ),
        if (kind == Kind.transfer) ...[
          if (destinations.isEmpty)
            const Text('Transfers require two distinct accounts.'),
          dropdown(
            'To account',
            destination,
            destinations,
            (value) => setState(() => destination = value),
            key: ValueKey(source),
          ),
        ] else ...[
          if (categories.isEmpty)
            const Text('Add an active category in Settings.'),
          dropdown(
            'Category',
            category,
            categories,
            (value) => setState(() => category = value),
            key: ValueKey(kind),
          ),
        ],
        TextFormField(
          controller: note,
          maxLength: 500,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        if (widget.entry != null)
          TextButton.icon(
            onPressed: saving ? null : delete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete entry'),
          ),
      ],
      onSave: () => save(
        () => ledger.saveEntry(
          LedgerEntry(
            widget.entry?.id ?? newId(),
            kind,
            minorUnits(amount.text)!,
            dayKey(date),
            source!,
            kind == Kind.transfer ? destination : null,
            kind == Kind.transfer ? null : category,
            note.text.trim(),
          ),
        ),
      ),
    );
  }

  Future<void> selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200, 12, 31),
    );
    if (mounted && selected != null) setState(() => date = selected);
  }

  Future<void> delete() async {
    if (await confirm(
          context,
          'Delete this entry?',
          'Its effect on your balances will be reversed.',
          'Delete',
        ) &&
        mounted) {
      await save(() => ledger.deleteEntry(widget.entry!.id), validate: false);
    }
  }
}

class AccountPage extends StatefulWidget {
  const AccountPage(this.ledger, {super.key, this.account});
  final Ledger ledger;
  final Account? account;
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> with FormSave<AccountPage> {
  late final name = TextEditingController(text: widget.account?.name ?? '');
  late final opening = TextEditingController(
    text: decimalAmount(widget.account?.opening ?? 0),
  );
  late String type = widget.account?.type ?? 'Cash';

  @override
  void dispose() {
    name.dispose();
    opening.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final old = widget.account;
    return FormPage(
      title: old == null ? 'New account' : 'Edit account',
      formKey: formKey,
      saving: saving,
      fields: [
        nameField(name, 'Account name'),
        dropdown('Account type', type, {
          for (final type in accountTypes) type: type,
        }, (value) => setState(() => type = value!)),
        amountField(opening, 'Opening balance', signed: true),
        if (old != null)
          TextButton(
            onPressed: saving
                ? null
                : () async {
                    final archive = !old.archived;
                    if (!archive ||
                        await confirm(
                          context,
                          'Archive this account?',
                          'Its balance and history stay in your ledger.',
                          'Archive',
                        )) {
                      if (mounted) {
                        await save(
                          () => widget.ledger.saveAccount(
                            Account(
                              old.id,
                              old.name,
                              old.type,
                              old.opening,
                              archive,
                            ),
                          ),
                          validate: false,
                        );
                      }
                    }
                  },
            child: Text(old.archived ? 'Unarchive account' : 'Archive account'),
          ),
      ],
      onSave: () => save(
        () => widget.ledger.saveAccount(
          Account(
            old?.id ?? newId(),
            name.text.trim(),
            type,
            minorUnits(opening.text)!,
            old?.archived ?? false,
          ),
        ),
      ),
    );
  }
}
