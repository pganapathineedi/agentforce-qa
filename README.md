# Agentforce QA Engine for Government Forms

A configurable, metadata-driven quality-assurance engine for government form submissions, with an **Agentforce** agent layered on top. Built on Salesforce using the Australian Aged Care **Quarterly Financial Report (QFR)** as the reference case — but designed to generalise to *any* government form.

The pitch: help providers submit valid data the first time, and help QA reviewers assess submissions in a fraction of the time — with the architecture extending to any form, not just the QFR.

---

## The idea

QA of government financial forms is manual, slow, and judgement-heavy. A reviewer cross-checks figures across forms and attachments, validates segmentation, and spots outliers by hand. Errors cost funding and compliance. And the rules change every quarter.

This project tackles that with a clean separation of concerns:

- **The engine supplies facts** (deterministic): completeness, reconciliation, and computed plausibility metrics.
- **The judgement is grounded, not hallucinated**: plausibility analysis is composed from the engine's own figures, so it's consistent and auditable — and surfaced through the agent.

A plain field-check is just config. The value here is QA *reasoning* over financial data — reconciliation across line items and plausibility judgement (e.g. an RN wage rate below the award minimum), explained in plain English.

---

## Architecture

```
Account (provider)
  └── Case  = one QFR submission (per provider, per quarter)
       └── Form__c            ← one object, a record type per form
            └── Form_Line_Item__c   ← flexibly-typed line items (the variable data)

Completeness_Rule__mdt   ← configurable rules (completeness · reconciliation · plausibility)
        │                   scoped by object, record type, and line key
        ▼
QAEngine (Apex)          ← reads rules, evaluates a form, rolls up a verdict
        │
        ▼
QACheckAction            ← @InvocableMethod the Agentforce agent calls
        │
        ▼
Agentforce agent         ← runs the assessment, presents verdict + findings + analysis
```

**Why this shape:**
- **One `Form__c` object with record types** — adding a new form is a record type + rules, never new code.
- **Flexibly-typed `Form_Line_Item__c`** — typed value fields (number, currency, text, boolean, date) handle tabular, question, and document-style forms alike.
- **Custom Metadata rules engine** — rules are configuration, not code, and deploy across orgs. BRE-inspired, runs in any org (no Public Sector Solutions licence needed).
- **Plugin escape hatch** — complex rules implement an Apex interface, so the engine never changes.

---

## The three check types

| Check | Nature | Example |
|-------|--------|---------|
| **Completeness** | Deterministic | RN cost, RN hours and occupied bed days must all be present |
| **Reconciliation** | Deterministic | Cost ÷ hours must match the declared implied rate, within tolerance |
| **Plausibility** | Judgement (grounded) | An RN rate of \$32/hr is below the ~\$38 award floor and down 19% on prior quarter — likely misreported on-costs or a data error |

The engine rolls per-check results into a **Pass / Flag / Fail** verdict.

---

## What's in this repo

```
force-app/main/default/
├── objects/
│   ├── Case/fields/                  Case-level QFR fields (quarter, verdict, summary)
│   ├── Form__c/                      the generic form object + Labour Cost & Hours record type
│   ├── Form_Line_Item__c/            the flexibly-typed line item
│   └── Completeness_Rule__mdt/       the configurable rules engine (Custom Metadata Type)
├── classes/
│   ├── CompletenessEngine.cls        generic field-level completeness engine
│   ├── CompletenessCheckAction.cls   invocable wrapper (case completeness)
│   ├── CompletenessRuleProvider.cls  plugin interface for complex rules
│   ├── QAEngine.cls                  form-level QA engine (reconciliation + plausibility)
│   ├── QACheckAction.cls             invocable wrapper the agent calls
│   └── *Test.cls                     test classes
└── permissionsets/
    └── QFR_Admin.permissionset       object/field/record-type access
```

---

## Deploying to a scratch / dev org

```bash
sf org login web --alias myorg
sf project deploy start --source-dir force-app --target-org myorg
sf org assign permset --name QFR_Admin --target-org myorg
```

Custom Metadata rule records (the sample QFR rules) are created via Apex — see the scripts referenced in the project notes.

---

## Status

- ✅ Configurable rules engine (completeness, reconciliation, plausibility)
- ✅ Generic Case → Form → Line Item data model
- ✅ Agentforce agent: runs QA, returns verdict + findings + analysis
- ✅ Proven end-to-end on realistic data (clean form passes; flawed form fails with issues caught and explained)
- ⏳ Provider pre-submission experience, additional forms as configuration, whole-submission roll-up

---

## A note on the design

In this org's Agentforce version, the agent reliably *executes an action and presents its output*, rather than performing free-form reasoning over returned data — consistent with Salesforce's guidance to build deterministic logic into the action rather than topic instructions. So the plausibility analysis is composed deterministically in Apex (from the engine's own figures) and presented by the agent. The result is consistent and auditable — which a compliance tool wants.

---

*Built as a capability demonstration — configurable, agentic QA for regulated government forms, on the Salesforce platform.*
