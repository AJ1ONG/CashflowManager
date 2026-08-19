import 'package:cashflow_manager/application/cashflow_service.dart';
import 'package:cashflow_manager/data/database/app_database.dart';
import 'package:cashflow_manager/data/repositories/cashflow_repository.dart';
import 'package:cashflow_manager/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late CashflowRepository repository;
  late CashflowService service;

  setUp(() {
    database = AppDatabase.inMemory();
    repository = CashflowRepository(database);
    service = CashflowService(repository);
  });
  tearDown(() => database.close());

  test(
    'rules materialize idempotently without regressing confirmed events',
    () {
      final rule = CashFlowRule(
        id: 'salary',
        name: 'Salary',
        amount: const Money(2500000),
        startDate: DateTime.utc(2026, 9, 15),
        frequency: RecurrenceFrequency.monthly,
      );
      service.materializeRule(rule, through: DateTime.utc(2026, 10, 31));
      service.confirmEvent('salary-20260915', const Money(2480000));
      service.materializeRule(rule, through: DateTime.utc(2026, 10, 31));

      expect(repository.events, hasLength(2));
      expect(
        repository.eventById('salary-20260915')!.status,
        CashFlowStatus.confirmed,
      );
      expect(repository.revisionsForEvent('salary-20260915'), hasLength(2));
    },
  );

  test(
    'credit card moves from estimate to confirmed to settled with reminder',
    () {
      final event = service.scheduleCreditCardStatement(
        CreditCard(
          id: 'card',
          name: 'Main card',
          statementDay: 18,
          paymentDay: 5,
          defaultExpectedBill: const Money(800000),
        ),
        DateTime.utc(2026, 8, 18),
      );

      expect(event.effectiveDate, DateTime.utc(2026, 9, 5));
      expect(repository.reminders.single.dueDate, DateTime.utc(2026, 8, 18));
      service.confirmCreditCardBill(event.id, const Money(873262));
      service.scheduleCreditCardStatement(
        repository.creditCards.single,
        DateTime.utc(2026, 8, 18),
      );
      expect(repository.eventById(event.id)!.status, CashFlowStatus.confirmed);
      service.settleCreditCardPayment(event.id, const Money(872900));

      final saved = repository.eventById(event.id)!;
      expect(saved.expectedAmount, const Money(-800000));
      expect(saved.confirmedAmount, const Money(-873262));
      expect(saved.actualAmount, const Money(-872900));
      expect(
        repository.revisionsForEvent(event.id).map((item) => item.action),
        [
          'credit_card_estimated',
          'credit_card_confirmed',
          'credit_card_settled',
        ],
      );
    },
  );

  test(
    'investment return is not automatic and partial receipt schedules rest',
    () {
      final investment = Investment(
        id: 'deposit',
        name: 'Deposit',
        principal: const Money(3000000),
        investmentDate: DateTime.utc(2026, 8, 17),
        expectedReturn: const Money(3060000),
        expectedReturnDate: DateTime.utc(2026, 10, 15),
      );
      service.createInvestment(investment);

      expect(
        repository.eventById('deposit-return')!.status,
        CashFlowStatus.estimated,
      );
      expect(repository.reminders.single.dueDate, DateTime.utc(2026, 10, 15));

      final events = service.recordInvestmentReturn(
        investmentId: 'deposit',
        received: const Money(2000000),
        remainingDate: DateTime.utc(2026, 10, 30),
      );
      expect(events.first.actualAmount, const Money(2000000));
      expect(events.last.expectedAmount, const Money(1060000));
      expect(repository.reminders.single.dueDate, DateTime.utc(2026, 10, 30));
      expect(repository.reminders.single.relatedId, events.last.id);
    },
  );

  test(
    'delayed investment return updates source, event, reminder, and history',
    () {
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

      service.updateInvestmentReturn(
        investmentId: 'deposit',
        expectedAmount: const Money(3070000),
        expectedDate: DateTime.utc(2026, 10, 30),
      );

      expect(
        repository.investmentById('deposit')!.expectedReturn,
        const Money(3070000),
      );
      expect(
        repository.eventById('deposit-return')!.effectiveDate,
        DateTime.utc(2026, 10, 30),
      );
      expect(repository.reminders.single.dueDate, DateTime.utc(2026, 10, 30));
      expect(repository.revisionsForEvent('deposit-return'), hasLength(2));
    },
  );

  test(
    'balance adjustment updates current cash without double-counting it',
    () {
      repository.saveAccount(
        id: 'cash',
        name: 'Cash',
        balance: const Money(5000000),
      );
      final adjustment = service.recordBalanceAdjustment(
        adjustmentId: 'adjustment-1',
        accountId: 'cash',
        actualBalance: const Money(4800000),
        at: DateTime.utc(2026, 8, 19),
      );

      expect(adjustment!.actualAmount, const Money(-200000));
      final analysis = service.analyze(
        from: DateTime.utc(2026, 8, 19),
        through: DateTime.utc(2026, 8, 20),
      );
      expect(analysis.currentCash, const Money(4800000));
      expect(analysis.forecast.points.first.balance, const Money(4800000));
    },
  );

  test(
    'analysis combines repository data into forecast and liquidity output',
    () {
      repository.saveAccount(
        id: 'cash',
        name: 'Cash',
        balance: const Money(5000000),
      );
      repository.saveEvent(
        CashFlowEvent(
          id: 'outflow-1',
          name: 'Outflow 1',
          effectiveDate: DateTime.utc(2026, 9, 25),
          expectedAmount: const Money(-800000),
        ),
      );
      repository.saveEvent(
        CashFlowEvent(
          id: 'outflow-2',
          name: 'Outflow 2',
          effectiveDate: DateTime.utc(2026, 10, 5),
          expectedAmount: const Money(-700000),
        ),
      );

      final analysis = service.analyze(
        from: DateTime.utc(2026, 8, 19),
        through: DateTime.utc(2026, 10, 31),
        deployment: const Money(5000000),
      );
      expect(analysis.forecast.minimumBalance, const Money(3500000));
      expect(analysis.deployableCapital, const Money(3500000));
      expect(
        analysis.requiredReturnSchedule.map((item) => item.cumulativeReturn),
        [const Money(800000), const Money(1500000)],
      );
    },
  );
}
