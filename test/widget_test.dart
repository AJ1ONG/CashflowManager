import 'package:cashflow_manager/application/cashflow_service.dart';
import 'package:cashflow_manager/data/database/app_database.dart';
import 'package:cashflow_manager/data/repositories/cashflow_repository.dart';
import 'package:cashflow_manager/domain/models.dart';
import 'package:cashflow_manager/presentation/cashflow_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late CashflowService service;

  setUp(() {
    database = AppDatabase.inMemory();
    final repository = CashflowRepository(database);
    service = CashflowService(repository);
    repository.saveAccount(
      id: 'cash',
      name: 'Cash',
      balance: const Money(5000000),
    );
    service.createEvent(
      CashFlowEvent(
        id: 'salary',
        name: '九月工资',
        effectiveDate: DateTime.utc(2026, 9, 15),
        expectedAmount: const Money(2500000),
      ),
    );
  });

  tearDown(() => database.close());

  testWidgets('desktop navigation renders dashboard and confirms an event', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      CashflowApp(service: service, now: DateTime.utc(2026, 8, 19)),
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('当前现金'), findsOneWidget);
    expect(find.text('可投入资金'), findsOneWidget);

    await tester.tap(find.text('时间线'));
    await tester.pumpAndSettle();
    expect(find.text('九月工资'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('confirm-salary')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('money-input')),
      '24800.00',
    );
    await tester.tap(find.byKey(const ValueKey('save-money')));
    await tester.pumpAndSettle();

    expect(find.text('已确认'), findsOneWidget);
    expect(service.events.single.confirmedAmount, const Money(2480000));
  });

  testWidgets('narrow window uses bottom navigation without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      CashflowApp(service: service, now: DateTime.utc(2026, 8, 19)),
    );

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
