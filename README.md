# Windows IT Administration Toolkit

This repository contains a set of PowerShell utilities designed for hardware auditing and system administration. These scripts were built to solve common issue when running automation across a network, specifically handling the limitations of network shares (UNC paths) and administrative permission prompts.


### Core

Most scripts fail when run directly from a server share because the Windows Command Prompt does not natively support UNC paths. These tools use a "wrapper" method: a small batch file maps a temporary drive letter, handles the administrative elevation, and then launches the PowerShell logic. This ensures the tools work regardless of whether they are run from a local USB drive or a deep network directory.


### Included Tools

**Asset Information Collector**
Located in the root as get_asset_info.bat. This script gathers essential hardware data including serial numbers, processor specs, and RAM. It features custom filtering logic for network adapters to ensure you get the physical MAC addresses rather than virtual VPN or software-defined adapters. 

* **Feedback:** Results are displayed in the console for immediate verification and appended to a log file in the parent directory.

**Staff and Student Offboarding**
Located as invoke_offboarding.bat. This tool automates the process of disabling Active Directory accounts. It is designed to be modular, making it easy to update the underlying logic without breaking the user-facing launcher.


### Technical Implementation

* **UNC Support:** Uses the pushd command to automatically map and unmap temporary drive letters during execution.
* **Elevation:** Utilizes Start-Process -Verb RunAs to ensure scripts have the necessary permissions to read hardware IDs and modify directory objects.
* **Compatibility:** The codebase is maintained with cross-platform development in mind, ensuring the repository remains clean when accessed from Windows, macOS, or ChromeOS environments.


### Usage

To use these tools, copy the entire folder structure to your preferred location. Run the .bat files found in the root directory. Do not move the files inside the sources folder, as the launchers rely on that specific directory structure to find the PowerShell logic.
