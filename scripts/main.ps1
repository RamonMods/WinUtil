Write-Host @"
    CCCCCCCCCCCCCTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT
 CCC::::::::::::CT:::::::::::::::::::::TT:::::::::::::::::::::T
CC:::::::::::::::CT:::::::::::::::::::::TT:::::::::::::::::::::T
C:::::CCCCCCCC::::CT:::::TT:::::::TT:::::TT:::::TT:::::::TT:::::T
C:::::C       CCCCCCTTTTTT  T:::::T  TTTTTTTTTTTT  T:::::T  TTTTTT
C:::::C                     T:::::T                T:::::T
C:::::C                     T:::::T                T:::::T
C:::::C                     T:::::T                T:::::T
C:::::C                     T:::::T                T:::::T
C:::::C                     T:::::T                T:::::T
C:::::C                     T:::::T                T:::::T
C:::::C       CCCCCC        T:::::T                T:::::T
C:::::CCCCCCCC::::C      TT:::::::TT            TT:::::::TT
CC:::::::::::::::C       T:::::::::T            T:::::::::T
CCC::::::::::::C         T:::::::::T            T:::::::::T
  CCCCCCCCCCCCC          TTTTTTTTTTT            TTTTTTTTTTT

====Ramon=====
=====Caixa de Ferramentas do Windows=====
"@

Write-WinUtilLog -Message "WinUtil $($sync.version) on PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)), $([Environment]::OSVersion.VersionString), process $PID."

# Carrega os arquivos de configuração

$sync.configs.applicationsHashtable = @{}
$sync.configs.applications.PSObject.Properties | ForEach-Object {
    $sync.configs.applicationsHashtable[$_.Name] = $_.Value
}

$sync.configs.appxHashtable = @{}
$sync.configs.appx.PSObject.Properties | ForEach-Object {
    $sync.configs.appxHashtable[$_.Name] = $_.Value
}
$sync.preferences.theme = "Auto"
$sync.preferences.packagemanager = "Winget"

function Remove-WinUtilTempScript {
    <#
    .SYNOPSIS
        Remove o script temporário baixado pelo windev.ps1.

    .DESCRIPTION
        Exclui o script atual apenas quando ele é um arquivo winutil-*.ps1 no
        diretório temporário do sistema. Isso preserva as inicializações normais
        do WinUtil, tanto por arquivo quanto em memória.
    #>

    $scriptPath = $PSCommandPath
    $tempPath = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')

    if (
        $scriptPath -and
        [IO.Path]::GetDirectoryName($scriptPath) -eq $tempPath -and
        [IO.Path]::GetFileName($scriptPath) -like 'winutil-*.ps1'
    ) {
        Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
    }
}

#===========================================================================
# Execuções headless nunca criam janela
#===========================================================================

