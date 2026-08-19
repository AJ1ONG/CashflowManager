import 'dart:io';

import 'package:flutter/material.dart';

import 'application/cashflow_service.dart';
import 'data/database/app_database.dart';
import 'data/repositories/cashflow_repository.dart';
import 'presentation/cashflow_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final baseDirectory =
      Platform.environment['XDG_DATA_HOME'] ??
      '${Platform.environment['HOME'] ?? Directory.current.path}/.local/share';
  final directory = Directory('$baseDirectory/cashflow_manager')
    ..createSync(recursive: true);
  final database = AppDatabase.open('${directory.path}/cashflow.sqlite');
  runApp(
    CashflowApp(
      service: CashflowService(CashflowRepository(database)),
      onDispose: database.close,
    ),
  );
}
