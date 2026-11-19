import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

enum Kind { expense, income, transfer }

const backupSizeLimit = 20 * 1024 * 1024;
const currencies = ['INR', 'USD', 'EUR', 'GBP'];
const accountTypes = ['Cash', 'Bank', 'Online', 'Card', 'Wallet', 'Other'];

int? minorUnits(String input) {
  final text = input.trim();
  if (!RegExp(r'^-?\d{1,12}(\.\d{1,2})?$').hasMatch(text)) return null;
  final pieces = text.replaceFirst('-', '').split('.');
  final cents =
      int.parse(pieces.first) * 100 +
      (pieces.length == 2 ? int.parse(pieces.last.padRight(2, '0')) : 0);
  return text.startsWith('-') ? -cents : cents;
}

String decimalAmount(int cents) =>
    '${cents < 0 ? '-' : ''}${cents.abs() ~/ 100}.${(cents.abs() % 100).toString().padLeft(2, '0')}';

String money(int cents, String currency) {
  final symbol = NumberFormat.simpleCurrency(name: currency).currencySymbol;
  final grouping = NumberFormat.decimalPattern(
    currency == 'INR' ? 'en_IN' : 'en_US',
  );
  return '${cents < 0 ? '−' : ''}$symbol${grouping.format(cents.abs() ~/ 100)}.${(cents.abs() % 100).toString().padLeft(2, '0')}';
}

String dayKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
String newId() => const Uuid().v4();

class Account {
  const Account(this.id, this.name, this.type, this.opening, this.archived);
  final String id, name, type;
  final int opening;
  final bool archived;

  factory Account.from(Map<String, Object?> row) => Account(
    row['id'] as String,
    row['name'] as String,
    row['type'] as String,
    row['opening'] as int,
    row['archived'] == 1,
  );
  Map<String, Object?> get row => {
    'id': id,
    'name': name,
    'type': type,
    'opening': opening,
    'archived': archived ? 1 : 0,
  };
}

class Category {
  const Category(this.id, this.name, this.kind, this.archived);
  final String id, name;
  final Kind kind;
  final bool archived;

  factory Category.from(Map<String, Object?> row) => Category(
    row['id'] as String,
    row['name'] as String,
    Kind.values.byName(row['kind'] as String),
    row['archived'] == 1,
  );
  Map<String, Object?> get row => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'archived': archived ? 1 : 0,
  };
}

class LedgerEntry {
  const LedgerEntry(
    this.id,
    this.kind,
    this.amount,
    this.day,
    this.source,
    this.destination,
    this.category,
    this.note,
  );
  final String id, day, source, note;
  final String? destination, category;
  final Kind kind;
  final int amount;

  factory LedgerEntry.from(Map<String, Object?> row) => LedgerEntry(
    row['id'] as String,
    Kind.values.byName(row['kind'] as String),
    row['amount'] as int,
    row['day'] as String,
    row['source'] as String,
    row['destination'] as String?,
    row['category'] as String?,
    row['note'] as String,
  );
  Map<String, Object?> get row => {
    'id': id,
    'kind': kind.name,
    'amount': amount,
    'day': day,
    'source': source,
    'destination': destination,
    'category': category,
    'note': note,
  };
}

class LocalProfile {
  const LocalProfile({
    this.name = '',
    this.phone = '',
    this.email = '',
    this.address = '',
    this.photo,
  });

  final String name, phone, email, address;
  final Uint8List? photo;

  factory LocalProfile.from(Map<String, Object?> row) => LocalProfile(
    name: row['name'] as String,
    phone: row['phone'] as String,
    email: row['email'] as String,
    address: row['address'] as String,
    photo: row['photo'] as Uint8List?,
  );
}

class Ledger extends ChangeNotifier {
  Ledger(this.db);

  final Database db;
  List<Account> accounts = [];
  List<Category> categories = [];
  List<LedgerEntry> entries = [];
  Map<String, String> preferences = {};
  bool busy = false;

  String get currency => preferences['currency'] ?? 'INR';
  String get theme => preferences['theme'] ?? 'system';
  static const _appLockPreference = 'appLock';
  bool get appLockEnabled => preferences[_appLockPreference] == 'enabled';

