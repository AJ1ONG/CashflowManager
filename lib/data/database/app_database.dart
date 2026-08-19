import 'package:sqlite3/sqlite3.dart';

class AppDatabase {
  AppDatabase._(this.connection) {
    _migrate();
  }

  factory AppDatabase.open(String path) => AppDatabase._(sqlite3.open(path));

  factory AppDatabase.inMemory() => AppDatabase._(sqlite3.openInMemory());

  static const schemaVersion = 2;

  // ponytail: synchronous access is enough for Phase 3; move database work to
  // an isolate if real-world profiling shows UI jank.
  final Database connection;
  var _transactionDepth = 0;

  int get userVersion =>
      connection.select('PRAGMA user_version').single['user_version'] as int;

  void close() => connection.close();

  T transaction<T>(T Function() action) {
    if (_transactionDepth > 0) return action();

    connection.execute('BEGIN IMMEDIATE');
    _transactionDepth++;
    try {
      final result = action();
      connection.execute('COMMIT');
      return result;
    } catch (_) {
      connection.execute('ROLLBACK');
      rethrow;
    } finally {
      _transactionDepth--;
    }
  }

  void _migrate() {
    connection.execute('PRAGMA foreign_keys = ON');
    var version = userVersion;
    if (version > schemaVersion) {
      throw StateError(
        'Database version $version is newer than supported version '
        '$schemaVersion',
      );
    }
    while (version < schemaVersion) {
      final targetVersion = version + 1;
      transaction(() {
        for (final statement in _migrations[targetVersion - 1]) {
          connection.execute(statement);
        }
        connection.execute('PRAGMA user_version = $targetVersion');
      });
      version = targetVersion;
    }
  }
}

const _migrations = [_version1Schema, _version2Schema];

const _version1Schema = [
  '''
    CREATE TABLE accounts (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      balance_minor INTEGER NOT NULL
    ) STRICT
  ''',
  '''
    CREATE TABLE cash_flow_rules (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      amount_minor INTEGER NOT NULL,
      start_date TEXT NOT NULL,
      end_date TEXT,
      frequency TEXT NOT NULL
        CHECK (frequency IN ('once', 'monthly', 'yearly'))
    ) STRICT
  ''',
  '''
    CREATE TABLE cash_flow_events (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      effective_date TEXT NOT NULL,
      expected_amount_minor INTEGER NOT NULL,
      confirmed_amount_minor INTEGER,
      actual_amount_minor INTEGER
    ) STRICT
  ''',
  '''
    CREATE INDEX cash_flow_events_effective_date
    ON cash_flow_events (effective_date)
  ''',
  '''
    CREATE TABLE credit_cards (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      statement_day INTEGER NOT NULL CHECK (statement_day BETWEEN 1 AND 31),
      payment_day INTEGER NOT NULL CHECK (payment_day BETWEEN 1 AND 31),
      default_expected_bill_minor INTEGER NOT NULL
        CHECK (default_expected_bill_minor >= 0)
    ) STRICT
  ''',
  '''
    CREATE TABLE income_sources (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      expected_amount_minor INTEGER NOT NULL,
      start_date TEXT NOT NULL,
      frequency TEXT NOT NULL
        CHECK (frequency IN ('once', 'monthly', 'yearly')),
      mode TEXT NOT NULL CHECK (mode IN ('net', 'gross')),
      tax_profile_id TEXT,
      social_insurance_profile_id TEXT
    ) STRICT
  ''',
  '''
    CREATE TABLE investments (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      principal_minor INTEGER NOT NULL CHECK (principal_minor > 0),
      investment_date TEXT NOT NULL,
      expected_return_minor INTEGER NOT NULL CHECK (expected_return_minor >= 0),
      expected_return_date TEXT NOT NULL
    ) STRICT
  ''',
  '''
    CREATE TABLE tax_profiles (
      id TEXT PRIMARY KEY NOT NULL,
      jurisdiction TEXT NOT NULL,
      tax_year INTEGER NOT NULL,
      rule_version TEXT NOT NULL
    ) STRICT
  ''',
  '''
    CREATE TABLE reminders (
      id TEXT PRIMARY KEY NOT NULL,
      title TEXT NOT NULL,
      due_date TEXT NOT NULL,
      related_id TEXT NOT NULL
    ) STRICT
  ''',
];

const _version2Schema = [
  '''
    CREATE TABLE cash_flow_event_revisions (
      revision_id INTEGER PRIMARY KEY AUTOINCREMENT,
      event_id TEXT NOT NULL,
      changed_at TEXT NOT NULL,
      action TEXT NOT NULL CHECK (action <> ''),
      name TEXT NOT NULL,
      effective_date TEXT NOT NULL,
      expected_amount_minor INTEGER NOT NULL,
      confirmed_amount_minor INTEGER,
      actual_amount_minor INTEGER
    ) STRICT
  ''',
  '''
    CREATE INDEX cash_flow_event_revisions_event_id
    ON cash_flow_event_revisions (event_id, revision_id)
  ''',
];
