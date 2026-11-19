function Invoke-WPFRunspace {

    <#

    .SYNOPSIS
        Cria e invoca um runspace usando o scriptblock e a lista de argumentos informados

    .PARAMETER ScriptBlock
        O scriptblock a invocar no runspace

    .PARAMETER ArgumentList
        Uma lista de argumentos a passar para o runspace

    .PARAMETER ParameterList
        Uma lista de parâmetros nomeados que devem ser fornecidos.
    .EXAMPLE
        Invoke-WPFRunspace `
            -ScriptBlock $sync.ScriptsInstallPrograms `
            -ArgumentList "Installadvancedip,Installbitwarden" `

        Invoke-WPFRunspace`
            -ScriptBlock $sync.ScriptsInstallPrograms `
            -ParameterList @(("PackagesToInstall", @("Installadvancedip,Installbitwarden")),("ChocoPreference", $true))
    #>

    [CmdletBinding()]
    [OutputType([System.IAsyncResult])]
    Param (
        $ScriptBlock,
        $ArgumentList,
        $ParameterList
    )

    $poolLock = Get-WinUtilRunspacePoolLock
    [System.Threading.Monitor]::Enter($poolLock)
    try {
        # O bloqueio de ciclo de vida mantém a verificação final de desligamento, o início da invocação e o registro
        # atômicos em relação ao fechamento do pool. Caso contrário, o desligamento pode perder uma invocação recém-iniciada.
        if ($sync.ShuttingDown) {
            Write-WinUtilLog -Level "WARN" -Component "UI" -Message "Recusado iniciar trabalho em segundo plano; o WinUtil está sendo fechado."
            return $null
        }

        Initialize-WinUtilRunspacePool | Out-Null

        # Cria uma instância do PowerShell
        $powershell = [powershell]::Create()

        # Adiciona o scriptblock e os argumentos ao runspace
        [void]$powershell.AddScript($ScriptBlock)
        [void]$powershell.AddArgument($ArgumentList)

        foreach ($parameter in $ParameterList) {
            # Um único par escrito como @(("Name", $value)) é reduzido a um array de dois elementos e
            # indexá-lo então retorna os dois primeiros caracteres do nome
            if ($parameter -is [string] -or $parameter.Count -ne 2) {
                throw "ParameterList recebe pares de nome e valor. Recebido '$parameter'. Um único par precisa de uma vírgula inicial: -ParameterList (,('Name', `$value))"
            }
            [void]$powershell.AddParameter($parameter[0], $parameter[1])
        }

        $powershell.RunspacePool = $sync.runspace

        # Registra antes de iniciar para que nenhuma exceção após o BeginInvoke faça o chamador liberar seu
        # token de trabalho enquanto o trabalho está realmente em execução. O registro de limpeza é melhor-esforço e conta com
        # um fallback em thread de segundo plano; ele nunca deve esperar sincronamente por um worker no dispatcher do WPF,
        # pois o finalizador do worker pode estar esperando para restaurar o estado da interface.
        try {
            Register-WinUtilActiveShell -PowerShell $powershell
        } catch {
            $powershell.Dispose()
            throw
        }
        $handle = $null
        try {
            $handle = $powershell.BeginInvoke()
        } catch {
            $startError = $_
            $sync.ActiveShells.Remove($powershell)
            $powershell.Dispose()
            throw $startError
        }

        try {
            Register-WinUtilRunspaceCleanup -PowerShell $powershell -Handle $handle
        } catch {
            # O worker continua monitorado e é dono do seu token de trabalho. Trate-o como agendado para que outro
            # trabalho que altere o sistema não possa iniciar ao lado dele; trabalhos posteriores/o desligamento podem recuperar o shell.
            Write-WinUtilLog -Level "WARN" -Component "UI" -Message "Não foi possível registrar a limpeza em segundo plano: $($_.Exception.Message)"
        }

        return $handle
    } finally {
        [System.Threading.Monitor]::Exit($poolLock)
    }
}
