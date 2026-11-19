Function Get-WinUtilPowerShellVersion {
    param ([string]$Path)
    & $Path -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
}

Function Get-WinUtilPowerShellArchitecture {
    param ([string]$Path)
    & $Path -NoLogo -NoProfile -Command '[System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()'
}

Function Test-WinUtilPowerShellMSIUpgradeAllowed {
    # O WinGet não tem saída estruturada de lista de pins, e os filtros de list não são respeitados por todas as versões.
    # Por precaução, deixe as atualizações com o WinGet sempre que existir algum pin ou a verificação falhar.
    try {
        $pinOutput = @(& winget pin list --accept-source-agreements --disable-interactivity 2>&1)
        if ($LASTEXITCODE -ne 0 -or $pinOutput.Count -eq 0) { return $false }
        $text = $pinOutput -join "`n"
        $text = $text -replace '\x1B\[[0-9;]*[A-Za-z]', ''
        return $text -notmatch '(?m)^\s*-{3,}\s*$'
    } catch {
        return $false
    }
}

Function Update-WinUtilPowerShellMSI {
    $candidates = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.WindowsInstaller -eq 1 -and
            $_.DisplayName -match '^PowerShell\s+7(?:\.\d+){0,3}(?:-(?:x64|x86|arm64))?(?:\s|$)' -and
            $_.DisplayName -notmatch "preview|daily"
        }
    $locations = @()
    foreach ($candidate in $candidates) {
        $location = $candidate.InstallLocation
        if (-not $location) {
            # O MSI oficial registra sua localização aqui, não no registro de desinstalação.
            $registration = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\PowerShellCore\InstalledVersions\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\PowerShellCore\InstalledVersions\*" -ErrorAction SilentlyContinue |
                Where-Object { $_.ProductCode -and $_.ProductCode -eq $candidate.PSChildName } |
                Select-Object -First 1
            $location = $registration.InstallLocation
        }
        if ($location -and (Test-Path -LiteralPath (Join-Path $location "pwsh.exe"))) {
            $location = ([string]$location).TrimEnd([char[]]'\/')
            if ($locations -notcontains $location) { $locations += $location }
        }
    }

    if ($locations.Count -eq 0) {
        return [pscustomobject]@{
            Outcome = "NotInstalled"
            Detail = "O PowerShell não foi instalado via MSI"
        }
    }

    if ($locations.Count -gt 1) {
        $detail = "Várias instalações estáveis do PowerShell via MSI foram detectadas; atualize cada instalação manualmente. Nenhuma atualização direta por MSI foi tentada."
        Write-WinUtilLog -Level "ERROR" -Component "Package" -Message $detail
        return [pscustomobject]@{ Outcome = "Failed"; ExitCode = -1; Detail = $detail }
    }
    $msi = [pscustomobject]@{ InstallLocation = $locations[0] }

    if (-not (Test-WinUtilPowerShellMSIUpgradeAllowed)) {
        Write-WinUtilLog -Component "Package" -Message "Ignorando a atualização direta do PowerShell por MSI: existem pins do WinGet ou o estado deles não pôde ser verificado."
        return [pscustomobject]@{
            Outcome = "Skipped"
            Detail = "Existem pins do WinGet ou o estado deles não pôde ser verificado; atualização por MSI ignorada"
        }
    }

    try {
        $installed = Get-WinUtilPowerShellVersion (Join-Path $msi.InstallLocation "pwsh.exe")
        $release = Invoke-RestMethod "https://api.github.com/repos/PowerShell/PowerShell/releases/latest" -TimeoutSec 30
        $latest = ([string]$release.tag_name).TrimStart("v")

        if ([version]$installed -ge [version]$latest) {
            Write-WinUtilLog -Component "Package" -Message "O PowerShell já está atualizado ($installed)"
            return [pscustomobject]@{
                Outcome = "Skipped"
                Detail = "O PowerShell já está atualizado"
            }
        }

        $arch = ([string](Get-WinUtilPowerShellArchitecture (Join-Path $msi.InstallLocation "pwsh.exe"))).Trim().ToLowerInvariant()
        if ($arch -notin @("x64", "x86", "arm64")) {
            throw "Arquitetura do PowerShell instalado não é suportada: $arch"
        }
        $asset = $release.assets |
            Where-Object { $_.name -match "^PowerShell-.*-win-$arch\.msi$" } |
            Select-Object -First 1

        if (-not $asset) {
            throw "Nenhum MSI do PowerShell encontrado para $arch"
        }

        $msiPath = Join-Path $env:TEMP "PowerShell-$arch-$([guid]::NewGuid()).msi"

        try {
            Invoke-WebRequest $asset.browser_download_url -OutFile $msiPath -UseBasicParsing -TimeoutSec 300

            if ($asset.digest) {
                $hash = (Get-FileHash -LiteralPath $msiPath -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($hash -ne $asset.digest.Replace("sha256:", "").ToLowerInvariant()) {
                    throw "Falha na verificação SHA256 do MSI do PowerShell"
                }
            }

            $signature = Get-AuthenticodeSignature -LiteralPath $msiPath
            if (
                $signature.Status -ne "Valid" -or
                -not $signature.SignerCertificate -or
                $signature.SignerCertificate.Subject -notmatch '(^|,\s*)CN=Microsoft Corporation(,|$)'
            ) {
                throw "Falha na verificação de assinatura do MSI do PowerShell"
            }

            $install = Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /qn /norestart" -Wait -PassThru

            if ($install.ExitCode -notin @(0,3010,1641)) {
                throw "A instalação do MSI do PowerShell falhou com o código de saída $($install.ExitCode)"
            }

            $detail = switch ($install.ExitCode) {
                3010 { "Atualização do MSI do PowerShell concluída; é preciso reiniciar para concluir" }
                1641 { "Atualização do MSI do PowerShell concluída; o instalador iniciou uma reinicialização" }
                default { "Atualização do MSI do PowerShell concluída" }
            }
            Write-WinUtilLog -Component "Package" -Message "$detail (código de saída $($install.ExitCode))"
            if ($install.ExitCode -in @(3010, 1641)) { Write-Host $detail }

            return [pscustomobject]@{
                Outcome = "Succeeded"
                ExitCode = $install.ExitCode
                Detail = $detail
            }
        }
        finally {
            Remove-Item -LiteralPath $msiPath -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-WinUtilLog -Level "ERROR" -Component "Package" -Message "Falha na atualização do MSI do PowerShell: $($_.Exception.Message)"

        return [pscustomobject]@{
            Outcome = "Failed"
            ExitCode = -1
            Detail = "Falha na atualização do MSI do PowerShell: $($_.Exception.Message)"
        }
    }
}

Function Install-WinUtilProgramWinget {
    <#

    .SYNOPSIS
        Instala ou desinstala pacotes com o WinGet e reporta o resultado de cada um

    .DESCRIPTION
        Emite um objeto de resultado por pacote para que o chamador saiba o que realmente
        aconteceu, em vez de presumir que a execução foi bem-sucedida.

        Executa um comando winget por pacote para que uma falha identifique o pacote que falhou,
        em vez do lote inteiro. O progresso avança por pacote: o winget oculta sua própria barra
        de progresso quando a saída é redirecionada, então não há nada a reportar de dentro de
        uma instalação individual.

    #>
    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet("Install", "Uninstall", "Upgrade")]
        [string]$Action,

        [Parameter(Mandatory=$true)]
        [string[]]$Programs
    )

    # APPINSTALLER_CLI_ERROR_ADMIN_CONTEXT_ACTION_PROHIBITED. O WinGet se recusa a agir em um pacote
    # que foi instalado no escopo do usuário enquanto executa elevado, e o WinUtil sempre executa
    # elevado, então todo aplicativo por usuário retorna isso e nada acontece.
    $adminContextProhibited = -1978335107

    # O WinGet reporta "não havia nada a fazer" pelo código de saída, em vez de como sucesso
    $nothingToDo = @{
        -1978335135 = "já instalado"
        -1978335189 = "nenhuma atualização aplicável"
    }

    # O instalador funcionou e quer reiniciar para concluir. O Windows reporta isso com seu próprio
    # código de saída, em vez de zero, e tratá-lo como falha marca instalações funcionais como quebradas.
    $rebootExitCodes = @{
        3010 = "instalado, é preciso reiniciar para concluir"
        1641 = "instalado, o instalador iniciou uma reinicialização"
        -1978334967 = "instalado, é preciso reiniciar para concluir"
        -1978334965 = "instalado, o instalador iniciou uma reinicialização"
    }

    foreach ($program in $Programs) {
        if ([string]::IsNullOrWhiteSpace($program) -or $program -eq "na") {
            continue
        }

        $upgradeAll = $Action -eq "Upgrade" -and $program -eq "all"

        if (($Action -in @("Install", "Upgrade") -and $program -eq "Microsoft.PowerShell") -or $upgradeAll) {
            $result = Update-WinUtilPowerShellMSI

            if ($result.Outcome -ne "NotInstalled") {
                [pscustomobject]@{
                    Package  = "Microsoft.PowerShell"
                    Manager  = "msi"
                    Action   = $Action
                    ExitCode = $result.ExitCode
                    Outcome  = $result.Outcome
                    Detail   = $result.Detail
                }

                # Atualizar Tudo ainda deve atualizar os outros pacotes após reportar o resultado do MSI.
                if (-not $upgradeAll) { continue }
            }
        }

        $source = if ($upgradeAll) { "todas as fontes configuradas" } else { "winget" }

        if (-not $upgradeAll -and $program.StartsWith("msstore:", [System.StringComparison]::OrdinalIgnoreCase)) {
            $source = "msstore"
            $program = $program.Substring("msstore:".Length)
        }

        Write-WinUtilLog -Component "Package" -Message "Pacote winget ($Action): $program (fonte: $source)"

        $outcome = "Failed"
        $detail = "nenhum resultado"
        $exitCode = -1

        $arguments = switch ($Action) {
            "Uninstall" {
                @("uninstall", "--id", $program, "--source", $source, "--silent")
            }
            "Upgrade" {
                if ($upgradeAll) {
                    @("upgrade", "--all", "--accept-package-agreements", "--accept-source-agreements", "--include-unknown", "--silent")
                } else {
                    @("upgrade", "--id", $program, "--accept-package-agreements", "--accept-source-agreements", "--source", $source, "--include-unknown", "--silent")
                }
            }
            default {
                @("install", "--id", $program, "--accept-package-agreements", "--accept-source-agreements", "--source", $source, "--silent")
            }
        }

        $process = Start-Process -FilePath winget -ArgumentList $arguments -NoNewWindow -Wait -PassThru
        $exitCode = $process.ExitCode

        if ($exitCode -eq 0) {
            $outcome = "Succeeded"
            $detail = "código de saída 0"
        } elseif ($rebootExitCodes.ContainsKey($exitCode)) {
            $outcome = "Succeeded"
            $detail = $rebootExitCodes[$exitCode]
        } elseif ($nothingToDo.ContainsKey($exitCode)) {
            $outcome = "Skipped"
            $detail = $nothingToDo[$exitCode]
        } elseif ($exitCode -eq $adminContextProhibited) {
            $outcome = "Skipped"
            $detail = switch ($Action) {
                "Install" { "já instalado para o usuário atual; o WinUtil elevado não pode atualizá-lo" }
                "Upgrade" { "não atualizado; instalado para o usuário atual e o WinUtil elevado não pode modificá-lo" }
                "Uninstall" { "continua instalado para o usuário atual; o WinUtil elevado não pode desinstalá-lo" }
            }
        } else {
            $outcome = "Failed"
            $detail = "O WinGet reportou 0x{0:X8}. Consulte https://learn.microsoft.com/windows/package-manager/winget/returnCodes" -f $exitCode
        }

        $level = if ($outcome -eq "Failed") { "ERROR" } else { "INFO" }

        Write-WinUtilLog -Level $level -Component "Package" -Message "Pacote winget ($Action) $($outcome.ToLowerInvariant()): $program ($detail)"

        [pscustomobject]@{
            Package  = $program
            Manager  = "winget"
            Action   = $Action
            ExitCode = $exitCode
            Outcome  = $outcome
            Detail   = $detail
        }
    }
}