if ($Preset -or $Config) {
    $headlessCode = 1
    try {
        Initialize-WinUtilRunspacePool | Out-Null

        if ($Preset) {
            if (-not $sync.configs.preset.$Preset) {
                throw "Não existe uma predefinição chamada '$Preset'. Disponíveis: $(($sync.configs.preset.PSObject.Properties.Name) -join ', ')"
            }
            Write-WinUtilLog -Component "AutoRun" -Message "Aplicando a predefinição '$Preset'."
            # SkipUnknown para que uma entrada aposentada de uma predefinição seja nomeada e ignorada em vez de
            # encerrar uma execução headless que não tem ninguém para ler o erro
            $skipped = @(Update-WinUtilSelections -flatJson $sync.configs.preset.$Preset -SkipUnknown)
            if ($skipped.Count -gt 0) {
                Write-WinUtilLog -Level "WARN" -Component "AutoRun" -Message "A predefinição '$Preset' cita $($skipped.Count) entrada(s) que esta versão não possui: $($skipped -join ', ')"
            }
        }

        # Os dois podem ser informados: a predefinição define uma base e a configuração acrescenta a ela
        if ($Config) {
            Write-WinUtilLog -Component "AutoRun" -Message "Importando as seleções de '$Config'."
            Invoke-WPFImpex -type "import" -Config $Config -Merge:([bool]$Preset) -ThrowOnError
        }

        $summary = Invoke-WinUtilAutoRun
        $headlessCode = Write-WinUtilAutoRunSummary -Summary $summary
    } catch {
        Write-WinUtilErrorRecord -ErrorRecord $_ -Component "AutoRun" -Context "Execução headless"
        Write-Host "O WinUtil não conseguiu concluir a execução headless: $($_.Exception.Message)" -ForegroundColor Red
        $headlessCode = 1
    } finally {
        Close-WinUtilRunspacePool
        [System.GC]::Collect()
        Remove-WinUtilTempScript
        Close-WinUtilLog
    }

    # Um processo filho elevado e isolado e uma execução explícita por arquivo são donos do próprio
    # processo. A invocação documentada em memória roda dentro do terminal de quem chamou e deve retornar sem fechá-lo.
    if ($env:WINUTIL_HEADLESS_CHILD -eq "1" -or $script:WinUtilIsFileProcess) {
        exit $headlessCode
    }
    $global:LASTEXITCODE = $headlessCode
    return $headlessCode
}

#===========================================================================
# Inicia a interface em sua própria thread e faz o gerenciamento a partir daqui
#===========================================================================
#
# A thread principal fica fora do caminho da janela. Ela cria o runspace STA dedicado onde a
# interface vive, espera essa janela fechar e relata qualquer falha da thread de interface.
# O trabalho iniciado pela interface vai para o pool de workers via
# Start-WinUtilJob, então nem a janela nem esta thread ficam bloqueadas por ele.

$sync.UIRunspace = [runspacefactory]::CreateRunspace($Host, (New-WinUtilSessionState))
$sync.UIRunspace.ApartmentState = "STA"
$sync.UIRunspace.ThreadOptions = "ReuseThread"
$sync.UIRunspace.Open()

$uiShell = [powershell]::Create()
$uiShell.Runspace = $sync.UIRunspace
[void]$uiShell.AddScript({ Start-WinUtilUserInterface })

Write-WinUtilLog -Component "UI" -Message "Iniciando a thread da interface."
$uiHandle = $uiShell.BeginInvoke()

# Esta thread não tem nada a fazer além de esperar, então ela paga o custo da renderização da sobreposição
# em vez de deixar isso para a thread que está construindo a janela
Start-WinUtilAssetRendering | Out-Null

# Registra a saída do Write-Host, os avisos e os erros da thread de UI enquanto a janela estiver aberta
while (-not $uiHandle.AsyncWaitHandle.WaitOne(250)) {
    Receive-WinUtilStreamOutput -PowerShell $uiShell -Component "UI"
}

$uiFailed = $false
try {
    $uiShell.EndInvoke($uiHandle) | Out-Null
} catch {
    $uiFailed = $true
    Write-WinUtilErrorRecord -ErrorRecord $_ -Component "UI" -Context "A thread da interface parou"
}

Receive-WinUtilStreamOutput -PowerShell $uiShell -Component "UI"

$uiShell.Dispose()
$sync.UIRunspace.Dispose()
$sync.Remove("UIRunspace")

# A janela pode ter sido fechada sobre um job que o usuário escolheu deixar terminar. Ele ainda está no
# pool de workers, então o pool não pode ser fechado antes de ele terminar.
Wait-WinUtilRemainingWork

Close-WinUtilRunspacePool
[System.GC]::Collect()

Remove-WinUtilTempScript
Write-Host "Até logo!" -ForegroundColor Cyan
Close-WinUtilLog

if ($uiFailed) {
    $global:LASTEXITCODE = 1
    if ($script:WinUtilIsFileProcess) { exit 1 }
    return 1
}
