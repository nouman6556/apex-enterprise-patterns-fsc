# Apex Enterprise Patterns for Financial Services

A self-contained implementation of **Apex Enterprise Patterns** (selector, domain, service, unit of work) over a **Financial Services Cloud-shaped** data model. It includes a **Queueable chain** and a **Batch/Scheduled** job for high-volume KYC-style verification. Dependency injection lets the service tests run with **no SOQL and no DML**.

> Portfolio / reference project built with synthetic records. No fflib dependency, so every pattern is visible in about 300 lines of Apex.

## Layers

```
            ┌──────────────────────────────┐
 Trigger ──▶│ Domain: FinancialAccounts    │  defaults, validation, aggregates (in-memory)
            └──────────────────────────────┘
 Queueable / Batch / Flow
            │
            ▼
 ┌─────────────────────┐   Application.get(IKycService)
 │ Service: KycService │──────────────────────────────────┐
 └──────────┬──────────┘                                  │
            │ reads                          writes       │
            ▼                                   ▼         │
 ┌───────────────────────────┐    ┌─────────────────────────────┐
 │ Selectors (USER_MODE)     │    │ UnitOfWork                  │
 │  AccountsSelector         │    │  ordered inserts → updates  │
 │  FinancialAccountsSelector│    │  → deletes, parent-Id wiring│
 └───────────────────────────┘    │  savepoint + rollback       │
                                  └─────────────────────────────┘
```

| Piece | What it shows |
|---|---|
| `Application` | Composition root. Maps interfaces to implementations; `setMock()` swaps in fakes for tests. |
| `IAccountsSelector`, `IFinancialAccountsSelector` + implementations | All SOQL in one place, `WITH USER_MODE`. |
| `FinancialAccounts` (domain) | Default status and balance, account-number and negative-balance rules, grouping and totals. Used by both the trigger and the service. |
| `KycService` | Rules: missing address → **Failed** (and financial accounts **Frozen**); high-risk jurisdiction or no financial accounts → **Manual Review**; aggregate balance ≥ 1M → **Medium** risk. One `KYC_Verification__c` per account, committed atomically. |
| `UnitOfWork` | Parent-to-child commit order, resolves Ids for not-yet-inserted parents, all-or-nothing through a savepoint, user-mode DML by default. |
| `KycVerificationQueueable` | Processes N accounts in chunks (default 200) and chains the remainder. |
| `KycReverificationBatch` | Batch plus Schedulable. Nightly re-verification of accounts with active financial accounts. |
| `FscException` hierarchy | `UnitOfWorkException`, `KycVerificationException`. |
| `KYC_Operations` permission set | Object, field and class access. User-mode code needs it. |

## Tests

- **`KycServiceTest`**: in-memory fake selectors and a fake unit of work. It asserts `Limits.getQueries()` and `Limits.getDmlStatements()` don't change, so the business rules are proven without touching the database.
- **`IntegrationTest`**: runs as a least-privilege user with `KYC_Operations` and covers the trigger and domain rules, unit-of-work parent wiring and rollback, the queueable chunking, the batch and the scheduler.

## Run it

```bash
sf org create scratch -f config/project-scratch-def.json -a fsc -d
sf project deploy start -d force-app
sf org assign permset -n KYC_Operations
sf apex run test -l RunLocalTests -w 10 -c

# kick off a run
sf apex run <<< "System.enqueueJob(new KycVerificationQueueable(new List<Id>(new Map<Id, Account>([SELECT Id FROM Account]).keySet())));"
```

## Mapping to Financial Services Cloud

`Financial_Account__c` mirrors `FinServ__FinancialAccount__c`, and `Account` stands in for the household or person account. In an FSC org, point the two selectors at the FinServ objects. The service, domain and tests don't change, which is the point of the selector layer.

## Tech

Apex · Enterprise Patterns (Selector / Domain / Service / Unit of Work) · Dependency Injection · Queueable, Batch & Scheduled Apex · Financial Services Cloud · Salesforce DX · GitHub Actions
