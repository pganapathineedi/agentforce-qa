# Setup Scripts

Apex scripts to seed the configurable rules and demo data, and to verify the engine.
Custom Metadata records and demo records are created via Apex (rather than CLI deploy)
because Custom Metadata record deployment is unreliable in some org configurations.

## How to run

Each script runs in **Developer Console → Debug → Open Execute Anonymous Window**.
Tick **Open Log**, paste the script, click **Execute**, then filter the log to **Debug Only**.

Run them in order:

| # | Script | What it does |
|---|--------|--------------|
| 1 | `apex/01_create_qa_rules.apex` | Creates the 7 QFR Labour Cost & Hours QA rules (completeness, reconciliation, plausibility) as Custom Metadata records |
| 2 | `apex/02_create_demo_forms.apex` | Creates two demo forms — a valid one (expects **Pass**) and a flawed one (expects **Fail**) — and runs the engine on both |
| 3 | `apex/03_verify_setup.apex` | Lists the active QA rules and re-runs the engine on the latest forms |

## Prerequisites

Before running these, deploy the metadata and assign the permission set:

```bash
sf project deploy start --source-dir force-app --target-org myorg
sf org assign permset --name QFR_Admin --target-org myorg
```

The permission set assignment is required — without it, Apex cannot see the
custom fields or the Form record type.

## Expected result

- **Valid form** → `VERDICT: Pass`, no findings, plausibility metrics in range
- **Flawed form** → `VERDICT: Fail`, with a missing-bed-days completeness finding,
  an RN-rate reconciliation mismatch, and an RN-rate plausibility flag
  (\$32/hr vs the ~\$38 award floor, down 19% on prior quarter)
