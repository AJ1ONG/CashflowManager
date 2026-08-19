enum CashFlowStatus { estimated, confirmed, settled }

enum RecurrenceFrequency { once, monthly, yearly }

enum IncomeMode { net, gross }

DateTime dateOnly(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

DateTime clampedDate(int year, int month, int day) {
  final lastDay = DateTime.utc(year, month + 1, 0).day;
  return DateTime.utc(year, month, day > lastDay ? lastDay : day);
}

class Money implements Comparable<Money> {
  const Money(this.minorUnits);

  static const zero = Money(0);

  static Money? tryParse(String input) {
    final value = input.trim().replaceAll(',', '').replaceAll('¥', '');
    final match = RegExp(r'^([+-]?)(\d+)(?:\.(\d{1,2}))?$').firstMatch(value);
    if (match == null) return null;
    final whole = int.parse(match.group(2)!);
    final fraction = (match.group(3) ?? '').padRight(2, '0');
    final minorUnits =
        whole * 100 + (fraction.isEmpty ? 0 : int.parse(fraction));
    return Money(match.group(1) == '-' ? -minorUnits : minorUnits);
  }

  final int minorUnits;

  Money operator +(Money other) => Money(minorUnits + other.minorUnits);

  Money operator -(Money other) => Money(minorUnits - other.minorUnits);

  Money operator -() => Money(-minorUnits);

  String format({String symbol = '¥'}) {
    final absolute = minorUnits.abs();
    final amount =
        '${absolute ~/ 100}.${(absolute % 100).toString().padLeft(2, '0')}';
    return minorUnits < 0 ? '-$symbol$amount' : '$symbol$amount';
  }

  @override
  int compareTo(Money other) => minorUnits.compareTo(other.minorUnits);

  @override
  bool operator ==(Object other) =>
      other is Money && other.minorUnits == minorUnits;

  @override
  int get hashCode => minorUnits.hashCode;

  @override
  String toString() => format();
}

class CashFlowEvent {
  const CashFlowEvent({
    required this.id,
    required this.name,
    required this.effectiveDate,
    required this.expectedAmount,
    this.confirmedAmount,
    this.actualAmount,
  });

  final String id;
  final String name;
  final DateTime effectiveDate;
  final Money expectedAmount;
  final Money? confirmedAmount;
  final Money? actualAmount;

  Money get effectiveAmount =>
      actualAmount ?? confirmedAmount ?? expectedAmount;

  CashFlowStatus get status => actualAmount != null
      ? CashFlowStatus.settled
      : confirmedAmount != null
      ? CashFlowStatus.confirmed
      : CashFlowStatus.estimated;

  CashFlowEvent confirm(Money amount) => CashFlowEvent(
    id: id,
    name: name,
    effectiveDate: effectiveDate,
    expectedAmount: expectedAmount,
    confirmedAmount: amount,
    actualAmount: actualAmount,
  );

  CashFlowEvent settle(Money amount) => CashFlowEvent(
    id: id,
    name: name,
    effectiveDate: effectiveDate,
    expectedAmount: expectedAmount,
    confirmedAmount: confirmedAmount,
    actualAmount: amount,
  );
}

class CashFlowEventRevision {
  const CashFlowEventRevision({
    required this.revisionId,
    required this.changedAt,
    required this.action,
    required this.event,
  });

  final int revisionId;
  final DateTime changedAt;
  final String action;
  final CashFlowEvent event;
}

class CashFlowRule {
  CashFlowRule({
    required this.id,
    required this.name,
    required this.amount,
    required this.startDate,
    required this.frequency,
    this.endDate,
  }) {
    if (endDate != null && dateOnly(endDate!).isBefore(dateOnly(startDate))) {
      throw ArgumentError.value(
        endDate,
        'endDate',
        'must not precede startDate',
      );
    }
  }

  final String id;
  final String name;
  final Money amount;
  final DateTime startDate;
  final DateTime? endDate;
  final RecurrenceFrequency frequency;
}

class CreditCard {
  CreditCard({
    required this.id,
    required this.name,
    required this.statementDay,
    required this.paymentDay,
    required this.defaultExpectedBill,
  }) {
    if (statementDay < 1 || statementDay > 31) {
      throw ArgumentError.value(statementDay, 'statementDay', 'must be 1-31');
    }
    if (paymentDay < 1 || paymentDay > 31) {
      throw ArgumentError.value(paymentDay, 'paymentDay', 'must be 1-31');
    }
    if (defaultExpectedBill.minorUnits < 0) {
      throw ArgumentError.value(
        defaultExpectedBill,
        'defaultExpectedBill',
        'must not be negative',
      );
    }
  }

  final String id;
  final String name;
  final int statementDay;
  final int paymentDay;
  final Money defaultExpectedBill;

  DateTime paymentDateForStatement(DateTime statementDate) {
    final statement = dateOnly(statementDate);
    final monthOffset = paymentDay <= statementDay ? 1 : 0;
    return clampedDate(
      statement.year,
      statement.month + monthOffset,
      paymentDay,
    );
  }

  CashFlowEvent expectedPaymentForStatement(DateTime statementDate) {
    final paymentDate = paymentDateForStatement(statementDate);
    return CashFlowEvent(
      id: '$id-${_dateKey(paymentDate)}',
      name: '$name repayment',
      effectiveDate: paymentDate,
      expectedAmount: -defaultExpectedBill,
    );
  }
}

class IncomeSource {
  const IncomeSource({
    required this.id,
    required this.name,
    required this.expectedAmount,
    required this.startDate,
    required this.frequency,
    this.mode = IncomeMode.net,
    this.taxProfileId,
    this.socialInsuranceProfileId,
  });

  final String id;
  final String name;
  final Money expectedAmount;
  final DateTime startDate;
  final RecurrenceFrequency frequency;
  final IncomeMode mode;
  final String? taxProfileId;
  final String? socialInsuranceProfileId;

  CashFlowRule toRule({Money? calculatedNetAmount}) {
    if (mode == IncomeMode.gross && calculatedNetAmount == null) {
      throw StateError('Gross income requires a calculated net amount');
    }
    return CashFlowRule(
      id: id,
      name: name,
      amount: calculatedNetAmount ?? expectedAmount,
      startDate: startDate,
      frequency: frequency,
    );
  }
}

class Investment {
  Investment({
    required this.id,
    required this.name,
    required this.principal,
    required this.investmentDate,
    required this.expectedReturn,
    required this.expectedReturnDate,
  }) {
    if (principal.minorUnits <= 0) {
      throw ArgumentError.value(principal, 'principal', 'must be positive');
    }
    if (expectedReturn.minorUnits < 0) {
      throw ArgumentError.value(
        expectedReturn,
        'expectedReturn',
        'must not be negative',
      );
    }
  }

  final String id;
  final String name;
  final Money principal;
  final DateTime investmentDate;
  final Money expectedReturn;
  final DateTime expectedReturnDate;

  List<CashFlowEvent> get initialEvents => [
    CashFlowEvent(
      id: '$id-principal',
      name: '$name principal',
      effectiveDate: investmentDate,
      expectedAmount: -principal,
      actualAmount: -principal,
    ),
    CashFlowEvent(
      id: '$id-return',
      name: '$name return',
      effectiveDate: expectedReturnDate,
      expectedAmount: expectedReturn,
    ),
  ];

  List<CashFlowEvent> recordReturn({
    required Money received,
    DateTime? remainingDate,
  }) {
    if (received.minorUnits < 0 ||
        received.minorUnits > expectedReturn.minorUnits) {
      throw ArgumentError.value(
        received,
        'received',
        'must be between zero and expected return',
      );
    }

    final settled = CashFlowEvent(
      id: '$id-return',
      name: '$name return',
      effectiveDate: expectedReturnDate,
      expectedAmount: expectedReturn,
      actualAmount: received,
    );
    final remaining = expectedReturn - received;
    if (remaining == Money.zero) return [settled];
    if (remainingDate == null ||
        !dateOnly(remainingDate).isAfter(dateOnly(expectedReturnDate))) {
      throw ArgumentError.value(
        remainingDate,
        'remainingDate',
        'must be after the original return date',
      );
    }

    return [
      settled,
      CashFlowEvent(
        id: '$id-return-${_dateKey(remainingDate)}',
        name: '$name remaining return',
        effectiveDate: remainingDate,
        expectedAmount: remaining,
      ),
    ];
  }
}

class Reminder {
  const Reminder({
    required this.id,
    required this.title,
    required this.dueDate,
    required this.relatedId,
  });

  final String id;
  final String title;
  final DateTime dueDate;
  final String relatedId;
}

String _dateKey(DateTime value) {
  final date = dateOnly(value);
  return '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';
}
