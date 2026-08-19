import 'dart:io';

import 'package:cashflow_manager/application/cashflow_service.dart';
import 'package:cashflow_manager/data/database/app_database.dart';
import 'package:cashflow_manager/data/repositories/cashflow_repository.dart';
import 'package:cashflow_manager/domain/models.dart';

void main(List<String> arguments) {
  if (arguments.contains('--help')) {
    stdout.writeln('Usage: dart run bin/non_ui_demo.dart [database-path]');
    return;
  }
  if (arguments.length > 1) {
    stderr.writeln('Expected at most one database path.');
    exitCode = 64;
    return;
  }

  Directory? temporaryDirectory;
  final path = arguments.isEmpty
      ? '${(temporaryDirectory = Directory.systemTemp.createTempSync('cashflow-demo-')).path}/demo.sqlite'
      : arguments.single;
  try {
    final analysis = _populateAndAnalyze(path);
    _populateAndAnalyze(path);
    final reopened = AppDatabase.open(path);
    final repository = CashflowRepository(reopened);
    try {
      if (reopened.userVersion != AppDatabase.schemaVersion ||
          repository.totalCash != const Money(5000000) ||
          repository.events.length != 5 ||
          repository.revisionsForEvent('main-card-20260905').length != 2) {
        throw StateError('Persistence self-check failed');
      }

      stdout
        ..writeln('Non-UI cashflow demo passed.')
        ..writeln('Current cash: ${analysis.currentCash}')
        ..writeln('Stored events: ${repository.events.length}')
        ..writeln('Minimum future balance: ${analysis.forecast.minimumBalance}')
        ..writeln('Deployable capital: ${analysis.deployableCapital}')
        ..writeln(
          'Required return checkpoints: '
          '${analysis.requiredReturnSchedule.length}',
        )
        ..writeln('SQLite close/reopen check: OK')
        ..writeln('Repeated workflow idempotency check: OK')
        ..writeln(
          temporaryDirectory == null
              ? 'Database kept at: $path'
              : 'Temporary database cleaned after the run.',
        );
    } finally {
      reopened.close();
    }
  } catch (error, stackTrace) {
    stderr
      ..writeln('Non-UI cashflow demo failed: $error')
      ..writeln(stackTrace);
    exitCode = 1;
  } finally {
    temporaryDirectory?.deleteSync(recursive: true);
  }
}

CashflowAnalysis _populateAndAnalyze(String path) {
  final database = AppDatabase.open(path);
  try {
    final repository = CashflowRepository(database);
    final service = CashflowService(repository);
    repository.saveAccount(
      id: 'cash',
      name: 'Current cash',
      balance: const Money(5000000),
    );
    service.scheduleIncome(
      IncomeSource(
        id: 'salary',
        name: 'Salary',
        expectedAmount: const Money(2500000),
        startDate: DateTime.utc(2026, 9, 15),
        frequency: RecurrenceFrequency.monthly,
      ),
      through: DateTime.utc(2026, 10, 31),
    );
    final cardEvent = service.scheduleCreditCardStatement(
      CreditCard(
        id: 'main-card',
        name: 'Main card',
        statementDay: 18,
        paymentDay: 5,
        defaultExpectedBill: const Money(800000),
      ),
      DateTime.utc(2026, 8, 18),
    );
    service.confirmCreditCardBill(cardEvent.id, const Money(873262));
    service.createInvestment(
      Investment(
        id: 'deposit',
        name: 'Deposit',
        principal: const Money(3000000),
        investmentDate: DateTime.utc(2026, 8, 17),
        expectedReturn: const Money(3060000),
        expectedReturnDate: DateTime.utc(2026, 10, 15),
      ),
    );
    return service.analyze(
      from: DateTime.utc(2026, 8, 19),
      through: DateTime.utc(2026, 10, 31),
      deployment: const Money(5000000),
    );
  } finally {
    database.close();
  }
}
