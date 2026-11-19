import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketledger/ledger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'upgrades a ledger with account references and saves an offline profile',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'pocketledger-upgrade-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final path = '${folder.path}/ledger.sqlite';
      final v1 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE accounts (id TEXT PRIMARY KEY, name TEXT, type TEXT CHECK(type IN (\'Cash\',\'Bank\')), opening INTEGER, archived INTEGER)',
            );
            await db.execute(
              'CREATE TABLE categories (id TEXT PRIMARY KEY, name TEXT, kind TEXT, archived INTEGER)',
            );
            await db.execute(
              'CREATE TABLE entries (id TEXT PRIMARY KEY, kind TEXT, amount INTEGER, day TEXT, source TEXT REFERENCES accounts(id), destination TEXT REFERENCES accounts(id), category TEXT, note TEXT)',
            );
            await db.execute(
              'CREATE TABLE preferences (key TEXT PRIMARY KEY, value TEXT)',
            );
            await db.execute(
              "INSERT INTO accounts VALUES ('cash','Cash','Cash',1000,0), ('bank','Bank','Bank',100,0)",
            );
            await db.execute(
              "INSERT INTO entries VALUES ('move','transfer',250,'2026-11-19','cash','bank',NULL,'')",
            );
          },
        ),
      );
      await v1.close();

      final ledger = await Ledger.open(path);
      try {
        expect(ledger.balances, {'cash': 750, 'bank': 350});
        expect(await ledger.db.rawQuery('PRAGMA foreign_keys'), [
          {'foreign_keys': 1},
        ]);
        await expectLater(
          ledger.db.delete('accounts', where: "id = 'bank'"),
          throwsA(isA<DatabaseException>()),
        );
        await ledger.saveAccount(
          const Account('online', 'Online wallet', 'Online', 200, false),
        );
        await ledger.saveProfileName('  Jit  ');
      } finally {
        await ledger.db.close();
      }

      final reopened = await Ledger.open(path);
      addTearDown(reopened.db.close);
      expect(reopened.profileName, 'Jit');
      expect(reopened.accounts.map((account) => account.type), [
        'Cash',
        'Bank',
        'Online',
      ]);
      expect(reopened.balances, {'cash': 750, 'bank': 350, 'online': 200});
    },
  );
}
