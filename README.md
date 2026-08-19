# Personal Cashflow Manager

A local-first Flutter application for forecasting future cash and liquidity.

The source of truth is [`docs/PROJECT_CONTEXT.md`](docs/PROJECT_CONTEXT.md).
New-device setup is documented in
[`docs/DEVELOPMENT_TOOLCHAIN.md`](docs/DEVELOPMENT_TOOLCHAIN.md).

## Development

```sh
flutter pub get
flutter test
flutter analyze
```

The domain layer is pure Dart and does not depend on Flutter, SQLite, or
platform APIs.

## Linux non-UI verification

Run all automated domain, application, and persistence tests:

```sh
flutter test
```

Run a real SQLite workflow without starting the Flutter UI:

```sh
dart run bin/non_ui_demo.dart
```

Pass a path to keep the generated database for inspection:

```sh
dart run bin/non_ui_demo.dart /tmp/cashflow-demo.sqlite
```

## Linux desktop UI

```sh
flutter run -d linux
```

The desktop app stores its SQLite database at
`$XDG_DATA_HOME/cashflow_manager/cashflow.sqlite`, or under
`$HOME/.local/share/cashflow_manager/` when `XDG_DATA_HOME` is not set.
