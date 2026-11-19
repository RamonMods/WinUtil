#===========================================================================
# Testes - Configuração do servidor OpenSSH
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

    function Get-WindowsCapability {
        param($Name, [switch]$Online)
        [pscustomobject]@{ State = "Installed" }
    }
    function Add-WindowsCapability {
        param($Name, [switch]$Online)
    }
    function Get-NetFirewallRule {
        [CmdletBinding()]
        param($Name)
        if ($script:firewallRuleMissing) {
            Write-Error -Message "No matching firewall rule was found." -Category ObjectNotFound
            return
        }
        [pscustomobject]@{ Enabled = $true }
    }
    function New-NetFirewallRule {
        param($Name, $DisplayName, $Enabled, $Direction, $Protocol, $Action, $LocalPort)
    }
    function Set-NetFirewallRule {
        param($Name, $Enabled)
    }
    function Set-Service {
        param($Name, $StartupType)
    }
    function Start-Service {
        param($Name)
    }
    function Restart-Service {
        param($Name, [switch]$Force)
    }

    . (Join-Path $script:repoRoot "functions\private\Invoke-WinUtilSSHServer.ps1")

    $script:defaultAdministratorsBlock = "Match Group administrators`n       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys`n"
    $script:overriddenAdministratorsBlock = "# Match Group administrators`n#        AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys`n"

    function script:New-SshdConfig {
        param([string]$AdministratorsBlock)

        $content = "# Default sshd_config`nPort 22`n`n$AdministratorsBlock"
        Set-Content -Path $script:sshdConfigPath -Value $content -NoNewline
        return $content
    }

    function script:Set-ProfileKeyFile {
        param([string[]]$Keys)

        New-Item -Path (Split-Path $script:profileKeysPath) -ItemType Directory -Force | Out-Null
        Set-Content -Path $script:profileKeysPath -Value $Keys
    }

    function script:Get-ExplicitKeyFileAccess {
        $acl = Get-Acl -Path $script:authorizedKeysPath
        @($acl.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier])) |
            ForEach-Object { $_.IdentityReference.Value }
    }

    function script:Get-AuthorizedKeyFileContent {
        # O arquivo de chaves acaba legível apenas por Administrators e SYSTEM, então uma
        # execução sem elevação precisa conceder a si mesma acesso de leitura por meio da
        # propriedade do arquivo antes de poder verificar o conteúdo.
        $currentUserSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        icacls $script:authorizedKeysPath /grant "*${currentUserSid}:(R)" | Out-Null

        @(Get-Content -Path $script:authorizedKeysPath)
    }
}

