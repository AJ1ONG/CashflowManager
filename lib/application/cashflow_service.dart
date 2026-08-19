import '../data/repositories/cashflow_repository.dart';
import '../domain/engines.dart';
import '../domain/models.dart';

class CashflowAnalysis {
  const CashflowAnalysis({
    required this.currentCash,
    required this.forecast,
    required this.deployableCapital,
    required this.requiredReturnSchedule,
  });

  final Money currentCash;
  final CashFlowForecast forecast;
  final Money deployableCapital;
  final List<LiquidityRequirement> requiredReturnSchedule;
}

class CashflowService {
  const CashflowService(this.repository);

  final CashflowRepository repository;

  Money get currentCash => repository.totalCash;

  List<CashFlowEvent> get events => repository.events;

  List<Investment> get investments => repository.investments;

  List<Reminder> get reminders => repository.reminders;

  List<CreditCard> get creditCards => repository.creditCards;

  List<IncomeSource> get incomeSources => repository.incomeSources;

  List<CashFlowEventRevision> revisionsForEvent(String eventId) =>
      repository.revisionsForEvent(eventId);

  void createEvent(CashFlowEvent event) {
    repository.saveEvent(event, action: 'manual_created');
  }

  CashFlowEvent? setCurrentCash({
    required Money balance,
    required DateTime at,
    required String adjustmentId,
  }) {
    if (repository.accountBalance('cash') == null) {
      repository.saveAccount(id: 'cash', name: 'Cash', balance: balance);
      return null;
    }
    return recordBalanceAdjustment(
      adjustmentId: adjustmentId,
      accountId: 'cash',
      actualBalance: balance,
      at: at,
    );
  }

  List<CashFlowEvent> materializeRule(
    CashFlowRule rule, {
    required DateTime through,
  }) => repository.database.transaction(() {
    repository.saveRule(rule);
    final generated = const RecurrenceEngine().expand(rule, through: through);
    for (final event in generated) {
      if (repository.eventById(event.id) == null) {
        repository.saveEvent(event, action: 'rule_generated');
      }
    }
    return generated;
  });

  List<CashFlowEvent> scheduleIncome(
    IncomeSource income, {
    required DateTime through,
    Money? calculatedNetAmount,
  }) => repository.database.transaction(() {
    repository.saveIncome(income);
    return materializeRule(
      income.toRule(calculatedNetAmount: calculatedNetAmount),
      through: through,
    );
  });

  CashFlowEvent scheduleCreditCardStatement(
    CreditCard card,
    DateTime statementDate,
  ) => repository.database.transaction(() {
    repository.saveCreditCard(card);
    final estimate = card.expectedPaymentForStatement(statementDate);
    final existing = repository.eventById(estimate.id);
    final event = existing ?? estimate;
    if (existing == null) {
      repository.saveEvent(estimate, action: 'credit_card_estimated');
    }
    repository.saveReminder(
      Reminder(
        id: '${event.id}-statement-reminder',
        title: 'Confirm ${card.name} statement',
        dueDate: statementDate,
        relatedId: event.id,
      ),
    );
    return event;
  });

  CashFlowEvent confirmCreditCardBill(String eventId, Money billAmount) =>
      _updateEvent(
        eventId,
        action: 'credit_card_confirmed',
        update: (event) =>
            event.confirm(-_nonNegative(billAmount, 'billAmount')),
      );

  CashFlowEvent settleCreditCardPayment(String eventId, Money deductedAmount) =>
      _updateEvent(
        eventId,
        action: 'credit_card_settled',
        update: (event) =>
            event.settle(-_nonNegative(deductedAmount, 'deductedAmount')),
      );

  CashFlowEvent confirmEvent(String eventId, Money amount) => _updateEvent(
    eventId,
    action: 'confirmed',
    update: (event) => event.confirm(amount),
  );

  CashFlowEvent settleEvent(String eventId, Money amount) => _updateEvent(
    eventId,
    action: 'settled',
    update: (event) => event.settle(amount),
  );

  List<CashFlowEvent> createInvestment(Investment investment) =>
      repository.database.transaction(() {
        final existing = repository.investmentById(investment.id);
        final saved = existing ?? investment;
        if (existing == null) {
          repository.saveInvestment(investment);
        }
        final events = saved.initialEvents;
        for (final event in events) {
          if (repository.eventById(event.id) == null) {
            repository.saveEvent(event, action: 'investment_created');
          }
        }
        _saveInvestmentReminder(saved, events.last.id);
        return events
            .map((event) => repository.eventById(event.id)!)
            .toList(growable: false);
      });

