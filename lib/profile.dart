import 'package:material_ui/material_ui.dart';

import 'forms.dart';
import 'ledger.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage(this.ledger, {super.key});
  final Ledger ledger;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with FormSave<ProfilePage> {
  late final name = TextEditingController(text: widget.ledger.profileName);

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: 'Your profile',
    formKey: formKey,
    saving: saving,
    fields: [
      const Align(
        alignment: Alignment.centerLeft,
        child: CircleAvatar(
          radius: 28,
          child: Icon(Icons.person_outline, size: 30),
        ),
      ),
      const Text('Your display name is stored on this device.'),
      TextFormField(
        controller: name,
        maxLength: 60,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(labelText: 'Display name'),
      ),
    ],
    onSave: () => save(() => widget.ledger.saveProfileName(name.text)),
  );
}
