import 'dart:io';

import 'package:cashflow_manager/data/database/app_database.dart';
import 'package:cashflow_manager/data/repositories/cashflow_repository.dart';
import 'package:cashflow_manager/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('migration creates only source-data tables at current version', () {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);

    final tables = database.connection
        .select(
          "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
        )
        .map((row) => row['name'] as String)
        .toSet();

    expect(database.userVersion, AppDatabase.schemaVersion);
    expect(
      tables,
      containsAll(<String>{
        'accounts',
        'cash_flow_rules',
        'cash_flow_events',
        'cash_flow_event_revisions',
        'credit_cards',
        'income_sources',
        'investments',
        'tax_profiles',
        'reminders',
      }),
    );
    expect(tables, isNot(contains('forecasts')));
    expect(tables, isNot(contains('liquidity_analysis')));
  });

  test('version 1 database upgrades without losing account data', () {
    final directory = Directory.systemTemp.createTempSync('cashflow-v1-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/cashflow.sqlite';
    final oldDatabase = sqlite3.open(path)
      ..execute('''
        CREATE TABLE accounts (
          id TEXT PRIMARY KEY NOT NULL,
          name TEXT NOT NULL,
          balance_minor INTEGER NOT NULL
        ) STRICT
      ''')
      ..execute('INSERT INTO accounts VALUES (?, ?, ?)', [
        'cash',
        'Cash',
        123400,
      ])
      ..execute('PRAGMA user_version = 1');
    oldDatabase.close();

    final upgraded = AppDatabase.open(path);
    addTearDown(upgraded.close);

    expect(upgraded.userVersion, 2);
    expect(CashflowRepository(upgraded).totalCash, const Money(123400));
    expect(
      upgraded.connection.select(
        "SELECT name FROM sqlite_master WHERE name = 'cash_flow_event_revisions'",
      ),
      isNotEmpty,
    );
  });

  test('event changes append snapshots and identical saves do not', () {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = CashflowRepository(database);
    final estimated = CashFlowEvent(
      id: 'bill',
      name: 'Card bill',
      effectiveDate: DateTime.utc(2026, 9, 5),
      expectedAmount: const Money(-800000),
    );

    expect(repository.saveEvent(estimated, action: 'estimated'), isTrue);
    expect(repository.saveEvent(estimated, action: 'duplicate'), isFalse);
    expect(
      repository.saveEvent(
        estimated.confirm(const Money(-812300)),
        action: 'confirmed',
      ),
      isTrue,
    );
    repository.saveEvent(
      estimated.confirm(const Money(-812300)).settle(const Money(-810000)),
      action: 'settled',
    );

    final revisions = repository.revisionsForEvent('bill');
    expect(revisions.map((item) => item.action), [
      'estimated',
      'confirmed',
      'settled',
    ]);
    expect(revisions[0].event.status, CashFlowStatus.estimated);
    expect(revisions[1].event.status, CashFlowStatus.confirmed);
    expect(revisions[2].event.actualAmount, const Money(-810000));
  });

  test('event and its revision roll back together', () {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = CashflowRepository(database);

    expect(
      () => database.transaction(() {
        repository.saveEvent(
          CashFlowEvent(
            id: 'rolled-back',
            name: 'Rolled back',
            effectiveDate: DateTime.utc(2026, 9, 1),
            expectedAmount: const Money(100),
          ),
        );
        throw StateError('abort');
      }),
      throwsStateError,
    );
    expect(repository.eventById('rolled-back'), isNull);
    expect(repository.revisionsForEvent('rolled-back'), isEmpty);
  });

  test('repository round-trips phase 1 models without losing amounts', () {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = CashflowRepository(database);

    repository
      ..saveAccount(id: 'cash', name: 'Cash', balance: const Money(5000000))
      ..saveAccount(
        id: 'savings',
        name: 'Savings',
        balance: const Money(2500000),
      )
      ..saveEvent(
        CashFlowEvent(
          id: 'salary',
          name: 'Salary',
          effectiveDate: DateTime.utc(2026, 9, 15),
          expectedAmount: const Money(2500000),
          confirmedAmount: const Money(2480000),
          actualAmount: const Money(2453200),
        ),
      )
      ..saveRule(
        CashFlowRule(
          id: 'monthly-salary',
          name: 'Monthly salary',
          amount: const Money(2500000),
          startDate: DateTime.utc(2026, 9, 15),
          endDate: DateTime.utc(2027, 8, 15),
          frequency: RecurrenceFrequency.monthly,
        ),
      )
      ..saveCreditCard(
        CreditCard(
          id: 'card',
          name: 'Card',
          statementDay: 18,
          paymentDay: 5,
          defaultExpectedBill: const Money(800000),
        ),
      )
      ..saveIncome(
        IncomeSource(
          id: 'gross-salary',
          name: 'Gross salary',
          expectedAmount: const Money(3000000),
          startDate: DateTime.utc(2026, 9, 15),
          frequency: RecurrenceFrequency.monthly,
          mode: IncomeMode.gross,
          taxProfileId: 'cn-2026',
          socialInsuranceProfileId: 'shanghai',
        ),
      )
      ..saveInvestment(
        Investment(
          id: 'deposit',
          name: 'Deposit',
          principal: const Money(3000000),
          investmentDate: DateTime.utc(2026, 8, 17),
          expectedReturn: const Money(3060000),
          expectedReturnDate: DateTime.utc(2026, 10, 15),
        ),
      )
      ..saveReminder(
        Reminder(
          id: 'statement-reminder',
          title: 'Confirm statement',
          dueDate: DateTime.utc(2026, 8, 18),
          relatedId: 'card',
        ),
      )
      ..saveTaxProfile(
        id: 'cn-2026',
        jurisdiction: 'CN',
        taxYear: 2026,
        ruleVersion: '2026.1',
      );

    expect(repository.totalCash, const Money(7500000));
    expect(repository.events.single.expectedAmount, const Money(2500000));
    expect(repository.events.single.confirmedAmount, const Money(2480000));
    expect(repository.events.single.actualAmount, const Money(2453200));
    expect(repository.rules.single.frequency, RecurrenceFrequency.monthly);
    expect(repository.creditCards.single.paymentDay, 5);
    expect(repository.incomeSources.single.mode, IncomeMode.gross);
    expect(repository.incomeSources.single.taxProfileId, 'cn-2026');
    expect(repository.investments.single.expectedReturn, const Money(3060000));
    expect(repository.reminders.single.relatedId, 'card');
    expect(
      database.connection.select(
        'SELECT rule_version FROM tax_profiles WHERE id = ?',
        ['cn-2026'],
      ).single['rule_version'],
      '2026.1',
    );
  });

  test('file database survives close and reopen', () {
    final directory = Directory.systemTemp.createTempSync('cashflow-manager-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/cashflow.sqlite';

    final firstDatabase = AppDatabase.open(path);
    CashflowRepository(firstDatabase)
        .saveAccount(id: 'cash', name: 'Cash', balance: const Money(5000000));
    firstDatabase.close();

    final reopenedDatabase = AppDatabase.open(path);
    addTearDown(reopenedDatabase.close);
    expect(
      CashflowRepository(reopenedDatabase).totalCash,
      const Money(5000000),
    );
  });
}
