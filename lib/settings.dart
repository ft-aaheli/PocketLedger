import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import 'app_lock.dart';
import 'forms.dart';
import 'ledger.dart';
import 'profile.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage(this.ledger, {super.key});
  final Ledger ledger;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Ledger get ledger => widget.ledger;
  bool busy = false;
  bool confirmingLock = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ledger,
    builder: (context, _) {
      final locked =
          ledger.entries.isNotEmpty ||
          ledger.accounts.any((a) => a.opening != 0);
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Profile'),
                  subtitle: Text(
                    ledger.profile.name.isEmpty
                        ? 'Add your full name'
                        : ledger.profile.name,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: busy
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => ProfilePage(ledger),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Add bank account'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: busy || confirmingLock
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                AccountPage(ledger, initialType: 'Bank'),
                          ),
                        ),
                ),
              ),
              if (DeviceLock.supported) ...[
                const SizedBox(height: 16),
                Card(
                  child: SwitchListTile(
                    secondary: const Icon(Icons.lock_outline),
                    title: const Text('App lock'),
                    subtitle: const Text(
                      'Require device confirmation to open PocketLedger.',
                    ),
                    value: ledger.appLockEnabled,
                    onChanged: busy || confirmingLock ? null : changeAppLock,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              dropdown(
                'Appearance',
                ledger.theme,
                {'system': 'System', 'light': 'Light', 'dark': 'Dark'},
                busy
                    ? null
                    : (value) => act(() => ledger.setting('theme', value!)),
                key: ValueKey(ledger.theme),
              ),
              const SizedBox(height: 16),
              dropdown(
                'Base currency',
                ledger.currency,
                {for (final code in currencies) code: code},
                locked || busy
                    ? null
                    : (value) => act(() => ledger.setting('currency', value!)),
                key: ValueKey(ledger.currency),
              ),
              if (locked)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Currency is fixed while there are entries or nonzero opening balances.',
                  ),
                ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Categories'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: busy
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => CategoriesPage(ledger),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              Text('Backups', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'PocketLedger keeps your records on this device. Save an encrypted backup before uninstalling or changing phones. You’ll need its password to restore it.',
              ),
              const SizedBox(height: 12),
              if (busy) const LinearProgressIndicator(),
              ListTile(
                leading: const Icon(Icons.file_upload_outlined),
                title: const Text('Export encrypted backup'),
                onTap: busy ? null : () => act(export),
              ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('Restore from backup'),
                onTap: busy ? null : () => act(restore),
              ),
            ],
          ),
        ),
      );
    },
  );

  Future<void> changeAppLock(bool enabled) async {
    setState(() => confirmingLock = true);
    try {
      if (await DeviceLock.confirm()) await ledger.setAppLock(enabled);
    } catch (error) {
      notice(DeviceLock.errorText(error));
    } finally {
      if (mounted) setState(() => confirmingLock = false);
    }
  }

  Future<void> act(Future<void> Function() operation) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await operation();
    } catch (_) {
      notice(
        'The operation failed. For restore, check the backup file and password.',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> export() async {
    final password = await requestPassword(context, exporting: true);
    if (password == null || !mounted) return;
    final bytes = await ledger.export(password);
    if (!mounted) return;
    if (bytes.length > backupSizeLimit) {
      notice('This ledger exceeds the 20 MB backup limit.');
      return;
    }
    final saved = await FilePicker.saveFile(
      fileName: 'PocketLedger-${dayKey(DateTime.now())}.plbackup',
      bytes: bytes,
    );
    if (saved != null) notice('Encrypted backup saved.');
  }

  Future<void> restore() async {
    final file = await FilePicker.pickFile();
    if (file == null || !mounted) return;
    final length = await file.length();
    if (length != null && length > backupSizeLimit) {
      notice('This backup exceeds the 20 MB restore limit.');
      return;
    }
    if (!mounted) return;
    final password = await requestPassword(context, exporting: false);
    if (password == null || !mounted) return;
    if (!await confirm(
      context,
      'Replace this ledger?',
      'Restoring replaces the accounts, entries, categories, and preferences on this device.',
      'Replace',
    )) {
      return;
    }
    final bytes = <int>[];
    await for (final chunk in file.readAsByteStream()) {
      if (bytes.length + chunk.length > backupSizeLimit) {
        throw const FormatException('Backup too large.');
      }
      bytes.addAll(chunk);
    }
    await ledger.restore(bytes, password);
    notice('Ledger restored.');
  }
}

Future<String?> requestPassword(
  BuildContext context, {
  required bool exporting,
}) => showDialog<String>(
  context: context,
  builder: (_) => _PasswordDialog(exporting),
);

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog(this.exporting);
  final bool exporting;
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final key = GlobalKey<FormState>();
  String password = '';

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(
      widget.exporting ? 'Set a backup password' : 'Enter backup password',
    ),
    content: Form(
      key: key,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            obscureText: true,
            onChanged: (value) => password = value,
            decoration: const InputDecoration(labelText: 'Password'),
            validator: (value) =>
                value == null || value.length < (widget.exporting ? 10 : 1)
                ? (widget.exporting
                      ? 'Use at least 10 characters.'
                      : 'Enter the backup password.')
                : null,
          ),
          if (widget.exporting) ...[
            const SizedBox(height: 12),
            TextFormField(
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm password'),
              validator: (value) =>
                  value != password ? 'Passwords must match.' : null,
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (key.currentState!.validate()) Navigator.pop(context, password);
        },
        child: const Text('Continue'),
      ),
    ],
  );
}

