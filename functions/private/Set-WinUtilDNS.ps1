function Set-WinUtilDNS {
    <#

    .SYNOPSIS
        Define o DNS de todas as interfaces que estão no estado "Up". Os valores são obtidos do arquivo DNS.Json

    .PARAMETER DNSProvider
        O provedor de DNS a ser definido no servidor DNS

    .EXAMPLE
        Set-WinUtilDNS -DNSProvider "google"

    #>
    param($DNSProvider)

    if($DNSProvider -eq "Default") {
        Write-WinUtilLog -Component "DNS" -Message "O provedor de DNS é Default; nenhuma alteração de DNS aplicada."
        return $true
    }

    if($DNSProvider -eq "Fastest") {
        Write-WinUtilLog -Component "DNS" -Message "Detectando automaticamente o provedor de DNS mais rápido via teste de latência..."
        $benchmark = Get-WinUtilDNSBenchmark
        $validFastest = $benchmark | Where-Object { $_.LatencyMs -lt 9999 } | Select-Object -First 1
        if ($validFastest) {
            $DNSProvider = $validFastest.Provider
            Write-Host "Provedor de DNS mais rápido selecionado automaticamente: $DNSProvider ($($validFastest.LatencyMs) ms)"
            Write-WinUtilLog -Component "DNS" -Message "Provedor de DNS mais rápido selecionado automaticamente: $DNSProvider ($($validFastest.LatencyMs) ms)"
        } else {
            Write-Warning "Não foi possível medir a latência de DNS para nenhum provedor; mantendo as configurações de DNS atuais do adaptador de rede."
            Write-WinUtilLog -Component "DNS" -Message "Tempo esgotado no teste ou todas as sondagens falharam; abortando a alteração de DNS para preservar as configurações existentes."
            return $false
        }
    }

    try {
        $Adapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
        Write-Host "Garantindo que o DNS seja definido como $DNSProvider nas seguintes interfaces:"
        Write-Host $($Adapters | Out-String)
        Write-WinUtilLog -Component "DNS" -Message "Definindo o provedor de DNS como $DNSProvider para $(@($Adapters).Count) adaptador(es) ativo(s)."

        if($DNSProvider -ne "DHCP") {
            $dns = $sync.configs.dns.$DNSProvider
            if($null -eq $dns) {
                Write-Warning "O provedor de DNS $DNSProvider não foi encontrado na configuração."
                Write-WinUtilLog -Level "ERROR" -Component "DNS" -Message "O provedor de DNS $DNSProvider não foi encontrado na configuração."
                return $false
            }
        }

        $dohSupported = [bool](Get-Command Add-DnsClientDohServerAddress -ErrorAction SilentlyContinue)
        if ($DNSProvider -ne "DHCP" -and $dns.DohOnly -and -not $dohSupported) {
            Write-Warning "O provedor de DNS $DNSProvider exige DNS over HTTPS, que não é suportado neste sistema."
            Write-WinUtilLog -Level "ERROR" -Component "DNS" -Message "O provedor de DNS $DNSProvider exige DNS over HTTPS, que não é suportado neste sistema."
            return $false
        }

        $dnscacheBase = "HKLM:\System\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters"

        Foreach ($Adapter in $Adapters) {
            $interfaceParams = "$dnscacheBase\$($Adapter.InterfaceGuid)"

            if($DNSProvider -eq "DHCP") {
                Write-WinUtilLog -Component "DNS" -Message "Redefinindo o DNS para DHCP no adaptador $($Adapter.Name) (ifIndex: $($Adapter.ifIndex))."
                Set-DnsClientServerAddress -InterfaceIndex $Adapter.ifIndex -ResetServerAddresses
                netsh interface ip set dnsservers name="$($Adapter.Name)" source=dhcp
                netsh interface ipv6 set dnsservers name="$($Adapter.Name)" source=dhcp

                $dohInterfaceSettings = "$interfaceParams\DohInterfaceSettings"
                if (Test-Path $dohInterfaceSettings) {
                    if ($dohSupported) {
                        $dohServerAddresses = @(
                            Get-ChildItem -Path "$dohInterfaceSettings\Doh" -ErrorAction SilentlyContinue
                            Get-ChildItem -Path "$dohInterfaceSettings\Doh6" -ErrorAction SilentlyContinue
                        ) | Select-Object -ExpandProperty PSChildName -Unique

                        foreach ($ip in $dohServerAddresses) {
                            if (Get-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue) {
                                Write-WinUtilLog -Component "DNS" -Message "Removendo o registro DoH de $ip."
                                Remove-DnsClientDohServerAddress -ServerAddress $ip -Confirm:$false -ErrorAction Stop
                            }
                        }
                    }

                    Remove-Item -Path $dohInterfaceSettings -Recurse -Force -ErrorAction SilentlyContinue
                }
            } else {
                $ipv4Addresses = @(@($dns.Primary, $dns.Secondary) | Where-Object { $_ })
                $ipv6Addresses = @(@($dns.Primary6, $dns.Secondary6) | Where-Object { $_ })

                if ($dohSupported -and $dns.DohTemplate) {
                    try {
                        $ips = @($dns.Primary, $dns.Secondary, $dns.Primary6, $dns.Secondary6) | Where-Object { $_ }
                        foreach ($ip in $ips) {
                            $dohTemplate = if ($dns.SecondaryDohTemplate -and @($dns.Secondary, $dns.Secondary6) -contains $ip) {
                                $dns.SecondaryDohTemplate
                            } else {
                                $dns.DohTemplate
                            }
                            $existing = Get-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue
                            if ($existing) {
                                Set-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $dohTemplate -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction Stop
                            } else {
                                Write-WinUtilLog -Component "DNS" -Message "Registrando o modelo DoH de $ip."
                                Add-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $dohTemplate -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction Stop
                            }

                            $leaf = if ($ip.Contains(':')) { 'Doh6' } else { 'Doh' }
                            $regPath = "$interfaceParams\DohInterfaceSettings\$leaf\$ip"

                            if (-not (Test-Path $regPath)) {
                                New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null
                            }
                            New-ItemProperty -Path $regPath -Name "DohFlags" -Value 1 -PropertyType QWord -Force -ErrorAction Stop | Out-Null
                        }
                    } catch {
                        if ($dns.DohOnly) {
                            throw
                        }

                        Write-Warning "A configuração de DNS over HTTPS para o provedor $DNSProvider falhou; continuando com DNS simples."
                        Write-WinUtilLog -Level "WARN" -Component "DNS" -Message "A configuração de DNS over HTTPS para o provedor $DNSProvider falhou; continuando com DNS simples: $($psitem.Exception.Message)"
                    }
                }

                Write-WinUtilLog -Component "DNS" -Message "Definindo o DNS IPv4 no adaptador $($Adapter.Name) (ifIndex: $($Adapter.ifIndex)) como $($dns.Primary), $($dns.Secondary)."
                Set-DnsClientServerAddress -InterfaceIndex $Adapter.ifIndex -ServerAddresses $ipv4Addresses -ErrorAction Stop
                Write-WinUtilLog -Component "DNS" -Message "Definindo o DNS IPv6 no adaptador $($Adapter.Name) (ifIndex: $($Adapter.ifIndex)) como $($dns.Primary6), $($dns.Secondary6)."
                Set-DnsClientServerAddress -InterfaceIndex $Adapter.ifIndex -ServerAddresses $ipv6Addresses -ErrorAction Stop
            }
        }
        if ($DNSProvider -ne "DHCP" -and $dohSupported -and $dns.DohTemplate) {
            Clear-DnsClientCache
        }
        Write-WinUtilLog -Component "DNS" -Message "Alteração do provedor de DNS concluída: $DNSProvider"
        return $true
    } catch {
        Write-Warning "O provedor de DNS $DNSProvider não foi aplicado porque ocorreu um erro."
        Write-Warning $psitem.Exception.Message
        Write-WinUtilLog -Level "ERROR" -Component "DNS" -Message "O provedor de DNS $DNSProvider não foi concluído: $($psitem.Exception.Message)"
        return $false
    }
}
