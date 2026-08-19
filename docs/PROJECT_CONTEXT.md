# PROJECT_CONTEXT.md

## 1. Project Overview

## Project Name

Personal Cashflow Manager

## Product Positioning

This project is a lightweight personal cash flow management application.

The product is **not** a budgeting application and **not** a traditional expense tracking application.

The core purpose is:

> Help users understand future cash availability, determine how much money can currently be deployed into investments, and understand when invested or reserved funds must become liquid again.

The application manages future cash events instead of recording every historical transaction.

---

# 2. Core Product Philosophy

## 2.1 Future-oriented cash management

The primary question the application answers:

- How much cash will I have on every future date?
- What money is truly available for investment?
- What future dates require liquidity?
- If I invest money today, when and how much cash must return?

The main object of analysis is:

```
Current Cash
+
Future Cash Flow Events
=
Future Cash Forecast
```

---

## 2.2 Not a budgeting application

The application does NOT focus on:

- Monthly spending limits
- Category budgets
- Expense classification
- Consumption analysis

The user does not need to record:

- Coffee
- Transportation
- Meals
- Small daily expenses

Small missing cash expenses can be handled through balance adjustment.

---

## 2.3 Not a bookkeeping application

The user mainly inputs:

- Expected salary
- Credit card payment amount
- Fixed payments
- Investment deployment
- Investment return dates
- Other income events

The system focuses on planning and forecasting.

---

# 3. Frozen Requirements

The following requirements are considered fixed for v1.

---

# 3.1 Cash Flow Event Model

Everything that changes cash balance must eventually become a:

```
CashFlowEvent
```

Examples:

- Salary
- Credit card repayment
- Housing fund withdrawal
- Bonus
- Investment return
- Fixed payment

---

## Event lifecycle

Every uncertain event follows:

```
Estimated
    ↓
Confirmed
    ↓
Settled
```

Meaning:

### Estimated

Future prediction.

Example:

```
September salary
Expected:
+25,000
```

---

### Confirmed

Amount is known but cash has not moved yet.

Example:

```
Credit card statement generated:

Payment:
-8,732
```

---

### Settled

Actual cash movement happened.

Example:

```
Salary actually received:

+24,532
```

---

## Amount priority

The effective amount of an event:

```
actual_amount
    >
confirmed_amount
    >
expected_amount
```

The system must preserve all values.

Do not overwrite historical estimates.

---

# 3.2 Credit Card Management

Credit cards have two important dates:

```
Statement Date
Payment Date
```

They represent different concepts.

Example:

```
Statement Date:
2026-08-18

Payment Date:
2026-09-05
```

Before statement:

```
09-05
Credit Card Payment
-8000
Estimated
```

On statement date:

User confirms:

```
Actual bill:
8732.62
```

Update:

```
09-05
Credit Card Payment
-8732.62
Confirmed
```

On payment date:

User confirms actual deduction.

---

# 3.3 Income Management

The system supports multiple income sources.

Examples:

- Salary
- Housing fund withdrawal
- Annual bonus
- Project bonus
- Other recurring income
- One-time income

Each income source supports:

- Expected amount
- Date
- Recurrence
- Optional tax calculation
- Optional insurance deduction

---

# 3.4 Salary Calculation

Salary supports two modes.

## Net Mode

User directly enters expected received amount.

Example:

```
Expected salary received:

25000
```

No tax calculation.

---

## Gross Mode

User enters pre-tax income.

Example:

```
Gross salary:

30000
```

System calculates:

```
Gross Income
    ↓
Social Insurance
    ↓
Housing Fund
    ↓
Tax
    ↓
Expected Net Income
```

The result is still only Estimated.

Actual salary must be confirmed when received.

---

# 3.5 Tax and Social Insurance

Tax calculation is separated from cash flow calculation.

Architecture:

```
Income Engine

    ↓

Tax Engine

    ↓

Net Income

    ↓

CashFlowEvent
```

The CashFlow Engine should not know tax rules.

---

## Tax rules

Tax rules must be:

- Versioned
- Region specific
- Year specific

Example:

```
China Individual Income Tax
2026 Version
```

Historical events must keep the original calculation context.

---

## Social Insurance

Five insurance and housing fund are configured separately.

They require:

- Contribution base
- Employee contribution rate

Important:

```
Salary != Insurance Base
```

The system must not assume insurance base equals salary.

---

# 3.6 Investment Management

Investment is not treated as normal spending.

Investment has:

- Principal
- Investment date
- Expected return amount
- Expected return date

Example:

```
Investment:

Principal:
30000

Date:
2026-08-17

Expected return:
30600

Expected return date:
2026-10-15
```

Generated events:

```
2026-08-17
-30000
Settled


2026-10-15
+30600
Estimated
```

---

## Investment return handling

The system must NOT automatically assume return happened.