  Future<void> setAppLock(bool enabled) =>
      setting(_appLockPreference, enabled ? 'enabled' : 'disabled');

  LocalProfile profile = const LocalProfile();

  static Future<void> _createAccounts(Database db, String table) => db.execute(
    '''CREATE TABLE $table (
      id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL CHECK(length(trim(name)) > 0),
      type TEXT NOT NULL CHECK(type IN ('Cash','Bank','Online','Card','Wallet','Other')),
      opening INTEGER NOT NULL, archived INTEGER NOT NULL CHECK(archived IN (0,1)))''',
  );

  static Future<void> _createProfile(Database db) => db.execute(
    '''CREATE TABLE local_profile (
      id INTEGER PRIMARY KEY CHECK(id = 1), name TEXT NOT NULL,
      phone TEXT NOT NULL, email TEXT NOT NULL, address TEXT NOT NULL, photo BLOB)''',
  );

  Future<void> saveProfile(LocalProfile value) async {
    if (value.name.length > 100 ||
        value.phone.length > 40 ||
        value.email.length > 254 ||
        value.address.length > 500 ||
        (value.photo?.length ?? 0) > 512 * 1024) {
      throw StateError('One or more profile fields exceed their size limit.');
    }
    await db.insert('local_profile', {
      'id': 1,
      'name': value.name.trim(),
      'phone': value.phone.trim(),
      'email': value.email.trim(),
      'address': value.address.trim(),
      'photo': value.photo,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    profile = LocalProfile(
      name: value.name.trim(),
      phone: value.phone.trim(),
      email: value.email.trim(),
      address: value.address.trim(),
      photo: value.photo,
    );
    notifyListeners();
  }

  static Future<Ledger> open([String? path]) async {
    final database = await openDatabase(
      path ?? '${await getDatabasesPath()}/pocketledger.db',
      version: 3,
      onConfigure: (db) async {
        // Rebuilding the parent table in the upgrade requires foreign keys
        // off before sqflite starts the migration transaction.
        if (await db.getVersion() != 1) {
          await db.execute('PRAGMA foreign_keys = ON');
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion == 1) {
          await _createAccounts(db, 'accounts_new');
          await db.execute(
            'INSERT INTO accounts_new SELECT * FROM accounts ORDER BY rowid',
          );
          await db.execute('DROP TABLE accounts');
          await db.execute('ALTER TABLE accounts_new RENAME TO accounts');
          await _createProfile(db);
          if ((await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
            throw StateError('The ledger contains invalid account references.');
          }
        } else {
          for (final column in ['phone', 'email', 'address']) {
            await db.execute(
              "ALTER TABLE local_profile ADD COLUMN $column TEXT NOT NULL DEFAULT ''",
            );
          }
          await db.execute('ALTER TABLE local_profile ADD COLUMN photo BLOB');
        }
      },
      onOpen: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await _createAccounts(db, 'accounts');
        await _createProfile(db);
        await db.execute(
          '''CREATE TABLE categories (
          id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL CHECK(length(trim(name)) > 0),
          kind TEXT NOT NULL CHECK(kind IN ('income','expense')),
          archived INTEGER NOT NULL CHECK(archived IN (0,1)), UNIQUE(id,kind))''',
        );
        await db.execute(
          '''CREATE TABLE entries (
          id TEXT PRIMARY KEY NOT NULL, kind TEXT NOT NULL CHECK(kind IN ('expense','income','transfer')),
          amount INTEGER NOT NULL CHECK(amount > 0), day TEXT NOT NULL, note TEXT NOT NULL,
          source TEXT NOT NULL REFERENCES accounts(id), destination TEXT REFERENCES accounts(id),
          category TEXT, FOREIGN KEY(category,kind) REFERENCES categories(id,kind),
          CHECK((kind = 'transfer' AND category IS NULL AND destination IS NOT NULL AND source != destination)
          OR (kind != 'transfer' AND category IS NOT NULL AND destination IS NULL)))''',
        );
        await db.execute(
          'CREATE TABLE preferences (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)',
        );
        for (final field in ['day', 'source', 'destination', 'category']) {
          await db.execute('CREATE INDEX entries_$field ON entries($field)');
        }
      },
    );
    final profileRow = (await database.query('local_profile')).firstOrNull;
    return Ledger(database)
      ..profile = profileRow == null
          ? const LocalProfile()
          : LocalProfile.from(profileRow)
      .._load(await database.transaction(_snapshot));
  }

  static Future<Map<String, Object?>> _snapshot(DatabaseExecutor db) async => {
    'accounts': await db.query('accounts', orderBy: 'rowid'),
    'categories': await db.query('categories', orderBy: 'rowid'),
    'entries': await db.query('entries', orderBy: 'day DESC, rowid DESC'),
    'preferences': await db.query('preferences'),
  };

  void _load(Map<String, Object?> data) {
    accounts = List.unmodifiable(_rows(data, 'accounts').map(Account.from));
    categories = List.unmodifiable(
      _rows(data, 'categories').map(Category.from),
    );
    entries = List.unmodifiable(_rows(data, 'entries').map(LedgerEntry.from));
    preferences = Map.unmodifiable({
      for (final row in _rows(data, 'preferences'))
        row['key'] as String: row['value'] as String,
    });
  }

  static List<Map<String, Object?>> _rows(
    Map<String, Object?> data,
    String table,
  ) => (data[table] as List)
      .map((row) => Map<String, Object?>.from(row as Map))
      .toList();

  Future<void> _change(Future<void> Function(Transaction) operation) async {
    if (busy) throw StateError('A save is already in progress.');
    busy = true;
    try {
      final data = await db.transaction((tx) async {
        await operation(tx);
        return _snapshot(tx);
      });
      _load(data);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> setup(
    String currency,
    String name,
    int opening, {
    String type = 'Cash',
  }) => _change((tx) async {
    if (accounts.isNotEmpty || !currencies.contains(currency)) {
      throw StateError('Invalid setup.');
    }
    await tx.insert('preferences', {'key': 'currency', 'value': currency});
    await tx.insert(
      'accounts',
      Account(newId(), name, type, opening, false).row,
    );
    const seeds = {
      Kind.expense: [
        'Food',
        'Transport',
        'Shopping',
        'Bills',
        'Health',
        'Other',
      ],
      Kind.income: ['Salary', 'Freelance', 'Gifts', 'Other'],
    };
    for (final group in seeds.entries) {
      for (final name in group.value) {
        await tx.insert(
          'categories',
          Category(newId(), name, group.key, false).row,
        );
      }
    }
  });

  Future<void> setting(String key, String value) => _change((tx) async {
    if (key == 'currency' &&
        (entries.isNotEmpty || accounts.any((a) => a.opening != 0))) {
      throw StateError('Currency is fixed once you record money.');
    }
    await tx.insert('preferences', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });

  Future<void> _upsert(
    Transaction tx,
    String table,
    Map<String, Object?> row,
  ) async {
    final id = row['id'];
    final count = await tx.update(table, row, where: 'id = ?', whereArgs: [id]);
    if (count == 0) await tx.insert(table, row);
  }

  Future<void> saveAccount(Account value) =>
      _change((tx) => _upsert(tx, 'accounts', value.row));
  Future<void> saveCategory(Category value) =>
      _change((tx) => _upsert(tx, 'categories', value.row));

  Future<void> saveEntry(LedgerEntry value) => _change((tx) async {
    final previous = entries.where((e) => e.id == value.id).firstOrNull;
    for (final (id, oldId) in [
      (value.source, previous?.source),
      (value.destination, previous?.destination),
    ]) {
      if (id != null &&
          accounts.any((a) => a.id == id && a.archived) &&
          id != oldId) {
        throw StateError('Choose an active account.');
      }
    }
    if (categories.any((c) => c.id == value.category && c.archived) &&
        value.category != previous?.category) {
      throw StateError('Choose an active category.');
    }
    if (value.amount <= 0 ||
        !validDay(value.day) ||
        value.kind == Kind.transfer && value.source == value.destination) {
      throw StateError('Check the amount, date and accounts.');
    }
    await _upsert(tx, 'entries', value.row);
  });

  static bool validDay(String day) {
    final date = DateTime.tryParse(day);
    return date != null && dayKey(date) == day;
  }

  Future<void> deleteEntry(String id) => _change((tx) async {
    await tx.delete('entries', where: 'id = ?', whereArgs: [id]);
  });

  Map<String, int> get balances {
    final values = {
      for (final account in accounts) account.id: account.opening,
    };
    for (final entry in entries) {
      values[entry.source] =
          values[entry.source]! +
          (entry.kind == Kind.income ? entry.amount : -entry.amount);
      final destination = entry.destination;
      if (destination != null) {
        values[destination] = values[destination]! + entry.amount;
      }
    }
    return values;
  }

  List<LedgerEntry> monthly(DateTime month) {
    final prefix = DateFormat('yyyy-MM-').format(month);
    return entries.where((entry) => entry.day.startsWith(prefix)).toList();
  }

  static int total(Iterable<LedgerEntry> entries, Kind kind) => entries
      .where((entry) => entry.kind == kind)
      .fold(0, (sum, entry) => sum + entry.amount);

  Future<Uint8List> export(String password) async {
    final data = await db.transaction(_snapshot);
    data['preferences'] = _rows(
      data,
      'preferences',
    ).where((row) => row['key'] != _appLockPreference).toList();
    final salt = SecretKeyData.random(length: 16).bytes;
    final key = await _key(password, salt);
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(jsonEncode({'version': 1, ...data})),
      secretKey: key,
    );
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'PocketLedger-1',
          'salt': base64Encode(salt),
          'nonce': base64Encode(box.nonce),
          'tag': base64Encode(box.mac.bytes),
          'data': base64Encode(box.cipherText),
        }),
      ),
    );
  }

