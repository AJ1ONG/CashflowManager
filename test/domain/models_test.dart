import 'package:cashflow_manager/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('money uses minor units and events preserve lifecycle amounts', () {
    expect(const Money(12345).format(), '¥123.45');
    expect(const Money(-805).format(), '-¥8.05');

    final estimated = CashFlowEvent(
      id: 'salary',
      name: 'Salary',
      effectiveDate: DateTime.utc(2026, 9, 15),
      expectedAmount: const Money(2500000),
    );
    final confirmed = estimated.confirm(const Money(2480000));
    final settled = confirmed.settle(const Money(2453200));

    expect(estimated.status, CashFlowStatus.estimated);
    expect(confirmed.status, CashFlowStatus.confirmed);
    expect(settled.status, CashFlowStatus.settled);
    expect(settled.effectiveAmount, const Money(2453200));
    expect(settled.expectedAmount, const Money(2500000));
    expect(settled.confirmedAmount, const Money(2480000));
  });

  test('money parses decimal input without floating point', () {
    expect(Money.tryParse('12,345.67'), const Money(1234567));
    expect(Money.tryParse('-¥8.5'), const Money(-850));
    expect(Money.tryParse('1.234'), isNull);
    expect(Money.tryParse('not money'), isNull);
  });

  test('credit card statement maps to a future repayment event', () {
    final card = CreditCard(
      id: 'card',
      name: 'Card',
      statementDay: 18,
      paymentDay: 5,
      defaultExpectedBill: const Money(800000),
    );

    final event = card.expectedPaymentForStatement(DateTime.utc(2026, 8, 18));
    expect(event.effectiveDate, DateTime.utc(2026, 9, 5));
    expect(event.effectiveAmount, const Money(-800000));
    expect(event.status, CashFlowStatus.estimated);
  });

  test('income distinguishes net input from gross calculation output', () {
    final netIncome = IncomeSource(
      id: 'net-salary',
      name: 'Net salary',
      expectedAmount: const Money(2500000),
      startDate: DateTime.utc(2026, 9, 15),
      frequency: RecurrenceFrequency.monthly,
    );
    final grossIncome = IncomeSource(
      id: 'gross-salary',
      name: 'Gross salary',
      expectedAmount: const Money(3000000),
      startDate: DateTime.utc(2026, 9, 15),
      frequency: RecurrenceFrequency.monthly,
      mode: IncomeMode.gross,
      taxProfileId: 'cn-2026',
      socialInsuranceProfileId: 'shanghai',
    );

    expect(netIncome.toRule().amount, const Money(2500000));
    expect(() => grossIncome.toRule(), throwsStateError);
    expect(
      grossIncome.toRule(calculatedNetAmount: const Money(2450000)).amount,
      const Money(2450000),
    );
  });

  test(
    'investment partial return preserves actual and reschedules remainder',
    () {
      final investment = Investment(
        id: 'investment',
        name: 'Deposit',
        principal: const Money(3000000),
        investmentDate: DateTime.utc(2026, 8, 17),
        expectedReturn: const Money(3060000),
        expectedReturnDate: DateTime.utc(2026, 10, 15),
      );

      final events = investment.recordReturn(
        received: const Money(2000000),
        remainingDate: DateTime.utc(2026, 10, 30),
      );

      expect(events.first.status, CashFlowStatus.settled);
      expect(events.first.actualAmount, const Money(2000000));
      expect(events.first.expectedAmount, const Money(3060000));
      expect(events.last.status, CashFlowStatus.estimated);
      expect(events.last.expectedAmount, const Money(1060000));
    },
  );
}