class CategoriesPage extends StatelessWidget {
  const CategoriesPage(this.ledger, {super.key});
  final Ledger ledger;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ledger,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => edit(context),
        icon: const Icon(Icons.add),
        label: const Text('New category'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
          children: [
            for (final kind in [Kind.expense, Kind.income]) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  kindLabel(kind),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final category in ledger.categories.where(
                (c) => c.kind == kind,
              ))
                Card(
                  child: ListTile(
                    title: Text(category.name),
                    subtitle: category.archived ? const Text('Archived') : null,
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => edit(context, category),
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
  );

  void edit(BuildContext context, [Category? category]) => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => _CategoryPage(ledger, category)),
  );
}

class _CategoryPage extends StatefulWidget {
  const _CategoryPage(this.ledger, this.category);
  final Ledger ledger;
  final Category? category;
  @override
  State<_CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<_CategoryPage>
    with FormSave<_CategoryPage> {
  late final name = TextEditingController(text: widget.category?.name ?? '');
  Kind kind = Kind.expense;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final old = widget.category;
    return FormPage(
      title: old == null ? 'New category' : 'Edit category',
      formKey: formKey,
      saving: saving,
      fields: [
        nameField(name, 'Category name'),
        if (old == null)
          dropdown('Type', kind.name, {
            for (final kind in [Kind.expense, Kind.income])
              kind.name: kindLabel(kind),
          }, (value) => setState(() => kind = Kind.values.byName(value!))),
        if (old != null)
          TextButton(
            onPressed: saving
                ? null
                : () async {
                    final archive = !old.archived;
                    if (!archive ||
                        await confirm(
                          context,
                          'Archive this category?',
                          'Existing entries keep this category.',
                          'Archive',
                        )) {
                      if (mounted) {
                        await save(
                          () => widget.ledger.saveCategory(
                            Category(old.id, old.name, old.kind, archive),
                          ),
                          validate: false,
                        );
                      }
                    }
                  },
            child: Text(
              old.archived ? 'Unarchive category' : 'Archive category',
            ),
          ),
      ],
      onSave: () => save(
        () => widget.ledger.saveCategory(
          Category(
            old?.id ?? newId(),
            name.text.trim(),
            old?.kind ?? kind,
            old?.archived ?? false,
          ),
        ),
      ),
    );
  }
}