  Future<void> restore(List<int> bytes, String password) async {
    if (bytes.length > backupSizeLimit) {
      throw const FormatException('Backup too large.');
    }
    final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (envelope['format'] != 'PocketLedger-1') {
      throw const FormatException('Unsupported backup.');
    }
    final salt = base64Decode(envelope['salt'] as String);
    final nonce = base64Decode(envelope['nonce'] as String);
    final tag = base64Decode(envelope['tag'] as String);
    if (salt.length != 16 || nonce.length != 12 || tag.length != 16) {
      throw const FormatException('Invalid backup header.');
    }
    final key = await _key(password, salt);
    final plain = await AesGcm.with256bits().decrypt(
      SecretBox(
        base64Decode(envelope['data'] as String),
        nonce: nonce,
        mac: Mac(tag),
      ),
      secretKey: key,
    );
    final data = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    if (data['version'] != 1) {
      throw const FormatException('Unsupported backup version.');
    }
    final accounts = _rows(data, 'accounts');
    final categories = _rows(data, 'categories');
    final entries = _rows(data, 'entries');
    final preferences = _rows(data, 'preferences');
    if (accounts.isEmpty ||
        accounts.map(Account.from).any((a) => a.id.isEmpty) ||
        categories.map(Category.from).any((c) => c.id.isEmpty) ||
        entries
            .map(LedgerEntry.from)
            .any((e) => e.id.isEmpty || !validDay(e.day)) ||
        !preferences.any(
          (p) => p['key'] == 'currency' && currencies.contains(p['value']),
        ) ||
        preferences.any(
          (p) =>
              p['key'] != 'currency' &&
              !(p['key'] == 'theme' &&
                  ['system', 'light', 'dark'].contains(p['value'])),
        )) {
      throw const FormatException('Invalid backup records.');
    }
    await _change((tx) async {
      for (final table in ['entries', 'categories', 'accounts']) {
        await tx.delete(table);
      }
      await tx.delete(
        'preferences',
        where: 'key != ?',
        whereArgs: [_appLockPreference],
      );
      for (final (table, rows) in [
        ('accounts', accounts),
        ('categories', categories),
        ('entries', entries.reversed),
        ('preferences', preferences),
      ]) {
        for (final row in rows) {
          await tx.insert(table, row);
        }
      }
    });
  }

  static Future<SecretKey> _key(String password, List<int> salt) async =>
      SecretKey(await compute(_deriveBackupKey, (password, salt)));
}

Future<List<int>> _deriveBackupKey((String, List<int>) input) async {
  final (password, salt) = input;
  final key = await Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 600000,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  return key.extractBytes();
}