Describe "Invoke-WinUtilSSHServer" {
    BeforeEach {
        $script:firewallRuleMissing = $false
        $script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "winutil-ssh-$([guid]::NewGuid())"
        $script:programData = Join-Path $script:testRoot "ProgramData"
        $script:userProfile = Join-Path $script:testRoot "Users\tester"
        New-Item -Path (Join-Path $script:programData "ssh") -ItemType Directory -Force | Out-Null
        New-Item -Path $script:userProfile -ItemType Directory -Force | Out-Null

        $script:sshdConfigPath = Join-Path $script:programData "ssh\sshd_config"
        $script:authorizedKeysPath = Join-Path $script:programData "ssh\administrators_authorized_keys"
        $script:profileKeysPath = Join-Path $script:userProfile ".ssh\authorized_keys"

        $script:savedProgramData = $env:ProgramData
        $script:savedUserProfile = $env:USERPROFILE
        $env:ProgramData = $script:programData
        $env:USERPROFILE = $script:userProfile

        Mock Write-Host { }
        Mock Restart-Service { }
    }

    AfterEach {
        $env:ProgramData = $script:savedProgramData
        $env:USERPROFILE = $script:savedUserProfile
        Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "não altera o bloco de administradores em um sshd_config padrão" {
        $original = New-SshdConfig -AdministratorsBlock $script:defaultAdministratorsBlock

        Invoke-WinUtilSSHServer

        Get-Content -Path $script:sshdConfigPath -Raw | Should -BeExactly $original
        Should -Invoke -CommandName Restart-Service -Times 0 -Exactly
    }

    It "cria a regra de firewall silenciosamente quando ela não existe" {
        New-SshdConfig -AdministratorsBlock $script:defaultAdministratorsBlock | Out-Null
        $script:firewallRuleMissing = $true
        Mock New-NetFirewallRule { }

        $output = @(Invoke-WinUtilSSHServer 2>&1)

        @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) | Should -BeNullOrEmpty
        Should -Invoke New-NetFirewallRule -Times 1 -Exactly
    }

    It "habilita uma regra de firewall desabilitada existente em vez de recriá-la" {
        New-SshdConfig -AdministratorsBlock $script:defaultAdministratorsBlock | Out-Null
        Mock Get-NetFirewallRule { [pscustomobject]@{ Enabled = 2 } }
        Mock Set-NetFirewallRule { }
        Mock New-NetFirewallRule { }

        Invoke-WinUtilSSHServer

        Should -Invoke Set-NetFirewallRule -Times 1 -Exactly -ParameterFilter {
            $Name -eq "sshd" -and $Enabled -eq $true
        }
        Should -Invoke New-NetFirewallRule -Times 0 -Exactly
    }

    It "não altera uma regra de firewall habilitada existente" {
        New-SshdConfig -AdministratorsBlock $script:defaultAdministratorsBlock | Out-Null
        Mock Get-NetFirewallRule { [pscustomobject]@{ Enabled = 1 } }
        Mock Set-NetFirewallRule { }
        Mock New-NetFirewallRule { }

        Invoke-WinUtilSSHServer

        Should -Invoke Set-NetFirewallRule -Times 0 -Exactly
        Should -Invoke New-NetFirewallRule -Times 0 -Exactly
    }

    It "não altera um sshd_config sem bloco de administradores" {
        $original = New-SshdConfig -AdministratorsBlock ""
        Set-ProfileKeyFile -Keys @("ssh-ed25519 AAAAnotanadminkey laptop")

        Invoke-WinUtilSSHServer

        Get-Content -Path $script:sshdConfigPath -Raw | Should -BeExactly $original
        Get-AuthorizedKeyFileContent | Should -Not -Contain "ssh-ed25519 AAAAnotanadminkey laptop"
        Should -Invoke -CommandName Restart-Service -Times 0 -Exactly
    }

    It "cria administrators_authorized_keys limitado a Administrators e SYSTEM" {
        New-SshdConfig -AdministratorsBlock $script:defaultAdministratorsBlock | Out-Null

        Invoke-WinUtilSSHServer

        Test-Path -Path $script:authorizedKeysPath | Should -BeTrue
        (Get-Acl -Path $script:authorizedKeysPath).AreAccessRulesProtected | Should -BeTrue

        $sids = Get-ExplicitKeyFileAccess
        $sids | Should -HaveCount 2
        $sids | Should -Contain "S-1-5-32-544"
        $sids | Should -Contain "S-1-5-18"
    }

    It "restaura o bloco de administradores quando uma execução anterior o comentou" {
        New-SshdConfig -AdministratorsBlock $script:overriddenAdministratorsBlock | Out-Null

        Invoke-WinUtilSSHServer

        $config = Get-Content -Path $script:sshdConfigPath -Raw
        $config | Should -Match '(?m)^Match Group administrators$'
        $config | Should -Match '(?m)^\s+AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys$'
        Should -Invoke -CommandName Restart-Service -Times 1 -Exactly
    }

    It "move as chaves do perfil para administrators_authorized_keys enquanto restaura o bloco" {
        New-SshdConfig -AdministratorsBlock $script:overriddenAdministratorsBlock | Out-Null
        Set-ProfileKeyFile -Keys @("# my laptop", "", "ssh-ed25519 AAAAkeyone laptop", "ssh-ed25519 AAAAkeytwo desktop")

        Invoke-WinUtilSSHServer

        $keys = Get-AuthorizedKeyFileContent
        $keys | Should -Contain "ssh-ed25519 AAAAkeyone laptop"
        $keys | Should -Contain "ssh-ed25519 AAAAkeytwo desktop"
        $keys | Should -Not -Contain "# my laptop"
    }

    It "não copia as chaves do perfil quando sshd_config já está no padrão" {
        New-SshdConfig -AdministratorsBlock $script:defaultAdministratorsBlock | Out-Null
        Set-ProfileKeyFile -Keys @("ssh-ed25519 AAAAnotanadminkey laptop")

        Invoke-WinUtilSSHServer

        Get-AuthorizedKeyFileContent | Should -Not -Contain "ssh-ed25519 AAAAnotanadminkey laptop"
    }

    It "mantém as chaves que já estão em administrators_authorized_keys" {
        New-SshdConfig -AdministratorsBlock $script:overriddenAdministratorsBlock | Out-Null
        Set-Content -Path $script:authorizedKeysPath -Value "ssh-ed25519 AAAAexisting server"
        Set-ProfileKeyFile -Keys @("ssh-ed25519 AAAAexisting server", "ssh-ed25519 AAAAnew laptop")

        Invoke-WinUtilSSHServer

        $keys = @(Get-AuthorizedKeyFileContent | Where-Object { $_.Trim() })
        $keys | Should -HaveCount 2
        $keys | Should -Contain "ssh-ed25519 AAAAexisting server"
        $keys | Should -Contain "ssh-ed25519 AAAAnew laptop"
    }
}