When expected return date arrives:

User chooses:

- Fully received
- Partially received
- Delayed
- Updated amount/date

Example:

Expected:

```
30600
```

Actual:

```
20000
```

Result:

```
10/15
+20000
Settled


10/30
+10600
Estimated
```

---

# 3.7 Reminder System

Reminder and CashFlowEvent are separate concepts.

Example:

Credit card:

```
Reminder:
2026-08-18
Confirm statement amount


CashFlowEvent:
2026-09-05
Payment
```

Reminder means:

"User needs to take action."

CashFlowEvent means:

"Cash changes."

---

# 4. Core Engines

---

# 4.1 CashFlow Engine

Input:

```
Current cash balance

+

Future CashFlowEvents
```

Output:

- Future cash timeline
- Daily balance
- Minimum future balance
- Minimum balance date

The engine should be deterministic.

---

# 4.2 Recurrence Engine

Responsible for generating events from rules.

Examples:

```
Monthly salary

↓

Events:

2026-09-15
2026-10-15
2026-11-15
```

v1 supports:

- Once
- Monthly
- Yearly

---

# 4.3 Liquidity Engine

This is the core differentiating feature.

The engine answers:

> How much money can I deploy now, and when must it return?

Outputs:

- Deployable capital
- Liquidity deadlines
- Required return schedule

Example:

```
Investment today:

50000


Required liquidity:

Sep 25:
8000

Oct 05:
15000
```

---

# 5. Technical Architecture

## Technology Stack

Fixed:

```
Frontend:
Flutter

Language:
Dart

Database:
SQLite

Architecture:
Local-first
```

Target platforms:

```
Ubuntu
Android
iOS
```

---

# 5.1 Architecture Rules

The project follows:

```
Presentation
      ↓
Application
      ↓
Domain
      ↓
Data
```

---

## Domain Layer

Domain must NOT depend on:

- Flutter
- SQLite
- Platform APIs

Domain contains:

- CashFlowEngine
- LiquidityEngine
- RecurrenceEngine
- Income calculation
- Tax calculation models

---

# 5.2 Recommended Structure

```
lib/

 app/
    router.dart
    app.dart

 domain/
    models/
    engines/

 application/
    services/
    use_cases/

 data/
    database/
    repositories/

 presentation/
    dashboard/
    timeline/
    investments/
    settings/

 platform/
    notifications/

 test/
```

---

# 6. Database Principles

Use SQLite.

Do not store calculated results as primary data.

Store:

- Accounts
- Rules
- Events
- Investments
- Tax Profiles
- Reminders

Generate:

- Forecast
- Liquidity analysis

dynamically.

---

# 7. Money Representation

Never use floating point numbers for money.

Wrong:

```
double amount = 123.45
```

Correct:

```
integer minor units

12345
=
123.45
```

---

# 8. Dependency Policy

Runtime dependencies must:

- Be free to obtain
- Be open source
- Allow commercial usage
- Allow closed-source paid applications

Preferred licenses:

- MIT
- BSD-2-Clause
- BSD-3-Clause
- Apache-2.0
- ISC
- Public Domain

Avoid runtime dependencies with:

- GPL
- AGPL
- SSPL
- Commercial-only license
- Non-commercial restriction
- Unknown license

Development tools are not restricted by this rule.

Every runtime dependency must be documented.

Maintain:

```
THIRD_PARTY_LICENSES.md
```

---

# 9. Development Rules for Codex

Codex must:

1. Keep the product small and focused.
2. Do not introduce budgeting features.
3. Do not introduce bookkeeping features.
4. Do not add unnecessary dependencies.
5. Do not put business logic inside Flutter widgets.
6. Do not use floating point for currency.
7. Do not automatically settle estimated events.
8. Do not automatically assume investment returns happened.
9. Preserve historical values.
10. Add tests for business logic changes.
11. Prefer simple architecture over premature abstraction.

---

# 10. Current Development Priority

Order:

## Phase 1

Implement domain models:

- Money
- CashFlowEvent
- CashFlowRule
- CreditCard
- Income
- Investment
- Reminder

---

## Phase 2

Implement engines:

- CashFlow Engine
- Recurrence Engine
- Liquidity Engine

---

## Phase 3

Implement SQLite persistence.

---

## Phase 4

Implement Flutter UI:

Main screens:

```
Dashboard

Timeline

Investments

Settings
```

---

## Phase 5

Implement:

- Local notifications
- Tax calculation
- Five insurance calculation
- Platform testing

---

# 11. Product Definition

The final product is:

> A lightweight personal cash flow management application that allows users to record future income, credit card obligations, investments, and other important cash events. The system continuously forecasts future cash availability, calculates deployable capital, and informs users when invested money must become liquid again.

The application should remain a focused cash flow planning tool, not evolve into a general finance management platform.
