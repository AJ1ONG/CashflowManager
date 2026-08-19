import 'package:flutter/material.dart';

import '../application/cashflow_service.dart';
import '../domain/models.dart';

class CashflowApp extends StatelessWidget {
  const CashflowApp({
    super.key,
    required this.service,
    this.now,
    this.onDispose,
  });

  final CashflowService service;
  final DateTime? now;
  final VoidCallback? onDispose;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '现金流管理',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B52)),
        scaffoldBackgroundColor: const Color(0xFFF4F7F5),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
        useMaterial3: true,
      ),
      home: _CashflowShell(
        service: service,
        today: dateOnly(now ?? DateTime.now()),
        onDispose: onDispose,
      ),
    );
  }
}

class _CashflowShell extends StatefulWidget {
  const _CashflowShell({
    required this.service,
    required this.today,
    this.onDispose,
  });

  final CashflowService service;
  final DateTime today;
  final VoidCallback? onDispose;

  @override
  State<_CashflowShell> createState() => _CashflowShellState();
}

class _CashflowShellState extends State<_CashflowShell> {
  var _selectedIndex = 0;

  static const _destinations = [
    (icon: Icons.dashboard_outlined, selected: Icons.dashboard, label: '概览'),
    (icon: Icons.timeline_outlined, selected: Icons.timeline, label: '时间线'),
    (icon: Icons.savings_outlined, selected: Icons.savings, label: '投资'),
    (icon: Icons.settings_outlined, selected: Icons.settings, label: '设置'),
  ];

