import 'dart:math';

import 'models.dart';

class BalancePoint {
  const BalancePoint({required this.date, required this.balance});

  final DateTime date;
  final Money balance;
}

class CashFlowForecast {
  const CashFlowForecast({
    required this.points,
    required this.minimumBalance,
    required this.minimumBalanceDate,
  });

  final List<BalancePoint> points;
  final Money minimumBalance;
  final DateTime minimumBalanceDate;
}

class CashFlowEngine {
  const CashFlowEngine();

  CashFlowForecast forecast({
    required Money currentCash,
    required Iterable<CashFlowEvent> events,
    required DateTime from,
    required DateTime through,
  }) {
    final firstDate = dateOnly(from);
    final lastDate = dateOnly(through);
    if (lastDate.isBefore(firstDate)) {
      throw ArgumentError.value(through, 'through', 'must not precede from');
    }

    final deltas = _eventDeltas(events, firstDate, lastDate);
    final points = <BalancePoint>[];
    var balance = currentCash.minorUnits;
    var minimum = balance;
    var minimumDate = firstDate;

    for (
      var date = firstDate;
      !date.isAfter(lastDate);
      date = date.add(const Duration(days: 1))
    ) {
      balance += deltas[date] ?? 0;
      points.add(BalancePoint(date: date, balance: Money(balance)));
      if (balance < minimum) {
        minimum = balance;
        minimumDate = date;
      }
    }

    return CashFlowForecast(
      points: List.unmodifiable(points),
      minimumBalance: Money(minimum),
      minimumBalanceDate: minimumDate,
    );
  }
}

class RecurrenceEngine {
  const RecurrenceEngine();

  List<CashFlowEvent> expand(CashFlowRule rule, {required DateTime through}) {
    final start = dateOnly(rule.startDate);
    final horizon = dateOnly(through);
    final end = rule.endDate == null ? horizon : dateOnly(rule.endDate!);
    final lastDate = end.isBefore(horizon) ? end : horizon;
    if (lastDate.isBefore(start)) return const [];

    final dates = switch (rule.frequency) {
      RecurrenceFrequency.once => [start],
      RecurrenceFrequency.monthly => _monthlyDates(start, lastDate),
      RecurrenceFrequency.yearly => _yearlyDates(start, lastDate),
    };

    return List.unmodifiable(
      dates.map(
        (date) => CashFlowEvent(
          id: '${rule.id}-${_dateKey(date)}',
          name: rule.name,
          effectiveDate: date,
          expectedAmount: rule.amount,
        ),
      ),
    );
  }

  List<DateTime> _monthlyDates(DateTime start, DateTime through) {
    final dates = <DateTime>[];
    for (var offset = 0; ; offset++) {
      final monthIndex = start.year * 12 + start.month - 1 + offset;
      final date = clampedDate(
        monthIndex ~/ 12,
        monthIndex % 12 + 1,
        start.day,
      );
      if (date.isAfter(through)) return dates;
      dates.add(date);
    }
  }

  List<DateTime> _yearlyDates(DateTime start, DateTime through) {
    final dates = <DateTime>[];
    for (var year = start.year; ; year++) {
      final date = clampedDate(year, start.month, start.day);
      if (date.isAfter(through)) return dates;
      dates.add(date);
    }
  }
}

class LiquidityRequirement {
  const LiquidityRequirement({
    required this.date,
    required this.cumulativeReturn,
    required this.incrementalReturn,
  });

  final DateTime date;
  final Money cumulativeReturn;
  final Money incrementalReturn;
}

class LiquidityEngine {
  const LiquidityEngine();

  Money deployableCapital({
    required Money currentCash,
    required Iterable<CashFlowEvent> events,
    required DateTime from,
    required DateTime through,
    Money minimumCashFloor = Money.zero,
  }) {
    _checkNonNegative(minimumCashFloor, 'minimumCashFloor');
    final forecast = const CashFlowEngine().forecast(
      currentCash: currentCash,
      events: events,
      from: from,
      through: through,
    );
    return Money(
      max(0, forecast.minimumBalance.minorUnits - minimumCashFloor.minorUnits),
    );
  }

  List<LiquidityRequirement> requiredReturnSchedule({
    required Money currentCash,
    required Money deployment,
    required Iterable<CashFlowEvent> events,
    required DateTime from,
    required DateTime through,
    Money minimumCashFloor = Money.zero,
  }) {
    _checkNonNegative(deployment, 'deployment');
    _checkNonNegative(minimumCashFloor, 'minimumCashFloor');
    final firstDate = dateOnly(from);
    final lastDate = dateOnly(through);
    if (lastDate.isBefore(firstDate)) {
      throw ArgumentError.value(through, 'through', 'must not precede from');
    }

    final deltas = _eventDeltas(events, firstDate, lastDate);
    final requirements = <LiquidityRequirement>[];
    var projectedBalance = currentCash.minorUnits - deployment.minorUnits;
    var cumulativeRequired = 0;

    void recordRequirement(DateTime date) {
      final shortfall = max(0, minimumCashFloor.minorUnits - projectedBalance);
      if (shortfall <= cumulativeRequired) return;
      requirements.add(
        LiquidityRequirement(
          date: date,
          cumulativeReturn: Money(shortfall),
          incrementalReturn: Money(shortfall - cumulativeRequired),
        ),
      );
      cumulativeRequired = shortfall;
    }

    recordRequirement(firstDate);
    for (final entry in deltas.entries) {
      projectedBalance += entry.value;
      recordRequirement(entry.key);
    }

    return List.unmodifiable(requirements);
  }
}

Map<DateTime, int> _eventDeltas(
  Iterable<CashFlowEvent> events,
  DateTime from,
  DateTime through,
) {
  final deltas = <DateTime, int>{};
  for (final event in events) {
    final date = dateOnly(event.effectiveDate);
    if (date.isBefore(from) || date.isAfter(through)) continue;
    deltas.update(
      date,
      (amount) => amount + event.effectiveAmount.minorUnits,
      ifAbsent: () => event.effectiveAmount.minorUnits,
    );
  }
  return Map.fromEntries(
    deltas.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

void _checkNonNegative(Money amount, String name) {
  if (amount.minorUnits < 0) {
    throw ArgumentError.value(amount, name, 'must not be negative');
  }
}

String _dateKey(DateTime value) {
  final date = dateOnly(value);
  return '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';
}
