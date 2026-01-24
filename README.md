# Azure File Share Cleanup using Access Keys
![PSScriptAnalyzer](https://github.com/Handover2AI/AzureFileshareCleanup_AccessKey/actions/workflows/ci-workflow-psscriptanalyzer.yml/badge.svg)

## 📖 Overview
This repository contains a PowerShell runbook script for **scheduled maintenance of Azure File Shares**.</br>
It is designed to run inside an **Azure Automation Account** using its **system-assigned managed identity**.</br>
<Mark> The script uses storage account **access keys** to retrieve and delete files.</Mark>
  > Alternatively, use [AzureFileshareCleanup_REST API](https://github.com/Handover2AI/AzureFileshareCleanup_REST-API) script that utilizes an OAuth bearer token for REST API calls instead of using storage account access keys

### Features
- Connects to Azure using managed identity
- Retrieves metadata (LastModified, size) for all files in a file share
- Exports metadata to a CSV file stored in an `Export` folder within the share
- Deletes files older than a configurable retention period

---

## ⚙️ Prerequisites
- **Azure Automation Account** with **PowerShell 7.2 runtime**
- **Az.Storage module** version 6.1.0 or higher imported into the Automation Account
- **System-assigned managed identity** enabled for the Automation Account
- Managed identity assigned the following roles on the storage account:
  - `Storage Account Key Operator Service Role` (to read storage account keys)
  - `Storage File Data SMB Share Contributor` (to list, upload, and delete files)

---

## 🔧 Configuration
The script defines the following parameters:

| Parameter          | Description                                                                 | Example Value             |
|--------------------|-----------------------------------------------------------------------------|---------------------------|
| `resourceGroupName`| Resource group containing the storage account                               | `rg-sam-aks-uks-storage`  |
| `storageAccName`   | Name of the storage account                                                 | `stsamaks8dsc`            |
| `fileShareName`    | Name of the file share                                                      | `fslogix`                 |
| `exportFolderName` | Folder in the file share where the CSV file will be saved                   | `Export`                  |
| `csvFileName`      | Name of the CSV file                                                        | `FileMetadata.csv`        |
| `retentionDays`    | Number of days; files older than this will be deleted                       | `7`                       |

---

## ▶️ Usage
1. Import the script into your Automation Account as a **PowerShell runbook**.
2. Configure the runbook to use **PowerShell 7.2 runtime**.
3. Ensure the Automation Account’s managed identity has the required roles.
4. Ensure `Allow storage account key access` is enabled in storage account configuration.
5. Set up a **schedule** to run the runbook daily (or at your desired frequency).
6. The runbook will:
   - Export file metadata to `Export/FileMetadata.csv`
   - Delete files older than `$retentionDays`

---

## 📂 Outputs
- **CSV file**: `Export/FileMetadata.csv` inside the file share, containing:
  - FilePath
  - Name
  - LastModified
  - LengthBytes
- **Runbook logs**: show which files were deleted and any warnings/errors.

---

## 🛡️ Notes
- Adjust `retentionDays` to control cleanup policy.
- Always test the runbook in a non‑production file share before applying to production.
- Deletion is permanent (assuming **soft delete** is not enabled) — ensure retention policy aligns with business requirements.
- Consider exporting a deletion log to CSV for audit purposes.

---

## 🤝 Contributing
Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on how to contribute.  
We expect all contributors to follow our [Code of Conduct](CODE_OF_CONDUCT.md).

---

## ✍️ Author
Created and maintained by **Handover2AI-byExistence**.   
If you find this useful, feel free to star ⭐ the repo or open issues for improvements.

---