  @override
  void dispose() {
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = switch (_selectedIndex) {
      0 => _DashboardPage(service: widget.service, today: widget.today),
      1 => _TimelinePage(
        service: widget.service,
        today: widget.today,
        onChanged: _refresh,
      ),
      2 => _InvestmentsPage(
        service: widget.service,
        today: widget.today,
        onChanged: _refresh,
      ),
      _ => _SettingsPage(
        service: widget.service,
        today: widget.today,
        onChanged: _refresh,
      ),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        return Scaffold(
          appBar: AppBar(
            title: Text(_destinations[_selectedIndex].label),
            actions: [
              IconButton(
                tooltip: '刷新',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: wide
              ? Row(
                  children: [
                    NavigationRail(
                      extended: constraints.maxWidth >= 1100,
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: _selectPage,
                      labelType: constraints.maxWidth >= 1100
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.selected,
                      leading: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Icon(Icons.account_balance_wallet, size: 30),
                      ),
                      destinations: [
                        for (final destination in _destinations)
                          NavigationRailDestination(
                            icon: Icon(destination.icon),
                            selectedIcon: Icon(destination.selected),
                            label: Text(destination.label),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: page),
                  ],
                )
              : page,
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _selectPage,
                  destinations: [
                    for (final destination in _destinations)
                      NavigationDestination(
                        icon: Icon(destination.icon),
                        selectedIcon: Icon(destination.selected),
                        label: destination.label,
                      ),
                  ],
                ),
        );
      },
    );
  }

  void _selectPage(int index) => setState(() => _selectedIndex = index);

  void _refresh() => setState(() {});
}

class _DashboardPage extends StatelessWidget {
  const _DashboardPage({required this.service, required this.today});

  final CashflowService service;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final through = today.add(const Duration(days: 90));
    final analysis = service.analyze(
      from: today,
      through: through,
      deployment: service.currentCash,
    );
    final upcoming = service.events
        .where(
          (event) =>
              !event.effectiveDate.isBefore(today) &&
              event.status != CashFlowStatus.settled,
        )
        .take(6)
        .toList(growable: false);

    return _PageFrame(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('未来 90 天资金概览', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 600
                  ? 1
                  : constraints.maxWidth < 900
                  ? 2
                  : 3;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 3,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 132,
                ),
                itemBuilder: (context, index) => switch (index) {
                  0 => _MetricCard(
                    label: '当前现金',
                    value: analysis.currentCash.format(),
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                  1 => _MetricCard(
                    label: '可投入资金',
                    value: analysis.deployableCapital.format(),
                    icon: Icons.rocket_launch_outlined,
                  ),
                  _ => _MetricCard(
                    label: '未来最低余额',
                    value: analysis.forecast.minimumBalance.format(),
                    detail: _formatDate(analysis.forecast.minimumBalanceDate),
                    icon: Icons.south_east,
                  ),
                },
              );
            },
          ),
          const SizedBox(height: 24),
          _SectionTitle(
            title: '资金回流节点',
            count: analysis.requiredReturnSchedule.length,
          ),
          const SizedBox(height: 8),
          Card(
            child: analysis.requiredReturnSchedule.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('当前计划期内没有必须回流的资金。'),
                  )
                : Column(
                    children: [
                      for (final item in analysis.requiredReturnSchedule)
                        ListTile(
                          leading: const Icon(Icons.flag_outlined),
                          title: Text(_formatDate(item.date)),
                          subtitle: Text(
                            '本次需回流 ${item.incrementalReturn.format()}',
                          ),
                          trailing: Text(
                            item.cumulativeReturn.format(),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 24),
          _SectionTitle(title: '近期现金事件', count: upcoming.length),
          const SizedBox(height: 8),
          Card(
            child: upcoming.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('还没有未来现金事件，请到“时间线”添加。'),
                  )
                : Column(
                    children: [
                      for (final event in upcoming)
                        ListTile(
                          leading: Icon(
                            event.effectiveAmount.minorUnits >= 0
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                          ),
                          title: Text(event.name),
                          subtitle: Text(
                            '${_formatDate(event.effectiveDate)} · ${_statusText(event.status)}',
                          ),
                          trailing: _AmountText(event.effectiveAmount),
                        ),
                    ],
                  ),
          ),
          if (service.reminders.isNotEmpty) ...[
            const SizedBox(height: 24),
            _SectionTitle(title: '待处理提醒', count: service.reminders.length),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (final reminder in service.reminders.take(6))
                    ListTile(
                      leading: const Icon(Icons.notifications_none),
                      title: Text(reminder.title),
                      trailing: Text(_formatDate(reminder.dueDate)),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimelinePage extends StatelessWidget {
  const _TimelinePage({
    required this.service,
    required this.today,
    required this.onChanged,
  });

  final CashflowService service;
  final DateTime today;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final events = service.events;
    return _PageFrame(
      child: Column(
        children: [
          _PageHeader(
            title: '现金事件',
            subtitle: '预估 → 已确认 → 已结算，所有金额变化都会保留历史。',
            actionLabel: '添加事件',
            actionIcon: Icons.add,
            onAction: () => _addEvent(context),
          ),
          Expanded(
            child: events.isEmpty
                ? const _EmptyState(
                    icon: Icons.timeline,
                    title: '还没有现金事件',
                    message: '添加工资、固定支出、奖金或其他未来资金变化。',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    itemCount: events.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _EventCard(
                      event: events[index],
                      onConfirm: () =>
                          _changeAmount(context, events[index], settle: false),
                      onSettle: () =>
                          _changeAmount(context, events[index], settle: true),
                      onHistory: () => _showEventHistory(
                        context,
                        service.revisionsForEvent(events[index].id),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _addEvent(BuildContext context) async {
    final draft = await _showEventDialog(context, today);
    if (draft == null || !context.mounted) return;
    _runAction(context, () {
      service.createEvent(
        CashFlowEvent(
          id: _newId('event'),
          name: draft.name,
          effectiveDate: draft.date,
          expectedAmount: draft.amount,
        ),
      );
      onChanged();
    });
  }

  Future<void> _changeAmount(
    BuildContext context,
    CashFlowEvent event, {
    required bool settle,
  }) async {
    final amount = await _showMoneyDialog(
      context,
      title: settle ? '记录实际到账/扣款' : '确认金额',
      initial: event.effectiveAmount,
      allowNegative: true,
    );
    if (amount == null || !context.mounted) return;
    _runAction(context, () {
      if (settle) {
        service.settleEvent(event.id, amount);
      } else {
        service.confirmEvent(event.id, amount);
      }
      onChanged();
    });
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.onConfirm,
    required this.onSettle,
    required this.onHistory,
  });

  final CashFlowEvent event;
  final VoidCallback onConfirm;
  final VoidCallback onSettle;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                event.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 8),
            _StatusChip(status: event.status),
          ],
        ),
        const SizedBox(height: 6),
        Text(_formatDate(event.effectiveDate)),
        const SizedBox(height: 4),
        Text(
          [
            '预估 ${event.expectedAmount.format()}',
            if (event.confirmedAmount != null)
              '确认 ${event.confirmedAmount!.format()}',
            if (event.actualAmount != null)
              '实际 ${event.actualAmount!.format()}',
          ].join('  ·  '),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
    final actions = Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _AmountText(event.effectiveAmount),
        if (event.status != CashFlowStatus.settled)
          TextButton(
            key: ValueKey('confirm-${event.id}'),
            onPressed: onConfirm,
            child: const Text('确认'),
          ),
        if (event.status != CashFlowStatus.settled)
          FilledButton.tonal(
            key: ValueKey('settle-${event.id}'),
            onPressed: onSettle,
            child: const Text('结算'),
          ),
        IconButton(
          tooltip: '历史记录',
          onPressed: onHistory,
          icon: const Icon(Icons.history),
        ),
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 620
              ? Row(
                  children: [
                    Expanded(child: info),
                    const SizedBox(width: 16),
                    actions,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    info,
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                ),
        ),
      ),
    );
  }
}

class _InvestmentsPage extends StatelessWidget {
  const _InvestmentsPage({
    required this.service,
    required this.today,
    required this.onChanged,
  });

  final CashflowService service;
  final DateTime today;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final investments = service.investments;
    return _PageFrame(
      child: Column(
        children: [
          _PageHeader(
            title: '投资回流',
            subtitle: '投资到期不会自动结算，需要手动确认到账、部分到账或延期。',
            actionLabel: '新增投资',
            actionIcon: Icons.add,
            onAction: () => _addInvestment(context),
          ),
          Expanded(
            child: investments.isEmpty
                ? const _EmptyState(
                    icon: Icons.savings_outlined,
                    title: '还没有投资记录',
                    message: '新增投资后会生成本金支出和预期回流事件。',
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    itemCount: investments.length,
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 520,
                          mainAxisExtent: 230,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                        ),
                    itemBuilder: (context, index) {
                      final investment = investments[index];
                      final returnEvent = service.events
                          .where(
                            (event) => event.id == '${investment.id}-return',
                          )
                          .firstOrNull;
                      return _InvestmentCard(
                        investment: investment,
                        returnStatus:
                            returnEvent?.status ?? CashFlowStatus.estimated,
                        onUpdate: () => _updateInvestment(context, investment),
                        onRecord: () => _recordReturn(context, investment),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _addInvestment(BuildContext context) async {
    final draft = await _showInvestmentDialog(context, today);
    if (draft == null || !context.mounted) return;
    _runAction(context, () {
      service.createInvestment(
        Investment(
          id: _newId('investment'),
          name: draft.name,
          principal: draft.principal,
          investmentDate: draft.investmentDate,
          expectedReturn: draft.expectedReturn,
          expectedReturnDate: draft.returnDate,
        ),
      );
      onChanged();
    });
  }

  Future<void> _updateInvestment(
    BuildContext context,
    Investment investment,
  ) async {
    final draft = await _showInvestmentUpdateDialog(context, investment);
    if (draft == null || !context.mounted) return;
    _runAction(context, () {
      service.updateInvestmentReturn(
        investmentId: investment.id,
        expectedAmount: draft.amount,
        expectedDate: draft.date,
      );
      onChanged();
    });
  }

  Future<void> _recordReturn(
    BuildContext context,
    Investment investment,
  ) async {
    final draft = await _showInvestmentReturnDialog(context, investment);
    if (draft == null || !context.mounted) return;
    _runAction(context, () {
      service.recordInvestmentReturn(
        investmentId: investment.id,
        received: draft.received,
        remainingDate: draft.received == investment.expectedReturn
            ? null
            : draft.remainingDate,
      );
      onChanged();
    });
  }
}

class _InvestmentCard extends StatelessWidget {
  const _InvestmentCard({
    required this.investment,
    required this.returnStatus,
    required this.onUpdate,
    required this.onRecord,
  });

  final Investment investment;
  final CashFlowStatus returnStatus;
  final VoidCallback onUpdate;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    investment.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                _StatusChip(status: returnStatus),
              ],
            ),
            const SizedBox(height: 18),
            _LabelValue(label: '投入本金', value: investment.principal.format()),
            const SizedBox(height: 8),
            _LabelValue(
              label: '预期回流',
              value: investment.expectedReturn.format(),
            ),
            const SizedBox(height: 8),
            _LabelValue(
              label: '回流日期',
              value: _formatDate(investment.expectedReturnDate),
            ),
            const Spacer(),
            if (returnStatus != CashFlowStatus.settled)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: onUpdate, child: const Text('延期/更新')),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: onRecord,
                    child: const Text('记录到账'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.service,
    required this.today,
    required this.onChanged,
  });

  final CashflowService service;
  final DateTime today;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return _PageFrame(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('基础数据', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                spacing: 24,
                runSpacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 280,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '当前现金余额',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          service.currentCash.format(),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 6),
                        const Text('更新余额时，差额会记录为已结算的余额校准事件。'),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('set-current-cash'),
                    onPressed: () => _setCurrentCash(context),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('设置余额'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _SectionTitle(title: '周期收入', count: service.incomeSources.length),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (service.incomeSources.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text('尚未设置周期收入。'),
                    )
                  else
                    for (final income in service.incomeSources)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.payments_outlined),
                        title: Text(income.name),
                        subtitle: Text(
                          '${_frequencyText(income.frequency)} · ${_formatDate(income.startDate)}',
                        ),
                        trailing: Text(income.expectedAmount.format()),
                      ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: () => _addIncome(context),
                      icon: const Icon(Icons.add),
                      label: const Text('添加周期收入'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _SectionTitle(title: '信用卡', count: service.creditCards.length),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (service.creditCards.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text('尚未设置信用卡账单。'),
                    )
                  else
                    for (final card in service.creditCards)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.credit_card),
                        title: Text(card.name),
                        subtitle: Text(
                          '账单日 ${card.statementDay} · 还款日 ${card.paymentDay}',
                        ),
                        trailing: Text(card.defaultExpectedBill.format()),
                      ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: () => _addCreditCardStatement(context),
                      icon: const Icon(Icons.add),
                      label: const Text('安排信用卡账单'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Card(
            child: ListTile(
              leading: Icon(Icons.storage_outlined),
              title: Text('本地优先存储'),
              subtitle: Text('数据保存在本机 SQLite 中，不需要联网。'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setCurrentCash(BuildContext context) async {
    final amount = await _showMoneyDialog(
      context,
      title: '设置当前现金余额',
      initial: service.currentCash,
      allowNegative: false,
    );
    if (amount == null || !context.mounted) return;
    _runAction(context, () {
      service.setCurrentCash(
        balance: amount,
        at: today,
        adjustmentId: _newId('balance-adjustment'),
      );
      onChanged();
    });
  }

  Future<void> _addIncome(BuildContext context) async {
    final draft = await _showIncomeDialog(context, today);
    if (draft == null || !context.mounted) return;
    _runAction(context, () {
      service.scheduleIncome(
        IncomeSource(
          id: _newId('income'),
          name: draft.name,
          expectedAmount: draft.amount,
          startDate: draft.startDate,
          frequency: draft.frequency,
        ),
        through: draft.startDate.add(const Duration(days: 366)),
      );
      onChanged();
    });
  }

  Future<void> _addCreditCardStatement(BuildContext context) async {
    final draft = await _showCreditCardDialog(context, today);
    if (draft == null || !context.mounted) return;
    _runAction(context, () {
      service.scheduleCreditCardStatement(
        CreditCard(
          id: _newId('card'),
          name: draft.name,
          statementDay: draft.statementDay,
          paymentDay: draft.paymentDay,
          defaultExpectedBill: draft.expectedBill,
        ),
        draft.statementDate,
      );
      onChanged();
    });
  }
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: child,
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 6),
                Text(subtitle),
              ],
            ),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: onAction,
            icon: Icon(actionIcon),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.detail,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(child: Icon(icon)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(value, style: Theme.of(context).textTheme.titleLarge),
                  if (detail != null) Text(detail!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        Text('$count 项'),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final CashFlowStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      CashFlowStatus.estimated => Theme.of(context).colorScheme.secondary,
      CashFlowStatus.confirmed => Colors.orange.shade800,
      CashFlowStatus.settled => Colors.green.shade700,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _statusText(status),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AmountText extends StatelessWidget {
  const _AmountText(this.amount);

  final Money amount;

  @override
  Widget build(BuildContext context) {
    return Text(
      amount.format(),
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: amount.minorUnits >= 0
            ? Colors.green.shade700
            : Theme.of(context).colorScheme.error,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _LabelValue extends StatelessWidget {
  const _LabelValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

Future<_EventDraft?> _showEventDialog(
  BuildContext context,
  DateTime initialDate,
) async {
  final formKey = GlobalKey<FormState>();
  var name = '';
  var amount = '';
  var date = initialDate;
  final result = await showDialog<_EventDraft>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('添加现金事件'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '名称'),
                  validator: _requiredText,
                  onChanged: (value) => name = value,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('event-amount'),
                  decoration: const InputDecoration(
                    labelText: '金额',
                    hintText: '收入填正数，支出填负数',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  validator: (value) => _moneyError(value, allowNegative: true),
                  onChanged: (value) => amount = value,
                ),
                const SizedBox(height: 12),
                _DateField(
                  label: '发生日期',
                  date: date,
                  onChanged: (value) => setDialogState(() => date = value),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('save-event'),
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(
                context,
                _EventDraft(
                  name: name.trim(),
                  amount: Money.tryParse(amount)!,
                  date: date,
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  return result;
}

Future<Money?> _showMoneyDialog(
  BuildContext context, {
  required String title,
  required Money initial,
  required bool allowNegative,
}) async {
  final formKey = GlobalKey<FormState>();
  var amount = _decimalText(initial);
  final result = await showDialog<Money>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        child: Form(
          key: formKey,
          child: TextFormField(
            key: const ValueKey('money-input'),
            initialValue: amount,
            autofocus: true,
            decoration: const InputDecoration(labelText: '金额'),
            keyboardType: TextInputType.numberWithOptions(
              decimal: true,
              signed: allowNegative,
            ),
            validator: (value) =>
                _moneyError(value, allowNegative: allowNegative),
            onChanged: (value) => amount = value,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('save-money'),
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            Navigator.pop(context, Money.tryParse(amount));
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
  return result;
}

Future<void> _showEventHistory(
  BuildContext context,
  List<CashFlowEventRevision> revisions,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('事件历史'),
      content: SizedBox(
        width: 520,
        height: 360,
        child: revisions.isEmpty
            ? const Center(child: Text('暂无历史记录。'))
            : ListView.builder(
                itemCount: revisions.length,
                itemBuilder: (context, index) {
                  final revision = revisions[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(_actionText(revision.action)),
                    subtitle: Text(
                      '${_formatDate(revision.event.effectiveDate)} · ${_statusText(revision.event.status)}',
                    ),
                    trailing: Text(revision.event.effectiveAmount.format()),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.onChanged,
  });

  final String label;
  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final selected = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime.utc(2000),
          lastDate: DateTime.utc(2100, 12, 31),
        );
        if (selected != null) onChanged(dateOnly(selected));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(_formatDate(date)),
      ),
    );
  }
}

class _EventDraft {
  const _EventDraft({
    required this.name,
    required this.amount,
    required this.date,
  });

  final String name;
  final Money amount;
  final DateTime date;
}

Future<_InvestmentDraft?> _showInvestmentDialog(
  BuildContext context,
  DateTime today,
) async {
  final formKey = GlobalKey<FormState>();
  var name = '';
  var principal = '';
  var expectedReturn = '';
  var investmentDate = today;
  var returnDate = today.add(const Duration(days: 30));
  final result = await showDialog<_InvestmentDraft>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('新增投资'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    autofocus: true,
                    decoration: const InputDecoration(labelText: '名称'),
                    validator: _requiredText,
                    onChanged: (value) => name = value,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    decoration: const InputDecoration(labelText: '投入本金'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) => _moneyError(
                      value,
                      allowNegative: false,
                      requirePositive: true,
                    ),
                    onChanged: (value) => principal = value,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    decoration: const InputDecoration(labelText: '预期回流金额'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) =>
                        _moneyError(value, allowNegative: false),
                    onChanged: (value) => expectedReturn = value,
                  ),
                  const SizedBox(height: 12),
                  _DateField(
                    label: '投资日期',
                    date: investmentDate,
                    onChanged: (value) =>
                        setDialogState(() => investmentDate = value),
                  ),
                  const SizedBox(height: 12),
                  _DateField(
                    label: '预期回流日期',
                    date: returnDate,
                    onChanged: (value) =>
                        setDialogState(() => returnDate = value),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              if (returnDate.isBefore(investmentDate)) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('回流日期不能早于投资日期。')));
                return;
              }
              Navigator.pop(
                context,
                _InvestmentDraft(
                  name: name.trim(),
                  principal: Money.tryParse(principal)!,
                  investmentDate: investmentDate,
                  expectedReturn: Money.tryParse(expectedReturn)!,
                  returnDate: returnDate,
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  return result;
}

Future<_AmountDateDraft?> _showInvestmentUpdateDialog(
  BuildContext context,
  Investment investment,
) async {
  final formKey = GlobalKey<FormState>();
  var amount = _decimalText(investment.expectedReturn);
  var date = investment.expectedReturnDate;
  final result = await showDialog<_AmountDateDraft>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('更新预期回流'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: amount,
                  decoration: const InputDecoration(labelText: '预期回流金额'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) =>
                      _moneyError(value, allowNegative: false),
                  onChanged: (value) => amount = value,
                ),
                const SizedBox(height: 12),
                _DateField(
                  label: '回流日期',
                  date: date,
                  onChanged: (value) => setDialogState(() => date = value),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(
                context,
                _AmountDateDraft(amount: Money.tryParse(amount)!, date: date),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  return result;
}

Future<_InvestmentReturnDraft?> _showInvestmentReturnDialog(
  BuildContext context,
  Investment investment,
) async {
  final formKey = GlobalKey<FormState>();
  var received = _decimalText(investment.expectedReturn);
  var remainingDate = investment.expectedReturnDate.add(
    const Duration(days: 7),
  );
  final result = await showDialog<_InvestmentReturnDraft>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('记录投资到账'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: received,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: '实际到账金额',
                    helperText: '预期 ${investment.expectedReturn.format()}',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) {
                    final basic = _moneyError(value, allowNegative: false);
                    if (basic != null) return basic;
                    if (Money.tryParse(value!)!
                            .compareTo(investment.expectedReturn) >
                        0) {
                      return '到账金额不能超过预期回流';
                    }
                    return null;
                  },
                  onChanged: (value) => received = value,
                ),
                const SizedBox(height: 12),
                _DateField(
                  label: '剩余金额预计日期（部分到账时使用）',
                  date: remainingDate,
                  onChanged: (value) =>
                      setDialogState(() => remainingDate = value),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final amount = Money.tryParse(received)!;
              if (amount != investment.expectedReturn &&
                  !remainingDate.isAfter(investment.expectedReturnDate)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('剩余金额日期必须晚于原回流日期。')),
                );
                return;
              }
              Navigator.pop(
                context,
                _InvestmentReturnDraft(
                  received: amount,
                  remainingDate: remainingDate,
                ),
              );
            },
            child: const Text('记录到账'),
          ),
        ],
      ),
    ),
  );
  return result;
}

class _InvestmentDraft {
  const _InvestmentDraft({
    required this.name,
    required this.principal,
    required this.investmentDate,
    required this.expectedReturn,
    required this.returnDate,
  });

  final String name;
  final Money principal;
  final DateTime investmentDate;
  final Money expectedReturn;
  final DateTime returnDate;
}

class _AmountDateDraft {
  const _AmountDateDraft({required this.amount, required this.date});

  final Money amount;
  final DateTime date;
}

class _InvestmentReturnDraft {
  const _InvestmentReturnDraft({
    required this.received,
    required this.remainingDate,
  });

  final Money received;
  final DateTime remainingDate;
}

Future<_IncomeDraft?> _showIncomeDialog(
  BuildContext context,
  DateTime today,
) async {
  final formKey = GlobalKey<FormState>();
  var name = '';
  var amount = '';
  var startDate = today;
  var frequency = RecurrenceFrequency.monthly;
  final result = await showDialog<_IncomeDraft>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('添加周期收入'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '收入名称'),
                  validator: _requiredText,
                  onChanged: (value) => name = value,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  decoration: const InputDecoration(labelText: '预计净到账金额'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) => _moneyError(
                    value,
                    allowNegative: false,
                    requirePositive: true,
                  ),
                  onChanged: (value) => amount = value,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<RecurrenceFrequency>(
                  initialValue: frequency,
                  decoration: const InputDecoration(labelText: '频率'),
                  items: [
                    for (final value in RecurrenceFrequency.values)
                      DropdownMenuItem(
                        value: value,
                        child: Text(_frequencyText(value)),
                      ),
                  ],
                  onChanged: (value) => frequency = value!,
                ),
                const SizedBox(height: 12),
                _DateField(
                  label: '首次到账日期',
                  date: startDate,
                  onChanged: (value) => setDialogState(() => startDate = value),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(
                context,
                _IncomeDraft(
                  name: name.trim(),
                  amount: Money.tryParse(amount)!,
                  startDate: startDate,
                  frequency: frequency,
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  return result;
}

Future<_CreditCardDraft?> _showCreditCardDialog(
  BuildContext context,
  DateTime today,
) async {
  final formKey = GlobalKey<FormState>();
  var name = '';
  var expectedBill = '';
  var statementDay = '${today.day}';
  var paymentDay = '5';
  var statementDate = today;
  final result = await showDialog<_CreditCardDraft>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('安排信用卡账单'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    autofocus: true,
                    decoration: const InputDecoration(labelText: '信用卡名称'),
                    validator: _requiredText,
                    onChanged: (value) => name = value,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    decoration: const InputDecoration(labelText: '预估账单金额'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) =>
                        _moneyError(value, allowNegative: false),
                    onChanged: (value) => expectedBill = value,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: statementDay,
                          decoration: const InputDecoration(labelText: '账单日'),
                          keyboardType: TextInputType.number,
                          validator: _dayError,
                          onChanged: (value) => statementDay = value,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          initialValue: paymentDay,
                          decoration: const InputDecoration(labelText: '还款日'),
                          keyboardType: TextInputType.number,
                          validator: _dayError,
                          onChanged: (value) => paymentDay = value,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _DateField(
                    label: '本期账单日期',
                    date: statementDate,
                    onChanged: (value) =>
                        setDialogState(() => statementDate = value),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(
                context,
                _CreditCardDraft(
                  name: name.trim(),
                  expectedBill: Money.tryParse(expectedBill)!,
                  statementDay: int.parse(statementDay),
                  paymentDay: int.parse(paymentDay),
                  statementDate: statementDate,
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  return result;
}

class _IncomeDraft {
  const _IncomeDraft({
    required this.name,
    required this.amount,
    required this.startDate,
    required this.frequency,
  });

  final String name;
  final Money amount;
  final DateTime startDate;
  final RecurrenceFrequency frequency;
}

class _CreditCardDraft {
  const _CreditCardDraft({
    required this.name,
    required this.expectedBill,
    required this.statementDay,
    required this.paymentDay,
    required this.statementDate,
  });

  final String name;
  final Money expectedBill;
  final int statementDay;
  final int paymentDay;
  final DateTime statementDate;
}

String? _requiredText(String? value) =>
    value == null || value.trim().isEmpty ? '此项不能为空' : null;

String? _moneyError(
  String? value, {
  required bool allowNegative,
  bool requirePositive = false,
}) {
  final amount = Money.tryParse(value ?? '');
  if (amount == null) return '请输入最多两位小数的金额';
  if (!allowNegative && amount.minorUnits < 0) return '金额不能为负数';
  if (requirePositive && amount.minorUnits <= 0) return '金额必须大于零';
  return null;
}

String? _dayError(String? value) {
  final day = int.tryParse(value ?? '');
  return day == null || day < 1 || day > 31 ? '请输入 1–31' : null;
}

void _runAction(BuildContext context, VoidCallback action) {
  try {
    action();
  } catch (error) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('操作失败：$error')));
  }
}

String _newId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}';

String _decimalText(Money amount) {
  final absolute = amount.minorUnits.abs();
  final value =
      '${absolute ~/ 100}.${(absolute % 100).toString().padLeft(2, '0')}';
  return amount.minorUnits < 0 ? '-$value' : value;
}

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _statusText(CashFlowStatus status) => switch (status) {
  CashFlowStatus.estimated => '预估',
  CashFlowStatus.confirmed => '已确认',
  CashFlowStatus.settled => '已结算',
};

String _frequencyText(RecurrenceFrequency frequency) => switch (frequency) {
  RecurrenceFrequency.once => '一次',
  RecurrenceFrequency.monthly => '每月',
  RecurrenceFrequency.yearly => '每年',
};

String _actionText(String action) => switch (action) {
  'manual_created' => '手动创建',
  'confirmed' => '确认金额',
  'settled' => '记录结算',
  'credit_card_estimated' => '信用卡预估',
  'credit_card_confirmed' => '信用卡账单确认',
  'credit_card_settled' => '信用卡还款',
  'investment_created' => '创建投资',
  'investment_return_updated' => '更新投资回流',
  'investment_return_recorded' => '记录投资到账',
  'balance_adjusted' => '余额校准',
  'rule_generated' => '周期规则生成',
  _ => action,
};