  CashFlowEvent updateInvestmentReturn({
    required String investmentId,
    required Money expectedAmount,
    required DateTime expectedDate,
  }) => repository.database.transaction(() {
    _nonNegative(expectedAmount, 'expectedAmount');
    final current = _investment(investmentId);
    final returnEvent = _event('$investmentId-return');
    if (returnEvent.status == CashFlowStatus.settled) {
      throw StateError('Settled investment returns cannot be changed');
    }
    final updated = Investment(
      id: current.id,
      name: current.name,
      principal: current.principal,
      investmentDate: current.investmentDate,
      expectedReturn: expectedAmount,
      expectedReturnDate: expectedDate,
    );
    repository.saveInvestment(updated);
    final event = CashFlowEvent(
      id: returnEvent.id,
      name: returnEvent.name,
      effectiveDate: expectedDate,
      expectedAmount: expectedAmount,
    );
    repository.saveEvent(event, action: 'investment_return_updated');
    _saveInvestmentReminder(updated, event.id);
    return event;
  });

  List<CashFlowEvent> recordInvestmentReturn({
    required String investmentId,
    required Money received,
    DateTime? remainingDate,
  }) => repository.database.transaction(() {
    final investment = _investment(investmentId);
    final currentReturn = _event('$investmentId-return');
    if (currentReturn.status == CashFlowStatus.settled) {
      throw StateError('Investment return is already settled');
    }
    final events = investment.recordReturn(
      received: received,
      remainingDate: remainingDate,
    );
    repository.deleteReminder('$investmentId-return-reminder');
    for (final event in events) {
      repository.saveEvent(event, action: 'investment_return_recorded');
    }
    if (events.length > 1) {
      repository.saveReminder(
        Reminder(
          id: '$investmentId-return-reminder',
          title: 'Check ${investment.name} remaining return',
          dueDate: events.last.effectiveDate,
          relatedId: events.last.id,
        ),
      );
    }
    return events;
  });

  CashFlowEvent? recordBalanceAdjustment({
    required String adjustmentId,
    required String accountId,
    required Money actualBalance,
    required DateTime at,
  }) => repository.database.transaction(() {
    final current = repository.accountBalance(accountId);
    if (current == null) throw StateError('Account not found: $accountId');
    final difference = actualBalance - current;
    if (difference == Money.zero) return null;

    repository.updateAccountBalance(accountId, actualBalance);
    final event = CashFlowEvent(
      id: adjustmentId,
      name: 'Balance adjustment',
      effectiveDate: at,
      expectedAmount: difference,
      actualAmount: difference,
    );
    repository.saveEvent(event, action: 'balance_adjusted');
    return event;
  });

  CashflowAnalysis analyze({
    required DateTime from,
    required DateTime through,
    Money minimumCashFloor = Money.zero,
    Money deployment = Money.zero,
  }) {
    final currentCash = repository.totalCash;
    final futureEvents = repository.events.where(
      (event) => event.status != CashFlowStatus.settled,
    );
    final forecast = const CashFlowEngine().forecast(
      currentCash: currentCash,
      events: futureEvents,
      from: from,
      through: through,
    );
    return CashflowAnalysis(
      currentCash: currentCash,
      forecast: forecast,
      deployableCapital: const LiquidityEngine().deployableCapital(
        currentCash: currentCash,
        events: futureEvents,
        from: from,
        through: through,
        minimumCashFloor: minimumCashFloor,
      ),
      requiredReturnSchedule: const LiquidityEngine().requiredReturnSchedule(
        currentCash: currentCash,
        deployment: deployment,
        events: futureEvents,
        from: from,
        through: through,
        minimumCashFloor: minimumCashFloor,
      ),
    );
  }

  CashFlowEvent _updateEvent(
    String eventId, {
    required String action,
    required CashFlowEvent Function(CashFlowEvent) update,
  }) => repository.database.transaction(() {
    final current = _event(eventId);
    if (current.status == CashFlowStatus.settled) {
      throw StateError('Settled events cannot be changed');
    }
    final updated = update(current);
    repository.saveEvent(updated, action: action);
    return updated;
  });

  CashFlowEvent _event(String id) {
    final event = repository.eventById(id);
    if (event == null) throw StateError('Event not found: $id');
    return event;
  }

  Investment _investment(String id) {
    final investment = repository.investmentById(id);
    if (investment == null) throw StateError('Investment not found: $id');
    return investment;
  }

  void _saveInvestmentReminder(Investment investment, String eventId) {
    repository.saveReminder(
      Reminder(
        id: '${investment.id}-return-reminder',
        title: 'Check ${investment.name} return',
        dueDate: investment.expectedReturnDate,
        relatedId: eventId,
      ),
    );
  }
}

Money _nonNegative(Money amount, String name) {
  if (amount.minorUnits < 0) {
    throw ArgumentError.value(amount, name, 'must not be negative');
  }
  return amount;
}
