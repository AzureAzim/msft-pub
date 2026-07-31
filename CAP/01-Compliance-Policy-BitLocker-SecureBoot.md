# Windows 10/11 Device Compliance Policy Recommendation: BitLocker + Secure Boot

## Purpose

Define a Microsoft Intune **built-in device compliance policy** for **Windows 10 and later / Windows 11** that enforces the two primary security controls requested:

1. **REQUIRED: BitLocker drive encryption enabled**
2. **REQUIRED: Secure Boot enabled**

This policy is intended to support Conditional Access decisions, reduce exposure from lost or stolen devices, and ensure devices boot in a trusted state.

## Scope

- **Platform:** Windows 10 and later / Windows 11
- **Policy type:** Intune device compliance policy (`windows10CompliancePolicy`)
- **Recommended target:** Corporate-managed Windows endpoints
- **Rollout approach:** Pilot first, then expand to broader production groups

---

## Required settings vs. optional suggestions

### Required controls

These are the two controls explicitly requested and should be enforced in the compliance policy:

- **Require BitLocker** = **Require**
- **Require Secure Boot to be enabled on the device** = **Require**

### Optional but recommended related controls

These commonly complement BitLocker and Secure Boot, but should be treated as **optional recommendations** unless your security standard requires them:

- **Code Integrity** = **Require**
- **Early launch antimalware driver** = **Require** (if your organization already depends on Microsoft Defender-based boot protections)
- **Minimum OS version** = set to your corporate baseline (for example, a supported Windows 10/11 build)
- **Microsoft Defender Antivirus / real-time protection** requirements if they align with your endpoint protection standard

> Recommendation: keep the compliance policy tightly focused for the first rollout. Enforce BitLocker and Secure Boot first, then layer in optional settings after pilot validation.

---

## Intune admin center configuration

**Path:**  
**Microsoft Intune admin center** > **Devices** > **Compliance** > **Policies** > **Create policy** > **Windows 10 and later**  
(*Some admins also navigate to the same workflow from Endpoint security, depending on portal habits and role layout.*)

### Device Health section

The table below shows the recommended settings for the **Device Health** section. The two requested controls are clearly marked as **REQUIRED**.

| Intune setting name | Recommended value | Required/Optional | Notes |
|---|---:|---|---|
| **Require BitLocker** | **Require** | **REQUIRED** | Device must report BitLocker protection enabled to be compliant. |
| **Require Secure Boot to be enabled on the device** | **Require** | **REQUIRED** | Uses device health attestation to confirm Secure Boot is enabled. |
| Code integrity | Require | Optional recommendation | Strengthens trust in boot/system integrity; recommended where compatible with hardware and driver set. |
| Early launch antimalware driver | Not configured or Require | Optional recommendation | Enable only if it matches your endpoint protection baseline and has been pilot-tested. |

> Exact UI wording can vary slightly by tenant portal version, but the two key settings to select are **Require BitLocker** and **Require Secure Boot to be enabled on the device**.

### Additional optional settings outside Device Health

These are not part of the two required asks, but are common companion settings in Windows compliance programs:

| Section | Setting | Recommended value | Why |
|---|---|---:|---|
| System Security / Microsoft Defender | Antivirus / Defender requirements | Require if aligned with your standard | Helps ensure protected endpoints, but avoid duplicating controls already enforced elsewhere. |
| System Security / Microsoft Defender | Real-time protection | Require if aligned with your standard | Common baseline for managed Windows devices. |
| Device Properties | Minimum OS version | Supported corporate baseline | Prevents outdated Windows builds from remaining compliant. |

---

## Recommended actions for noncompliance

Recommended compliance action schedule:

| Action | When | Recommendation |
|---|---|---|
| **Mark device noncompliant** | **Immediately** | Recommended for production because BitLocker and Secure Boot are foundational controls. |
| Send email to end user | After 1 day | Optional reminder to explain remediation steps before access impact is noticed by the user. |
| Conditional Access access restriction | At next Conditional Access evaluation after device is noncompliant | Recommended via CA policy, not as a compliance-policy action itself. |

### Practical rollout guidance

- **Pilot phase:** If user disruption is a concern, you can temporarily use a short grace period (for example, 3 days) before marking devices noncompliant.
- **Production phase:** Prefer **immediate noncompliance** so devices without BitLocker or Secure Boot quickly lose access to protected resources through Conditional Access.

---

## Assignment guidance

Recommended assignment model:

1. **Pilot group first**
   - Assign to a limited set of IT-managed test devices or a security pilot Entra ID group.
   - Validate reporting accuracy on modern hardware, VM-based test devices, and devices with different OEM/TPM combinations.
2. **Broaden to managed corporate devices**
   - Expand after confirming no false positives and after verifying user support/remediation guidance.
3. **Exclude known exceptions only when justified**
   - Use documented exception handling for devices that genuinely cannot support Secure Boot or BitLocker.
   - Review exceptions regularly and time-bound them where possible.

---

## Microsoft Graph API example

The following JSON body can be used with Microsoft Graph to create a `windows10CompliancePolicy` that enforces **BitLocker** and **Secure Boot**. Optional fields are included as examples and can be adjusted to your standard.

```json
{
  "@odata.type": "#microsoft.graph.windows10CompliancePolicy",
  "displayName": "Windows Compliance - BitLocker and Secure Boot",
  "description": "Requires BitLocker and Secure Boot on Windows 10/11 devices.",
  "bitLockerEnabled": true,
  "secureBootEnabled": true,
  "codeIntegrityEnabled": true,
  "osMinimumVersion": "10.0.19045.0"
}
```

### Notes for Graph / PowerShell use

- Typical create endpoint: `POST https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies`
- Assignments are usually made **after** policy creation with an assignment call.
- Scheduled actions for noncompliance may be configured separately depending on your automation approach and Graph workflow.
- If you want the policy to contain **only** the two requested controls, remove the optional `codeIntegrityEnabled` and `osMinimumVersion` fields.

---

## Interaction with Conditional Access

This compliance policy is most effective when paired with a Conditional Access policy that uses the grant control:

- **Require device to be marked as compliant**

### How it works

1. Intune evaluates the Windows device against the compliance policy.
2. If **BitLocker** or **Secure Boot** is missing, the device becomes **noncompliant** (immediately or after the configured grace period).
3. Conditional Access sees the device is not compliant and can block access to targeted cloud apps.

### Important operational note

- The Intune compliance policy determines **compliant/noncompliant state**.
- The Conditional Access policy enforces the **access consequence**.
- Without a CA policy using **Require device to be marked as compliant**, a noncompliant device is reported as noncompliant but may still be able to access resources that are not otherwise restricted.

---

## Recommended final baseline

If the goal is a minimal, high-value starting point:

- **Require BitLocker** = **Require**
- **Require Secure Boot to be enabled on the device** = **Require**

Then, after pilot validation, consider:

- **Code integrity** = **Require**
- **Minimum OS version** = supported corporate baseline
