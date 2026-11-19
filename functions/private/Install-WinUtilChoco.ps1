function Install-WinUtilChoco {
    <#
    .SYNOPSIS
        Instala o Chocolatey se ele ainda não estiver presente
    #>

    if (Get-Command -Name choco -ErrorAction SilentlyContinue) {
        return
    }

    Write-WinUtilLog -Component "Package" -Message "O Chocolatey não está instalado; instalando agora."
    Step-WinUtilJob -Status "Instalando o Chocolatey" -State "Indeterminate"

    # O Windows PowerShell 5.1 pode negociar um protocolo que o site recusa, por isso o
    # bootstrap oficial define o protocolo explicitamente pelo mesmo motivo
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    $installScript = Invoke-WebRequest -Uri https://community.chocolatey.org/install.ps1 -UseBasicParsing -TimeoutSec 60
    Invoke-Command -ScriptBlock ([scriptblock]::Create($installScript.Content))

    # O instalador estende o PATH para novos processos, e este processo não é novo. Anexado em vez de
    # substituído: sobrescrever descarta o que este processo adicionou antes na sessão, e uma
    # etapa posterior que procurasse aquela ferramenta não a encontraria mais.
    $existing = $env:PATH -split ';' | Where-Object { $_ }
    $persisted = @(
        [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        [System.Environment]::GetEnvironmentVariable("Path", "User")
    ) -join ';' -split ';' | Where-Object { $_ }

    $missing = $persisted | Where-Object { $existing -notcontains $_ }
    if ($missing) {
        $env:PATH = (@($existing) + @($missing)) -join ';'
    }

    if (-not (Get-Command -Name choco -ErrorAction SilentlyContinue)) {
        throw "O Chocolatey foi instalado, mas o choco ainda não está no PATH."
    }

    Write-WinUtilLog -Component "Package" -Message "Chocolatey instalado."
}
