# SentinelOne Custom Compliance for Windows in Microsoft Intune

## Overview

This folder contains a **Windows custom compliance** example for Microsoft Intune that verifies:

1. **SentinelOne is installed**
2. **A SentinelOne agent service is running**

Intune custom compliance for Windows uses **two artifacts together**:

- A **device-side detection script** that runs on the endpoint and writes a JSON object to **stdout**
- A **custom compliance rules file** that tells Intune how to evaluate the JSON values returned by the script

For this package:

- `DetectSentinelOne-Windows.ps1` returns JSON such as:

```json
{"SentinelOneInstalled":true,"SentinelOneServiceRunning":true}
```

- `SentinelOneComplianceRules.json` tells Intune that both values must equal `true`

---

## Files in this folder

| File | Purpose |
|---|---|
| `README.md` | Explains how the custom compliance package works and how to deploy it in Intune |
| `SentinelOneComplianceRules.json` | Intune custom compliance rules file |
| `DetectSentinelOne-Windows.ps1` | Windows detection script that checks install state and service status |

---

## How Intune custom compliance works

### 1. Detection script

The detection script runs locally on the Windows device and must output a **single JSON object** to standard output.  
Each JSON property name must match a `SettingName` in the rules file.

Example:

```json
{
  "SentinelOneInstalled": true,
  "SentinelOneServiceRunning": true
}
```

### 2. Rules file

The rules file contains a top-level `Rules` array. Each rule defines:

- `SettingName`
- `Operator`
- `DataType`
- `Operand`
- `MoreInfoUrl`
- `RemediationStrings`

Intune compares the script output to these rules and marks the device compliant or noncompliant accordingly.

---

## What this specific policy checks

### `SentinelOneInstalled`

Evaluates whether SentinelOne appears to be installed by checking one or more of the following:

- Known Windows services such as `SentinelAgent` or `SentinelServiceHelper`
- Registry locations commonly associated with SentinelOne, such as:
  - `HKLM:\SOFTWARE\Sentinel Labs\Sentinel Agent`
  - `HKLM:\SOFTWARE\WOW6432Node\Sentinel Labs\Sentinel Agent`
- Installed application entries in Windows uninstall registry paths that contain SentinelOne/Sentinel Agent naming

### `SentinelOneServiceRunning`

Evaluates whether a SentinelOne-related agent service is currently in the **Running** state.

> Important: exact service names, display names, and registry paths can vary by SentinelOne version, packaging method, or MSP deployment model. Validate the detection logic against your actual SentinelOne deployment before broad rollout.

---

## Deployment steps in Intune

### Step 1: Upload the detection script

In Intune admin center:

**Devices** > **Compliance** > **Scripts**

Upload:

- `DetectSentinelOne-Windows.ps1`

After upload, assign the script to a pilot device group and confirm devices report script results successfully.

### Step 2: Create the custom compliance policy

In Intune admin center:

**Devices** > **Compliance** > **Policies** > **Create policy** > **Windows 10 and later** > **Custom compliance**

When prompted:

- Select the previously uploaded detection script
- Upload `SentinelOneComplianceRules.json`

### Step 3: Configure actions for noncompliance

Recommended approach:

- Mark device noncompliant immediately, or
- Use a short pilot grace period if you need time to validate detection accuracy

### Step 4: Assign to a pilot group first

Assign first to a limited Windows pilot group, then broaden once:

- The script output is validated on real devices
- Service names/registry paths are confirmed
- User-facing remediation messages are acceptable

---

## Operational notes

- The script should emit **only JSON** to stdout. Extra output can break compliance evaluation.
- If SentinelOne uses different service names in your environment, update the script and rules package before production rollout.
- This custom compliance policy only evaluates device state. To enforce access impact, pair it with Conditional Access using **Require device to be marked as compliant** where appropriate.

---

## Expected output example

Compliant device:

```json
{"SentinelOneInstalled":true,"SentinelOneServiceRunning":true}
```

Noncompliant example:

```json
{"SentinelOneInstalled":true,"SentinelOneServiceRunning":false}
```

---

## Recommended validation before production

Test on:

- A device with a healthy SentinelOne agent
- A device where SentinelOne is uninstalled
- A device where the agent is installed but the service is stopped or unhealthy

Confirm that Intune shows the expected noncompliance message for each rule.

