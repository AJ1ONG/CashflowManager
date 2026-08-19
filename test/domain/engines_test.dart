import 'package:cashflow_manager/domain/engines.dart';
import 'package:cashflow_manager/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecurrenceEngine', () {
    test('once rules generate exactly one event', () {
      final events = const RecurrenceEngine().expand(
        CashFlowRule(
          id: 'one-time',
          name: 'One-time income',
          amount: const Money(100),
          startDate: DateTime.utc(2026, 9, 1),
          frequency: RecurrenceFrequency.once,
        ),
        through: DateTime.utc(2027, 1, 1),
      );

      expect(events, hasLength(1));
      expect(events.single.effectiveDate, DateTime.utc(2026, 9, 1));
    });

    test('monthly rules return to day 31 after shorter months', () {
      final events = const RecurrenceEngine().expand(
        CashFlowRule(
          id: 'salary',
          name: 'Salary',
          amount: const Money(100),
          startDate: DateTime.utc(2026, 1, 31),
          frequency: RecurrenceFrequency.monthly,
        ),
        through: DateTime.utc(2026, 3, 31),
      );

      expect(events.map((event) => event.effectiveDate), [
        DateTime.utc(2026, 1, 31),
        DateTime.utc(2026, 2, 28),
        DateTime.utc(2026, 3, 31),
      ]);
    });

    test('yearly leap-day rules clamp only non-leap years', () {
      final events = const RecurrenceEngine().expand(
        CashFlowRule(
          id: 'bonus',
          name: 'Bonus',
          amount: const Money(100),
          startDate: DateTime.utc(2024, 2, 29),
          frequency: RecurrenceFrequency.yearly,
        ),
        through: DateTime.utc(2028, 2, 29),
      );

      expect(events.last.effectiveDate, DateTime.utc(2028, 2, 29));
      expect(events[1].effectiveDate, DateTime.utc(2025, 2, 28));
    });
  });

  test(
    'cashflow forecast aggregates same-day events before balance output',
    () {
      final date = DateTime.utc(2026, 8, 20);
      final forecast = const CashFlowEngine().forecast(
        currentCash: const Money(5000000),
        events: [
          CashFlowEvent(
            id: 'income',
            name: 'Income',
            effectiveDate: date,
            expectedAmount: const Money(3000000),
          ),
          CashFlowEvent(
            id: 'card',
            name: 'Card',
            effectiveDate: date,
            expectedAmount: const Money(-1800000),
          ),
          CashFlowEvent(
            id: 'payment',
            name: 'Payment',
            effectiveDate: DateTime.utc(2026, 8, 25),
            expectedAmount: const Money(-5000000),
          ),
        ],
        from: date,
        through: DateTime.utc(2026, 8, 25),
      );

      expect(forecast.points.first.balance, const Money(6200000));
      expect(forecast.minimumBalance, const Money(1200000));
      expect(forecast.minimumBalanceDate, DateTime.utc(2026, 8, 25));
    },
  );

  test('liquidity engine returns deployable cash and cumulative deadlines', () {
    final from = DateTime.utc(2026, 8, 19);
    final events = [
      CashFlowEvent(
        id: 'outflow-1',
        name: 'Outflow 1',
        effectiveDate: DateTime.utc(2026, 9, 25),
        expectedAmount: const Money(-800000),
      ),
      CashFlowEvent(
        id: 'outflow-2',
        name: 'Outflow 2',
        effectiveDate: DateTime.utc(2026, 10, 5),
        expectedAmount: const Money(-700000),
      ),
    ];
    const engine = LiquidityEngine();

    expect(
      engine.deployableCapital(
        currentCash: const Money(5000000),
        events: events,
        from: from,
        through: DateTime.utc(2026, 10, 31),
      ),
      const Money(3500000),
    );

    final schedule = engine.requiredReturnSchedule(
      currentCash: const Money(5000000),
      deployment: const Money(5000000),
      events: events,
      from: from,
      through: DateTime.utc(2026, 10, 31),
    );
    expect(schedule.map((item) => item.cumulativeReturn), [
      const Money(800000),
      const Money(1500000),
    ]);
    expect(schedule.map((item) => item.incrementalReturn), [
      const Money(800000),
      const Money(700000),
    ]);
  });

  test('liquidity floor reduces deployable cash', () {
    expect(
      const LiquidityEngine().deployableCapital(
        currentCash: const Money(5000000),
        events: const [],
        from: DateTime.utc(2026, 8, 19),
        through: DateTime.utc(2026, 8, 31),
        minimumCashFloor: const Money(1000000),
      ),
      const Money(4000000),
    );
  });

  test('required cumulative return never decreases after future income', () {
    final schedule = const LiquidityEngine().requiredReturnSchedule(
      currentCash: const Money(5000000),
      deployment: const Money(5000000),
      events: [
        CashFlowEvent(
          id: 'outflow',
          name: 'Outflow',
          effectiveDate: DateTime.utc(2026, 9, 1),
          expectedAmount: const Money(-800000),
        ),
        CashFlowEvent(
          id: 'income',
          name: 'Income',
          effectiveDate: DateTime.utc(2026, 9, 15),
          expectedAmount: const Money(1000000),
        ),
      ],
      from: DateTime.utc(2026, 8, 19),
      through: DateTime.utc(2026, 9, 30),
    );

    expect(schedule, hasLength(1));
    expect(schedule.single.cumulativeReturn, const Money(800000));
  });
}
