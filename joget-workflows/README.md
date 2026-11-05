---
tags: [wso2, joget-workflows, readme]
---
# Joget workflows on WSO2 Integrator

Durable workflows that Joget apps start and act on through WSO2's own workflow Management API (`/workflow` on port 8234).

| Workflow | Joget app | Source of the flow |
|---|---|---|
| `mufApplication` | mufFinancing | MUF decision tables DT-01, 03, 04, 05, 06, 08, 10, read from Joget at run time |
| `bizOnboardingApproval` | bizOnboarding | package.xpdl "Business Account Opening" |
| `wso2DeskApproval` | wso2Desk | "Platform Request Review" |
| `wso2HrLeaveApproval` | wso2HrLeave | "Leave approval" |
| `wso2LoanApproval` | wso2Loan | "Loan Origination" |
| `wso2OnboardingApproval` | wso2Onboarding | "New Joiner Onboarding" |

wso2AppCentre has no process in its export, so it has no workflow.

- Run locally: `./start-everything-locally.sh`. Test: `python3 scripts/test_app_workflows.py`.
- Joget API Connector spec: `openapi/wso2-workflow-management.joget.oas.json` (rebuild with `scripts/make_joget_openapi_spec.py`).
- Cloud move: `MIGRATION.md`.
- Settings: `Config.example.toml`; the real `Config.toml` is git-ignored.
