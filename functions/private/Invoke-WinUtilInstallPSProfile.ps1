function Get-WinUtilPowerShell7Path {
    $command = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    foreach ($candidate in @(
            "$env:ProgramFiles\PowerShell\7\pwsh.exe",
            "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe")) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    return $null
}

function Invoke-WinUtilInstallPSProfile {
    <#
    .SYNOPSIS
        Instala o perfil PowerShell do Ramon

    .DESCRIPTION
        O perfil é voltado ao PowerShell 7, então o script de configuração dele precisa rodar sob
        pwsh e não no runspace em que esta tarefa está. Ele roda como processo filho com a saída
        capturada, para que o log da tarefa registre o que aconteceu em vez de rolar por um
        terminal que ninguém acompanhou.
    #>

    $pwshPath = Get-WinUtilPowerShell7Path
    if (-not $pwshPath) {
        Step-WinUtilJob -Status "Instalando o PowerShell 7" -State "Indeterminate"
        Write-WinUtilLog -Component "Feature" -Message "PowerShell 7 não encontrado, instalando-o primeiro."

        Install-WinUtilWinget
        Install-WinUtilProgramWinget -Action Install -Programs @("Microsoft.PowerShell") | Out-Null

        # O WinGet atualiza o PATH persistido, não este processo já em execução. Resolva os
        # locais de instalação padrão e o PATH atual antes de concluir que falhou.
        $pwshPath = Get-WinUtilPowerShell7Path
        if (-not $pwshPath) {
            throw "Não foi possível instalar o PowerShell 7, então o perfil não pode ser configurado."
        }
    }

    Step-WinUtilJob -Status "Executando a configuração do perfil" -State "Indeterminate"

    $setupUrl = "https://github.com/RamonMods/powershell-profile/raw/main/setup.ps1"
    # Para no processo filho, para que uma falha de configuração seja uma saída não zero em vez
    # de um erro registrado e um código de saída zero
    $output = & $pwshPath -NoProfile -NonInteractive -Command "`$ErrorActionPreference = 'Stop'; irm '$setupUrl' | iex" 2>&1
    $exitCode = $LASTEXITCODE

    $failures = 0
    foreach ($line in @($output)) {
        if ($line -is [System.Management.Automation.ErrorRecord]) {
            $failures++
            Write-WinUtilErrorRecord -ErrorRecord $line -Component "Feature" -Context "Configuração do perfil do PowerShell"
        } elseif (-not [string]::IsNullOrWhiteSpace($line)) {
            Write-WinUtilLog -Component "Feature" -Message ([string]$line).Trim()
        }
    }

    if ($exitCode -ne 0) {
        throw "O script de configuração do perfil saiu com o código $exitCode."
    }

    if ($failures -gt 0) {
        throw "O script de configuração do perfil reportou $failures erro(s); veja o log."
    }

    Write-WinUtilLog -Component "Feature" -Message "Perfil PowerShell do Ramon instalado. Abra uma nova sessão do PowerShell 7 para usá-lo."
}
