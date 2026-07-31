# Conditional Access Device Compliance Rollout Implementation Plan

## Executive Summary
This implementation plan describes a phased rollout of Microsoft Entra Conditional Access (CA) using the grant control **Require device to be marked as compliant**. The objective is to ensure that only devices meeting defined security and management standards can access targeted Microsoft 365 and enterprise applications. The rollout assumes managed Windows devices are enrolled in Microsoft Intune and are either Microsoft Entra joined, hybrid Microsoft Entra joined, or otherwise able to report compliance state into Entra ID.

The recommended approach is to establish clean compliance baselines first, pilot the policy with a limited group, expand in production rings, and only then enforce Conditional Access. The plan includes risk controls, break-glass protections, operational monitoring, and success metrics so the organization can reduce lockout risk while steadily improving device security posture.

## 1. Goal and Scope

### 1.1 Goal
Implement Microsoft Entra Conditional Access policies that allow access only from devices that are:
- enrolled in Microsoft Intune,
- evaluated against required compliance policies, and
- marked as **Compliant** in Microsoft Entra ID / Intune.

### 1.2 What “Require device to be marked as compliant” means
Under Conditional Access, the grant control **Require device to be marked as compliant** means:
- a user must sign in from a device whose current compliance state is reported as compliant,
- the compliance decision is based on Intune device compliance evaluation,
- a non-compliant, inactive, unknown, or unmanaged device is denied access to in-scope cloud apps unless another allowed path or exclusion applies.

This is not just a device registration check. The device must both exist as a managed identity in Entra ID and pass the applicable Intune compliance policies.

### 1.3 Scope
This plan covers:
- Windows device compliance rollout using Intune + Entra Conditional Access,
- pilot and staged production enforcement,
- operational monitoring and remediation processes,
- references to both built-in and custom compliance policies authored in parallel.

### 1.4 Assumptions
The plan assumes:
- target devices are already enrolled in Microsoft Intune,
- devices are Microsoft Entra joined or hybrid Microsoft Entra joined,
- users authenticate to Microsoft Entra ID-backed apps such as Microsoft 365 or other enterprise SaaS apps,
- compliance evaluation can be reported consistently to Entra ID,
- emergency access accounts will be excluded from CA enforcement.

### 1.5 Out of Scope
Unless separately approved, this document does not define:
- mobile-platform-specific rollout details for iOS/iPadOS or Android,
- full device enrollment project workstreams,
- app protection policy design,
- non-Entra identity providers,
- remediation scripts or packaging details for endpoint agents.

## 2. Prerequisites

### 2.1 Licensing
At minimum, confirm the following licenses are available for all in-scope users/devices:

| Requirement | Purpose | Notes |
|---|---|---|
| Microsoft Entra ID P1 | Conditional Access | Required for CA targeting and enforcement |
| Microsoft Intune | Device compliance + device management | Required to evaluate and publish compliance state |
| Windows licensing as applicable | OS support and security features | Confirm supported editions for BitLocker and Secure Boot |
| Any required security tool licensing | Custom compliance dependencies | Needed for SentinelOne deployment/telemetry if in scope |

### 2.2 Technical Preconditions
Validate these conditions before pilot:
- Devices are successfully enrolled in Intune.
- Devices appear in both Intune and Entra ID with stable device identities.
- Primary users are assigned correctly where required.
- Time sync, OS supportability, and connectivity to Intune service endpoints are healthy.
- Existing access policies are inventoried to avoid policy conflicts.

### 2.3 Required Groups
Create and validate the following groups before rollout:

| Group | Purpose | Recommended Type |
|---|---|---|
| CA-DeviceCompliance-Pilot | Early validation with selected users/devices | Entra security group |
| CA-DeviceCompliance-Ring1 | First production ring | Entra security group |
| CA-DeviceCompliance-Ring2 | Second production ring | Entra security group |
| CA-DeviceCompliance-Ring3 | Broad production ring | Entra security group |
| CA-DeviceCompliance-Exclusions | Temporary operational exclusions | Entra security group |
| CA-BreakGlass-Accounts | Emergency access accounts excluded from CA | Entra security group with strict ownership |

### 2.4 Administrative Readiness
Confirm:
- named owners for Entra CA, Intune compliance, endpoint engineering, IAM, helpdesk, and communications,
- documented change window and approval path,
- helpdesk runbook for common remediation failures,
- sign-in log monitoring access for responders.

