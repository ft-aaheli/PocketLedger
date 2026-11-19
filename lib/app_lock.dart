import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class DeviceLock {
  static const _channel = MethodChannel('pocketledger/device_lock');

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  static String get unlockDescription => _isIOS
      ? 'Unlock with Face ID, Touch ID, or your device passcode.'
      : 'Unlock with your Android PIN, pattern, or password.';

  static Future<bool> confirm() async =>
      await _channel.invokeMethod<bool>('confirm') ?? false;

  static String errorText(Object error) =>
      error is PlatformException && error.code == 'no_screen_lock'
      ? (_isIOS
            ? 'Set a device passcode in Settings, then try again.'
            : 'Set a PIN, pattern, or password in Android Settings, then try again.')
      : 'Device confirmation is unavailable. Try again.';
}

class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  late bool locked = widget.enabled;
  bool confirming = false;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant AppLockGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      // Settings changes the flag only after the device verifies the credential.
      locked = false;
      error = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.enabled &&
        !locked &&
        (state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused)) {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        locked = true;
        error = null;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> unlock() async {
    if (confirming) return;
    setState(() {
      confirming = true;
      error = null;
    });
    try {
      final verified = await DeviceLock.confirm();
      if (mounted && verified) setState(() => locked = false);
    } catch (failure) {
      if (mounted) setState(() => error = DeviceLock.errorText(failure));
    } finally {
      if (mounted) setState(() => confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Offstage(
        offstage: locked,
        child: TickerMode(
          enabled: !locked,
          child: ExcludeFocus(excluding: locked, child: widget.child),
        ),
      ),
      if (locked)
        Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'PocketLedger is locked',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      DeviceLock.unlockDescription,
                      textAlign: TextAlign.center,
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: confirming ? null : unlock,
                      child: Text(
                        confirming
                            ? 'Waiting for device confirmation…'
                            : 'Unlock PocketLedger',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
