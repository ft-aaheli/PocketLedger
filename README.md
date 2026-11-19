# PocketLedger

PocketLedger is a Flutter personal money manager for Android. Its SQLite database stays in app-private storage. The app works without sign-in or a backend.

## Run on Android

Use Flutter 3.50.0, a JDK compatible with Gradle 9, and the Android SDK. Run `flutter doctor` to check local setup and `flutter doctor --android-licenses` if necessary.

1. Open this directory in Android Studio with its Flutter plugin installed.
2. Start a virtual device in Device Manager, or plug in a phone with USB debugging enabled.
3. From the project root, run `flutter pub get` and `flutter run`. For a standalone debug APK, run `flutter build apk --debug`. Find the binary at `build/app/outputs/flutter-apk/app-debug.apk`.

To build the phone test package for 32-bit and 64-bit ARM devices, run `flutter build apk --release --target-platform android-arm,android-arm64`. The APK is at `build/app/outputs/flutter-apk/app-release.apk`. This build uses the generated debug signing key for testing.

The debug package uses the ID com.pocketledger.pocketledger.dev so it can run alongside the standard package. The iOS project is included for future device validation.

## Verify the first build

Run `flutter analyze` and `flutter test`.

On the phone, create Cash with an opening balance of ₹1,000. Record a ₹250 expense and ₹500 income. Create Bank with a ₹2,000 opening balance, then transfer ₹300 from Cash to Bank. Cash should show ₹950 and Bank ₹2,300. Monthly income and expense should still show ₹500 and ₹250.

Edit the expense to ₹350 and delete the transfer. Cash should show ₹1,150 and Bank ₹2,000. Export a backup under Settings, delete an entry, then restore the backup and confirm it returns. Switch to airplane mode and reopen the app to confirm the ledger is still available.

## Accounts and profile

Choose Bank or Online when setting up a ledger or creating an account. Use Online to track a digital balance such as a payment wallet. Accounts are tracked manually. Use **Add Bank, Online or other account** on the entry form to create and select an account without leaving your draft.

Open **Settings → Profile** to enter your full name, phone, email, mailing address, or add a photo. The profile is stored on this device and is excluded from ledger backups. The app opens without a login.

## Export and share a monthly report

Open Reports and select a month. **Excel** and **PDF** save a copy through the system file picker. **Share report** lets you choose a format and opens the system share sheet for WhatsApp and other installed apps.

The Excel workbook includes the monthly summary and transaction details. The PDF includes the monthly cash-flow summary and expense breakdown. Transfers appear in the Excel transaction list and are excluded from income and expense totals.

## Implementation

Money is stored in integer minor units. SQLite foreign keys enforce account and category links. Balances are derived from openings and transactions. Restoring an authenticated backup replaces the ledger in a single SQL transaction. Backups use AES-256-GCM with PBKDF2-HMAC-SHA256 and can be restored up to 20 MB.

The project uses sqflite for SQLite, Flutter ChangeNotifier for shared state, native Flutter navigation, and a custom-painted expense chart. Financial records are local and Android automatic app data backup is disabled. Keep an exported backup and its password separately.