## 3. Compliance Policy Inputs
Two compliance policy workstreams are expected to feed this rollout:

1. `CAP\01-Compliance-Policy-BitLocker-SecureBoot.md`
   - Built-in device compliance policy requiring BitLocker and Secure Boot.
2. `CAP\02-Custom-Compliance-SentinelOne\`
   - Custom compliance policy verifying SentinelOne is installed and active.

These artifacts should be treated as detailed control definitions that support the overall CA enforcement plan in this document.

## 4. Phased Rollout Plan

### Phase 0 – Discovery and Inventory
**Objective:** Understand current posture before creating enforcement risk.

#### Activities
- Inventory enrolled device count from Intune.
- Segment by OS/version/build, ownership type, join type, and business unit.
- Measure current compliance state: compliant, non-compliant, not evaluated, inactive.
- Identify devices missing prerequisites such as BitLocker, Secure Boot, or SentinelOne.
- Review sign-in patterns to determine which apps and user populations should be targeted first.
- Identify privileged/admin populations that require stricter change control.

#### Deliverables
- Baseline device inventory report.
- Compliance gap analysis.
- Initial pilot candidate list.
- Exception candidates list (shared kiosks, lab devices, specialized systems if applicable).

#### Example discovery outputs

| Metric | Example Output |
|---|---|
| Total enrolled devices | Count by platform and join type |
| Compliant percentage | Current baseline by business unit |
| Top failure reasons | BitLocker off, Secure Boot off, agent missing, stale check-in |
| Users at risk | Number of active users on non-compliant devices |

### Phase 1 – Create Compliance Policies in Audit / Report-Only Mode
**Objective:** Define the compliance requirements and observe impact before enforcement.

#### Activities
- Create and assign the built-in compliance policy described in `CAP\01-Compliance-Policy-BitLocker-SecureBoot.md`.
- Create and validate the custom compliance policy described in `CAP\02-Custom-Compliance-SentinelOne\`.
- Assign policies initially to pilot devices/users or a representative sample.
- Tune compliance evaluation schedules and grace periods where appropriate.
- Create dashboards or reports for policy evaluation results.
- If Conditional Access policy objects are created at this stage, keep them in **Report-only** mode.

#### Key validation questions
- Are devices evaluating reliably and within expected time windows?
- Do hardware limitations or BIOS settings create false failures?
- Does SentinelOne detection produce consistent compliant/non-compliant outcomes?
- Are stale or duplicate device records distorting results?

#### Exit criteria
- Compliance policies evaluate successfully for pilot population.
- Failure reasons are understood and documented.
- No major false-positive pattern remains unresolved.

### Phase 2 – Pilot Group Rollout with Monitoring
**Objective:** Validate end-user impact with a controlled population.

#### Scope
Target `CA-DeviceCompliance-Pilot` with:
- a representative cross-section of business users,
- a small number of IT/helpdesk users,
- known hardware variations,
- low-risk apps first where practical.

#### Activities
- Enable CA in **Report-only** first for the pilot scope.
- Review Entra sign-in logs for would-be blocks.
- Remediate non-compliant pilot devices before moving to enforcement.
- Communicate pilot expectations, support path, and self-remediation steps.
- After a stable observation period, switch pilot CA policy from Report-only to On for pilot users/apps.

#### Monitoring focus
- Sign-in failures due to non-compliance.
- Time to remediate per failed user/device.
- Repeat offenders and root causes.
- Service desk ticket volume.

#### Exit criteria
- Pilot compliance rate reaches agreed threshold (for example, >=95%).
- Break/fix runbook proven with real incidents.
- No critical business workflow blocked without workaround.

### Phase 3 – Staged Production Rollout (Rings)
**Objective:** Expand enforcement safely using progressive rings.

#### Recommended ring model

| Ring | Population | Suggested Size | Goal |
|---|---|---:|---|
| Ring 1 | IT / technically prepared users | 5-10% | Validate at scale with strong support coverage |
| Ring 2 | Early adopter business units | 15-25% | Prove business-process compatibility |
| Ring 3 | Remaining standard users | 60-80% | Broad rollout |
| Ring 4 (optional) | High-risk or special cases after remediation | Variable | Close long-tail gaps |

#### Activities
- Move one ring at a time after reviewing prior ring metrics.
- Keep an active exclusion group for temporary short-term exceptions only.
- Use change windows and clear go/no-go checkpoints between rings.
- Review app-specific impacts, especially on legacy auth, shared devices, and privileged workflows.
- Escalate unresolved patterns to endpoint engineering or security engineering before proceeding.

#### Ring readiness criteria
- Prior ring stable for at least 5 business days.
- No unresolved Sev A / Sev B business impact.
- Sign-in block trend understood and declining.
- Helpdesk capacity remains within expected volume.

### Phase 4 – Enforce via Conditional Access
**Objective:** Turn policy into a security control that blocks access from non-compliant devices.

#### Conditional Access design guidance
Recommended CA design elements:
- **Users:** include targeted user groups/rings.
- **Exclude:** `CA-BreakGlass-Accounts` and tightly governed operational exclusions.
- **Cloud apps:** start with Microsoft 365 and business-critical apps in scope; expand deliberately.
- **Conditions:** consider supported platforms and client apps; avoid unnecessary complexity in first release.
- **Grant:** **Require device to be marked as compliant**.
- **Session controls:** optional, only if separately justified.

#### Enforcement steps
1. Confirm compliance policy health.
2. Confirm break-glass accounts are tested and excluded.
3. Turn CA policy from Report-only to On for approved ring.
4. Monitor Entra sign-in logs and Intune compliance reports daily during rollout.
5. Document issues, exceptions, and remediations.

#### Log sources to monitor
- Entra sign-in logs.
- Conditional Access insights/reporting workbook.
- Intune device compliance reports.
- Helpdesk incident queue.
- Endpoint security telemetry where available.

### Phase 5 – Steady-State Operations
**Objective:** Sustain compliance and manage drift.

#### Ongoing activities
- Daily/weekly review of compliance drift and newly non-compliant devices.
- Monthly review of exclusion group membership.
- Quarterly review of compliance policy thresholds and security standards.
- Ongoing monitoring for stale devices and duplicate records.
- Measure remediation SLA and repeat failure patterns.
- Update user communication and helpdesk content as the process matures.

#### Exception process
Define a formal exception workflow:
- business justification,
- named owner,
- risk approval,
- time-bound expiration,
- compensating controls,
- periodic review and automatic removal where possible.

## 5. Risk and Mitigation

| Risk | Impact | Mitigation |
|---|---|---|
| Misconfigured CA policy causes broad lockout | High | Use Report-only first, pilot first, stage by rings, validate exclusions |
| Break-glass accounts not excluded or untested | High | Maintain at least two emergency accounts, exclude them, test sign-in regularly |
| Devices fail compliance unexpectedly | Medium/High | Baseline discovery, remediation guidance, helpdesk runbooks, ring pauses |
| False non-compliance due to stale device state | Medium | Validate sync cadence, retire stale records, confirm check-in health |
| Helpdesk overload at enforcement | Medium | Pre-brief service desk, prepare KB articles, increase staffing during cutover |
| Custom compliance dependency fails (SentinelOne state) | Medium | Validate detection logic early, test on diverse hardware, define fallback/support path |
| Executive or privileged admin lockout | High | Separate pilot handling, dedicated communications, confirmed emergency access path |
| Exception sprawl weakens control | Medium | Time-box exceptions, require approvals, review monthly |

### Break-Glass Requirements
- Maintain at least two cloud-only emergency access accounts.
- Store credentials securely per organizational standard.
- Exclude them from all device-compliance CA policies.
- Test them on a scheduled basis and log results.
- Prevent everyday use; monitor all sign-ins.

### Communication Plan
Communications should occur at least at these points:
- **Pre-pilot:** explain objective, expected prompts, remediation steps, support contacts.
- **Pre-ring rollout:** notify impacted groups with dates and self-check instructions.
- **Day of enforcement:** reminder plus known-issues/support channels.
- **Post-rollout:** summarize outcomes and ongoing expectations.

### Helpdesk Readiness
Prepare helpdesk with:
- KB for “device not compliant” troubleshooting,
- escalation tree for Intune, Entra, endpoint security, and hardware issues,
- known commands/portals for device sync and compliance refresh,
- process for temporary exclusion approvals.

### Rollback Plan
If user/business impact exceeds tolerance:
1. Move CA policy back to **Report-only** or disable affected production ring policy.
2. Preserve logging for impacted sign-ins.
3. Use temporary exclusion group only for narrowly approved cases.
4. Triage root cause (policy logic, telemetry failure, assignment scope, stale records).
5. Re-enter pilot/stabilization before re-enforcement.

Rollback should be documented per ring, not improvised during an outage.

## 6. Operational Model

### Roles and Ownership

| Role | Responsibility |
|---|---|
| IAM / Entra Admin | Conditional Access design, deployment, sign-in monitoring |
| Intune Admin | Compliance policy creation, assignment, reporting |
| Endpoint Engineering | Device configuration remediation, BitLocker/Secure Boot enablement |
| Security Engineering | Control validation, SentinelOne compliance dependency oversight |
| Helpdesk / Support | User triage, ticket handling, escalation |
| Communications / Change Management | End-user notifications and stakeholder updates |
| Service Owner / Approver | Go/no-go decision per phase/ring |

### Review Cadence
- Daily during pilot and first enforcement week.
- Twice weekly during staged rollout.
- Monthly after stabilization.
- Quarterly control review with security and endpoint owners.

## 7. Success Metrics and KPIs

| KPI | Definition | Target / Trend |
|---|---|---|
| Device compliance rate | % of in-scope devices marked compliant | Trend upward to agreed target (e.g., >95%) |
| CA block rate | %/count of sign-ins blocked for non-compliance | Initial spike acceptable, then trending down |
| Mean time to remediate (MTTR) | Average time from block to restored compliant access | Trending down over rollout |
| Pilot incident rate | Tickets/incidents per 100 pilot users | Stable and manageable before next ring |
| Exception volume | Active temporary exclusions | Low, time-bound, and declining |
| Stale device record count | Devices inactive or duplicative in management systems | Trending down |
| Policy evaluation reliability | % devices receiving timely compliance state | Near-complete and stable |

### Recommended reporting views
- Daily compliance dashboard by ring.
- Daily CA failures by app, group, and failure reason.
- Weekly remediation aging report.
- Monthly exception register review.

## 8. Timeline Estimate

| Week | Focus | Expected Outputs |
|---|---|---|
| Week 1 | Discovery and stakeholder alignment | Inventory baseline, scope confirmation, owner mapping, group design |
| Week 2 | Compliance policy build and validation | Draft/initial policies, assignment tests, reporting views |
| Week 3 | Report-only observation | Gap analysis, false-positive cleanup, support content |
| Week 4 | Pilot enforcement | Pilot metrics, remediation runbook validation, go/no-go for production |
| Week 5 | Ring 1 rollout | First production enforcement, daily monitoring |
| Week 6 | Ring 2 rollout | Expanded enforcement, trend review, exceptions cleanup |
| Week 7 | Ring 3 rollout | Broad production coverage |
| Week 8 | Stabilization and steady-state handoff | KPI baseline, review cadence, backlog of residual fixes |

This timeline can compress or expand depending on current compliance posture, number of device exceptions, and operational readiness.

## 9. Recommended Implementation Checklist

| Item | Status | Notes |
|---|---|---|
| Confirm licensing for all in-scope users | Pending | Entra ID P1 + Intune minimum |
| Create pilot/ring/exclusion/break-glass groups | Pending | Verify ownership and membership rules |
| Complete discovery inventory | Pending | Establish baseline metrics |
| Finalize built-in compliance policy | Pending | See `CAP\01-Compliance-Policy-BitLocker-SecureBoot.md` |
| Finalize custom compliance policy | Pending | See `CAP\02-Custom-Compliance-SentinelOne\` |
| Validate report-only CA behavior | Pending | Review sign-in logs |
| Train helpdesk and publish KB | Pending | Before pilot enforcement |
| Test break-glass accounts | Pending | Before every enforcement milestone |
| Execute ringed rollout | Pending | Pause between rings for review |
| Establish steady-state reviews | Pending | Monthly and quarterly governance |

## 10. Final Recommendation
Proceed with a **compliance-first, enforcement-second** rollout. Do not enable broad Conditional Access enforcement until the built-in BitLocker/Secure Boot compliance policy and the SentinelOne custom compliance policy are both producing reliable signals and pilot remediation is proven. Success depends less on the CA toggle itself and more on clean inventory, accurate device state, disciplined exclusions, tested break-glass access, and tight monitoring during each rollout ring.
