import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import 'forms.dart';
import 'ledger.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({required this.photo, required this.radius, super.key});

  final Uint8List? photo;
  final double radius;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: SizedBox.square(
      dimension: radius * 2,
      child: photo == null
          ? _placeholder()
          : Image.memory(
              photo!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _placeholder(),
            ),
    ),
  );

  Widget _placeholder() =>
      CircleAvatar(child: Icon(Icons.person_outline, size: radius));
}

class ProfilePage extends StatefulWidget {
  const ProfilePage(this.ledger, {super.key});
  final Ledger ledger;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with FormSave<ProfilePage> {
  late final profile = widget.ledger.profile;
  late final name = TextEditingController(text: profile.name);
  late final phone = TextEditingController(text: profile.phone);
  late final email = TextEditingController(text: profile.email);
  late final address = TextEditingController(text: profile.address);
  late Uint8List? photo = profile.photo;
  bool picking = false;

  @override
  void dispose() {
    for (final controller in [name, phone, email, address]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: 'Your profile',
    formKey: formKey,
    saving: saving || picking,
    fields: [
      Row(
        children: [
          ProfileAvatar(photo: photo, radius: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(
              children: [
                TextButton(
                  onPressed: picking || saving ? null : pickPhoto,
                  child: Text(photo == null ? 'Add photo' : 'Change photo'),
                ),
                if (photo != null)
                  TextButton(
                    onPressed: picking || saving
                        ? null
                        : () => setState(() => photo = null),
                    child: const Text('Remove'),
                  ),
              ],
            ),
          ),
        ],
      ),
      const Text('Profile details are optional and stay on this device.'),
      TextFormField(
        controller: name,
        maxLength: 100,
        keyboardType: TextInputType.name,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Full name'),
      ),
      TextFormField(
        controller: phone,
        maxLength: 40,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(labelText: 'Phone number'),
      ),
      TextFormField(
        controller: email,
        maxLength: 254,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'Email address'),
        validator: (value) {
          final text = value?.trim() ?? '';
          return text.isEmpty ||
                  RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)
              ? null
              : 'Enter a valid email address.';
        },
      ),
      TextFormField(
        controller: address,
        maxLength: 500,
        minLines: 2,
        maxLines: 4,
        keyboardType: TextInputType.streetAddress,
        decoration: const InputDecoration(labelText: 'Mailing address'),
      ),
    ],
    onSave: () => save(
      () => widget.ledger.saveProfile(
        LocalProfile(
          name: name.text,
          phone: phone.text,
          email: email.text,
          address: address.text,
          photo: photo,
        ),
      ),
    ),
  );

  Future<void> pickPhoto() async {
    const limit = 15 * 1024 * 1024;
    setState(() => picking = true);
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (!mounted || file == null) return;
      final data = BytesBuilder(copy: false);
      await for (final chunk in file.openRead()) {
        if (data.length + chunk.length > limit) {
          throw const FormatException('Choose an image smaller than 15 MB.');
        }
        data.add(chunk);
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(data.takeBytes());
      final codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (width, height) {
          const edge = 320;
          if (width <= edge && height <= edge) {
            return const ui.TargetImageSize();
          }
          return width >= height
              ? const ui.TargetImageSize(width: edge)
              : const ui.TargetImageSize(height: edge);
        },
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final png = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (mounted && png != null) {
            setState(() => photo = png.buffer.asUint8List());
          }
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException
                  ? error.message
                  : 'Could not open this image.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }
}
