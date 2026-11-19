function Get-WinUtilDNSBenchmark {
    <#

    .SYNOPSIS
        Testa provedores DNS neutros medindo a latência da porta 53 via TCP (RTT em ms) para determinar o servidor DNS mais rápido.

    .PARAMETER TimeoutMs
        Tempo máximo de espera em milissegundos para cada teste de conexão. O padrão é 1500 ms.

    .OUTPUTS
        Matriz de PSCustomObjects contendo Provider, PrimaryIP e LatencyMs, ordenada pela menor latência.

    .EXAMPLE
        $results = Get-WinUtilDNSBenchmark
        $fastest = $results[0]

    #>
    [CmdletBinding()]
    param(
        [ValidateRange(1, 9998)]
        [int]$TimeoutMs = 1500
    )

    Write-WinUtilLog -Component "DNS" -Message "Iniciando a verificação de latência de DNS (porta 53 via TCP)..."

    $dnsConfigs = $sync.configs.dns
    if ($null -eq $dnsConfigs) {
        Write-Warning "Configurações de DNS não encontradas em `$sync.configs.dns."
        Write-WinUtilLog -Level "ERROR" -Component "DNS" -Message "Configurações de DNS não encontradas em `$sync.configs.dns."
        return @()
    }

    $results = [System.Collections.Generic.List[PSObject]]::new()

    foreach ($prop in $dnsConfigs.PSObject.Properties) {
        $providerName = $prop.Name
        $primaryIp = $prop.Value.Primary
        if (-not $primaryIp) { continue }

        # Os provedores precisam optar explicitamente, para que novos serviços de filtragem nunca sejam escolhidos automaticamente.
        if ($prop.Value.BenchmarkEligible -ne $true) {
            continue
        }

        $latency = 9999
        $client = $null
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $asyncResult = $client.BeginConnect($primaryIp, 53, $null, $null)
            $success = $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
            $stopwatch.Stop()

            if ($success) {
                $client.EndConnect($asyncResult)
                $latency = [int]$stopwatch.ElapsedMilliseconds
            } else {
                $latency = 9999
            }
        } catch {
            $latency = 9999
        } finally {
            if ($null -ne $client) {
                $client.Dispose()
            }
        }

        $results.Add([PSCustomObject]@{
            Provider  = $providerName
            PrimaryIP = $primaryIp
            LatencyMs = $latency
        })
    }

    $sortedResults = @($results | Sort-Object LatencyMs)
    if ($sortedResults.Count -gt 0 -and $sortedResults[0].LatencyMs -lt 9999) {
        $fastest = $sortedResults[0]
        Write-WinUtilLog -Component "DNS" -Message "Benchmark de DNS concluído. Provedor neutro mais rápido: $($fastest.Provider) ($($fastest.LatencyMs) ms)"
    } else {
        Write-WinUtilLog -Component "DNS" -Message "Benchmark de DNS concluído. Não foi possível determinar a latência dos provedores."
    }

    return $sortedResults
}
