function Invoke-WinUtilSSHServer {
    <#
    .SYNOPSIS
        Habilita o servidor OpenSSH para acessar remotamente seu dispositivo Windows
    #>

    # Instala o recurso de Servidor OpenSSH caso ainda não esteja instalado
    if ((Get-WindowsCapability -Name OpenSSH.Server -Online).State -ne "Installed") {
        Write-Host "Habilitando o Servidor OpenSSH... Isso pode demorar bastante."
        Add-WindowsCapability -Name OpenSSH.Server -Online
    }

    Write-Host "Iniciando os serviços"

    Set-Service -Name sshd -StartupType Automatic
    Start-Service -Name sshd

    Set-Service -Name ssh-agent -StartupType Automatic
    Start-Service -Name ssh-agent

    #Adicionando regra de firewall para a porta 22
    Write-Host "Configurando as regras de firewall"
    $firewallRule = Get-NetFirewallRule -Name 'sshd' -ErrorAction SilentlyContinue
    if ($null -eq $firewallRule) {
        New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
        Write-Host "Regra de firewall para o Servidor OpenSSH criada e habilitada."
    } elseif ([int]$firewallRule.Enabled -eq 2) {
        Set-NetFirewallRule -Name 'sshd' -Enabled True
        Write-Host "Regra de firewall para o Servidor OpenSSH habilitada."
    }

    # Um logon SSH de um membro do grupo de administradores recebe um token completo
    # sem solicitação do UAC, então o sshd lê as chaves de administrador de um arquivo
    # válido para todo o computador, que somente Administradores e SYSTEM podem gravar.
    # O WinUtil sempre é executado elevado, então a conta configurada aqui é sempre administrador.
    $sshProgramDataPath = Join-Path $env:ProgramData "ssh"
    $sshdConfigPath = Join-Path $sshProgramDataPath "sshd_config"
    $authorizedKeysPath = Join-Path $sshProgramDataPath "administrators_authorized_keys"
    $profileKeysPath = Join-Path $env:USERPROFILE ".ssh\authorized_keys"

    if (-not (Test-Path -Path $sshProgramDataPath)) {
        New-Item -Path $sshProgramDataPath -ItemType Directory -Force | Out-Null
    }

    # Versões anteriores do WinUtil comentavam o bloco de administradores no
    # sshd_config. Detecte esse estado antes de restaurá-lo, para que as chaves de
    # administrador já em uso sejam preservadas em vez de parar de funcionar silenciosamente.
    $configContent = if (Test-Path -Path $sshdConfigPath) { [string](Get-Content -Path $sshdConfigPath -Raw) } else { "" }
    $restoredContent = $configContent -replace '(?m)^# (Match Group administrators)$', '$1'
    $restoredContent = $restoredContent -replace '(?m)^# (\s+AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys)$', '$1'
    $configWasOverridden = $restoredContent -ne $configContent

    if (-not (Test-Path -Path $authorizedKeysPath)) {
        Write-Host "Criando o arquivo administrators_authorized_keys..."
        New-Item -Path $authorizedKeysPath -ItemType File -Force | Out-Null
        Write-Host "Arquivo administrators_authorized_keys criado em $authorizedKeysPath."
    }

    if ($configWasOverridden -and (Test-Path -Path $profileKeysPath)) {
        $currentKeys = @(Get-Content -Path $authorizedKeysPath)
        $keysToMove = @(Get-Content -Path $profileKeysPath | Where-Object {
            $_.Trim() -and -not $_.TrimStart().StartsWith("#") -and $currentKeys -notcontains $_
        })

        if ($keysToMove.Count -gt 0) {
            Add-Content -Path $authorizedKeysPath -Value $keysToMove
            Write-Host "Movida(s) $($keysToMove.Count) chave(s) de $profileKeysPath para $authorizedKeysPath."
        }
    }

    # O sshd ignora o arquivo a menos que a herança esteja desativada e o acesso seja limitado a
    # Administradores (S-1-5-32-544) e SYSTEM (S-1-5-18). Os SIDs mantêm isso
    # funcionando em instalações localizadas, onde os nomes dos grupos diferem.
    $acl = Get-Acl -Path $authorizedKeysPath
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) {
        [void]$acl.RemoveAccessRule($rule)
    }
    foreach ($sid in @("S-1-5-32-544", "S-1-5-18")) {
        [void]$acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new(
            [System.Security.Principal.SecurityIdentifier]::new($sid), "FullControl", "Allow"))
    }
    Set-Acl -Path $authorizedKeysPath -AclObject $acl

    if ($configWasOverridden) {
        Set-Content -Path $sshdConfigPath -Value $restoredContent -Force
        Write-Host "Configuração do arquivo de chaves de administrador restaurada no sshd_config."
        Restart-Service -Name sshd -Force
    }

    Write-Host "Servidor OpenSSH habilitado com sucesso."
    Write-Host "O arquivo de configuração está em $sshdConfigPath"
    Write-Host "Adicione suas chaves públicas a este arquivo -> $authorizedKeysPath"
}
