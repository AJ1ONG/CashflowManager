import '../../domain/models.dart';
import '../database/app_database.dart';

class CashflowRepository {
  const CashflowRepository(this.database);

  final AppDatabase database;

  void saveAccount({
    required String id,
    required String name,
    required Money balance,
  }) {
    database.connection.execute(
      '''
        INSERT INTO accounts (id, name, balance_minor)
        VALUES (?, ?, ?)
        ON CONFLICT (id) DO UPDATE SET
          name = excluded.name,
          balance_minor = excluded.balance_minor
      ''',
      [id, name, balance.minorUnits],
    );
  }

  Money get totalCash {
    final value =
        database.connection
                .select(
                  'SELECT COALESCE(SUM(balance_minor), 0) AS total FROM accounts',
                )
                .single['total']
            as int;
    return Money(value);
  }

  Money? accountBalance(String id) {
    final rows = database.connection.select(
      'SELECT balance_minor FROM accounts WHERE id = ?',
      [id],
    );
    return rows.isEmpty ? null : Money(rows.single['balance_minor'] as int);
  }

  void updateAccountBalance(String id, Money balance) {
    database.connection.execute(
      'UPDATE accounts SET balance_minor = ? WHERE id = ?',
      [balance.minorUnits, id],
    );
  }

  bool saveEvent(CashFlowEvent event, {String action = 'saved'}) {
    if (action.isEmpty) throw ArgumentError.value(action, 'action');

    return database.transaction(() {
      final current = eventById(event.id);
      if (current != null && _sameEvent(current, event)) return false;

      database.connection.execute('''
          INSERT INTO cash_flow_events (
            id, name, effective_date, expected_amount_minor,
            confirmed_amount_minor, actual_amount_minor
          ) VALUES (?, ?, ?, ?, ?, ?)
          ON CONFLICT (id) DO UPDATE SET
            name = excluded.name,
            effective_date = excluded.effective_date,
            expected_amount_minor = excluded.expected_amount_minor,
            confirmed_amount_minor = excluded.confirmed_amount_minor,
            actual_amount_minor = excluded.actual_amount_minor
        ''', _eventValues(event));
      database.connection.execute(
        '''
          INSERT INTO cash_flow_event_revisions (
            event_id, changed_at, action, name, effective_date,
            expected_amount_minor, confirmed_amount_minor, actual_amount_minor
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          event.id,
          DateTime.now().toUtc().toIso8601String(),
          action,
          ..._eventValues(event).skip(1),
        ],
      );
      return true;
    });
  }

  CashFlowEvent? eventById(String id) {
    final rows = database.connection.select(
      'SELECT * FROM cash_flow_events WHERE id = ?',
      [id],
    );
    return rows.isEmpty ? null : _eventFromRow(rows.single);
  }

  List<CashFlowEvent> get events => database.connection
      .select('SELECT * FROM cash_flow_events ORDER BY effective_date, id')
      .map(_eventFromRow)
      .toList(growable: false);

  List<CashFlowEventRevision> revisionsForEvent(String eventId) => database
      .connection
      .select(
        '''
          SELECT revision_id, changed_at, action, event_id AS id, name,
                 effective_date, expected_amount_minor,
                 confirmed_amount_minor, actual_amount_minor
          FROM cash_flow_event_revisions
          WHERE event_id = ? ORDER BY revision_id
        ''',
        [eventId],
      )
      .map(
        (row) => CashFlowEventRevision(
          revisionId: row['revision_id'] as int,
          changedAt: DateTime.parse(row['changed_at'] as String),
          action: row['action'] as String,
          event: _eventFromRow(row),
        ),
      )
      .toList(growable: false);

  void saveRule(CashFlowRule rule) {
    database.connection.execute(
      '''
        INSERT INTO cash_flow_rules (
          id, name, amount_minor, start_date, end_date, frequency
        ) VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT (id) DO UPDATE SET
          name = excluded.name,
          amount_minor = excluded.amount_minor,
          start_date = excluded.start_date,
          end_date = excluded.end_date,
          frequency = excluded.frequency
      ''',
      [
        rule.id,
        rule.name,
        rule.amount.minorUnits,
        _dateText(rule.startDate),
        rule.endDate == null ? null : _dateText(rule.endDate!),
        rule.frequency.name,
      ],
    );
  }

  List<CashFlowRule> get rules => database.connection
      .select('SELECT * FROM cash_flow_rules ORDER BY start_date, id')
      .map(
        (row) => CashFlowRule(
          id: row['id'] as String,
          name: row['name'] as String,
          amount: Money(row['amount_minor'] as int),
          startDate: DateTime.parse(row['start_date'] as String),
          endDate: _optionalDate(row['end_date']),
          frequency: RecurrenceFrequency.values.byName(
            row['frequency'] as String,
          ),
        ),
      )
      .toList(growable: false);

  void saveCreditCard(CreditCard card) {
    database.connection.execute(
      '''
        INSERT INTO credit_cards (
          id, name, statement_day, payment_day, default_expected_bill_minor
        ) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT (id) DO UPDATE SET
          name = excluded.name,
          statement_day = excluded.statement_day,
          payment_day = excluded.payment_day,
          default_expected_bill_minor = excluded.default_expected_bill_minor
      ''',
      [
        card.id,
        card.name,
        card.statementDay,
        card.paymentDay,
        card.defaultExpectedBill.minorUnits,
      ],
    );
  }

  List<CreditCard> get creditCards => database.connection
      .select('SELECT * FROM credit_cards ORDER BY name, id')
      .map(
        (row) => CreditCard(
          id: row['id'] as String,
          name: row['name'] as String,
          statementDay: row['statement_day'] as int,
          paymentDay: row['payment_day'] as int,
          defaultExpectedBill: Money(row['default_expected_bill_minor'] as int),
        ),
      )
      .toList(growable: false);

  void saveIncome(IncomeSource income) {
    database.connection.execute(
      '''
        INSERT INTO income_sources (
          id, name, expected_amount_minor, start_date, frequency, mode,
          tax_profile_id, social_insurance_profile_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (id) DO UPDATE SET
          name = excluded.name,
          expected_amount_minor = excluded.expected_amount_minor,
          start_date = excluded.start_date,
          frequency = excluded.frequency,
          mode = excluded.mode,
          tax_profile_id = excluded.tax_profile_id,
          social_insurance_profile_id = excluded.social_insurance_profile_id
      ''',
      [
        income.id,
        income.name,
        income.expectedAmount.minorUnits,
        _dateText(income.startDate),
        income.frequency.name,
        income.mode.name,
        income.taxProfileId,
        income.socialInsuranceProfileId,
      ],
    );
  }

  List<IncomeSource> get incomeSources => database.connection
      .select('SELECT * FROM income_sources ORDER BY start_date, id')
      .map(
        (row) => IncomeSource(
          id: row['id'] as String,
          name: row['name'] as String,
          expectedAmount: Money(row['expected_amount_minor'] as int),
          startDate: DateTime.parse(row['start_date'] as String),
          frequency: RecurrenceFrequency.values.byName(
            row['frequency'] as String,
          ),
          mode: IncomeMode.values.byName(row['mode'] as String),
          taxProfileId: row['tax_profile_id'] as String?,
          socialInsuranceProfileId:
              row['social_insurance_profile_id'] as String?,
        ),
      )
      .toList(growable: false);

  void saveInvestment(Investment investment) {
    database.connection.execute(
      '''
        INSERT INTO investments (
          id, name, principal_minor, investment_date,
          expected_return_minor, expected_return_date
        ) VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT (id) DO UPDATE SET
          name = excluded.name,
          principal_minor = excluded.principal_minor,
          investment_date = excluded.investment_date,
          expected_return_minor = excluded.expected_return_minor,
          expected_return_date = excluded.expected_return_date
      ''',
      [
        investment.id,
        investment.name,
        investment.principal.minorUnits,
        _dateText(investment.investmentDate),
        investment.expectedReturn.minorUnits,
        _dateText(investment.expectedReturnDate),
      ],
    );
  }

  List<Investment> get investments => database.connection
      .select('SELECT * FROM investments ORDER BY investment_date, id')
      .map(
        (row) => Investment(
          id: row['id'] as String,
          name: row['name'] as String,
          principal: Money(row['principal_minor'] as int),
          investmentDate: DateTime.parse(row['investment_date'] as String),
          expectedReturn: Money(row['expected_return_minor'] as int),
          expectedReturnDate: DateTime.parse(
            row['expected_return_date'] as String,
          ),
        ),
      )
      .toList(growable: false);

  Investment? investmentById(String id) {
    final rows = database.connection.select(
      'SELECT * FROM investments WHERE id = ?',
      [id],
    );
    return rows.isEmpty ? null : _investmentFromRow(rows.single);
  }

  void saveReminder(Reminder reminder) {
    database.connection.execute(
      '''
        INSERT INTO reminders (id, title, due_date, related_id)
        VALUES (?, ?, ?, ?)
        ON CONFLICT (id) DO UPDATE SET
          title = excluded.title,
          due_date = excluded.due_date,
          related_id = excluded.related_id
      ''',
      [
        reminder.id,
        reminder.title,
        _dateText(reminder.dueDate),
        reminder.relatedId,
      ],
    );
  }

  List<Reminder> get reminders => database.connection
      .select('SELECT * FROM reminders ORDER BY due_date, id')
      .map(
        (row) => Reminder(
          id: row['id'] as String,
          title: row['title'] as String,
          dueDate: DateTime.parse(row['due_date'] as String),
          relatedId: row['related_id'] as String,
        ),
      )
      .toList(growable: false);

  void deleteReminder(String id) {
    database.connection.execute('DELETE FROM reminders WHERE id = ?', [id]);
  }

  void saveTaxProfile({
    required String id,
    required String jurisdiction,
    required int taxYear,
    required String ruleVersion,
  }) {
    database.connection.execute(
      '''
        INSERT INTO tax_profiles (id, jurisdiction, tax_year, rule_version)
        VALUES (?, ?, ?, ?)
        ON CONFLICT (id) DO UPDATE SET
          jurisdiction = excluded.jurisdiction,
          tax_year = excluded.tax_year,
          rule_version = excluded.rule_version
      ''',
      [id, jurisdiction, taxYear, ruleVersion],
    );
  }
}

List<Object?> _eventValues(CashFlowEvent event) => [
  event.id,
  event.name,
  _dateText(event.effectiveDate),
  event.expectedAmount.minorUnits,
  event.confirmedAmount?.minorUnits,
  event.actualAmount?.minorUnits,
];

CashFlowEvent _eventFromRow(Map<String, dynamic> row) => CashFlowEvent(
  id: row['id'] as String,
  name: row['name'] as String,
  effectiveDate: DateTime.parse(row['effective_date'] as String),
  expectedAmount: Money(row['expected_amount_minor'] as int),
  confirmedAmount: _optionalMoney(row['confirmed_amount_minor']),
  actualAmount: _optionalMoney(row['actual_amount_minor']),
);

Investment _investmentFromRow(Map<String, dynamic> row) => Investment(
  id: row['id'] as String,
  name: row['name'] as String,
  principal: Money(row['principal_minor'] as int),
  investmentDate: DateTime.parse(row['investment_date'] as String),
  expectedReturn: Money(row['expected_return_minor'] as int),
  expectedReturnDate: DateTime.parse(row['expected_return_date'] as String),
);

bool _sameEvent(CashFlowEvent first, CashFlowEvent second) =>
    first.id == second.id &&
    first.name == second.name &&
    dateOnly(first.effectiveDate) == dateOnly(second.effectiveDate) &&
    first.expectedAmount == second.expectedAmount &&
    first.confirmedAmount == second.confirmedAmount &&
    first.actualAmount == second.actualAmount;

String _dateText(DateTime value) => dateOnly(value).toIso8601String();

DateTime? _optionalDate(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

Money? _optionalMoney(Object? value) =>
    value == null ? null : Money(value as int);
