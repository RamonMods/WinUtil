#===========================================================================
# Testes - DNS
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

    function Get-NetAdapter { }
    function Set-DnsClientServerAddress {
        param(
            $InterfaceIndex,
            $ServerAddresses,
            [switch]$ResetServerAddresses,
            $ErrorAction
        )
    }
    function netsh {
        param(
            [Parameter(ValueFromRemainingArguments = $true)]
            [string[]]$Arguments
        )
    }
    function Write-WinUtilLog {
        param($Message, $Level, $Component)
    }

    function Add-DnsClientDohServerAddress {
        param($ServerAddress, $DohTemplate, $AllowFallbackToUdp, $AutoUpgrade, $ErrorAction)
    }
    function Set-DnsClientDohServerAddress {
        param($ServerAddress, $DohTemplate, $AllowFallbackToUdp, $AutoUpgrade, $ErrorAction)
    }
    function Get-DnsClientDohServerAddress {
        param($ServerAddress, $ErrorAction)
    }
    function Remove-DnsClientDohServerAddress {
        param($ServerAddress, $Confirm, $ErrorAction)
    }
    function Clear-DnsClientCache { }

    . (Join-Path $script:repoRoot "functions\private\Set-WinUtilDNS.ps1")
    . (Join-Path $script:repoRoot "functions\private\Get-WinUtilDNSBenchmark.ps1")
}

Describe "Set-WinUtilDNS" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{
            configs = @{
                dns = @{
                    Cloudflare = [pscustomobject]@{
                        Primary = "1.1.1.1"
                        Secondary = "1.0.0.1"
                        Primary6 = "2606:4700:4700::1111"
                        Secondary6 = "2606:4700:4700::1001"
                        DohTemplate = "https://cloudflare-dns.com/dns-query"
                    }
                    DohOnlyProvider = [pscustomobject]@{
                        Primary = "192.0.2.1"
                        Secondary = "192.0.2.2"
                        Primary6 = "2001:db8::1"
                        Secondary6 = "2001:db8::2"
                        DohOnly = $true
                        DohTemplate = "https://doh.example.com/dns-query"
                        SecondaryDohTemplate = "https://secondary.doh.example.com/dns-query"
                    }
                    DohOnlyNoSecondary = [pscustomobject]@{
                        Primary = "192.0.2.1"
                        Secondary = ""
                        Primary6 = "2001:db8::1"
                        Secondary6 = ""
                        DohOnly = $true
                        DohTemplate = "https://doh.example.com/dns-query"
                    }
                }
            }
        })

        Mock Get-NetAdapter {
            [pscustomobject]@{
                Name = "Ethernet"
                Status = "Up"
                ifIndex = 7
                InterfaceGuid = "{1234-5678-90AB-CDEF}"
            }
        }
        Mock Set-DnsClientServerAddress { }
        Mock netsh { }
        Mock Write-WinUtilLog { }
        Mock Write-Warning { }
        Mock Write-Host { }

        Mock Get-Command { return $true } -ParameterFilter { $Name -eq "Add-DnsClientDohServerAddress" }
        Mock Add-DnsClientDohServerAddress { }
        Mock Set-DnsClientDohServerAddress { }
        Mock Get-DnsClientDohServerAddress { return $null }
        Mock Remove-DnsClientDohServerAddress { }
        Mock Test-Path { return $false }
        Mock Get-ChildItem { }
        Mock New-Item { }
        Mock New-ItemProperty { }
        Mock Remove-Item { }
        Mock Clear-DnsClientCache { }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
    }

    It "define os endereços de servidores DNS IPv4 e IPv6 separadamente e aplica modelos DoH" {
        $result = Set-WinUtilDNS -DNSProvider "Cloudflare"

        $result | Should -BeTrue
        Should -Invoke -CommandName Set-DnsClientServerAddress -Times 1 -Exactly -ParameterFilter {
            $InterfaceIndex -eq 7 -and
                $ServerAddresses.Count -eq 2 -and
                $ServerAddresses[0] -eq "1.1.1.1" -and
                $ServerAddresses[1] -eq "1.0.0.1"
        }
        Should -Invoke -CommandName Set-DnsClientServerAddress -Times 1 -Exactly -ParameterFilter {
            $InterfaceIndex -eq 7 -and
                $ServerAddresses.Count -eq 2 -and
                $ServerAddresses[0] -eq "2606:4700:4700::1111" -and
                $ServerAddresses[1] -eq "2606:4700:4700::1001"
        }
        Should -Invoke -CommandName Set-DnsClientServerAddress -Times 0 -Exactly -ParameterFilter {
            $ServerAddresses.Count -eq 4
        }
        Should -Invoke -CommandName Add-DnsClientDohServerAddress -Times 4 -Exactly
        Should -Invoke -CommandName New-ItemProperty -Times 4 -ParameterFilter {
            $Name -eq "DohFlags" -and $Value -eq 1
        }
        Should -Invoke -CommandName Clear-DnsClientCache -Times 1 -Exactly
    }

    It "preserva o DNS quando Fastest não tem sondagens bem-sucedidas" {
        Mock Get-WinUtilDNSBenchmark {
            [pscustomobject]@{ Provider = 'Cloudflare'; LatencyMs = 9999 }
        }
        Set-WinUtilDNS -DNSProvider 'Fastest' | Should -BeFalse
        Should -Invoke Get-NetAdapter -Times 0 -Exactly
        Should -Invoke Set-DnsClientServerAddress -Times 0 -Exactly
        Should -Invoke New-ItemProperty -Times 0 -Exactly
    }

    It "preserva o DNS quando Fastest não retorna resultados" {
        Mock Get-WinUtilDNSBenchmark { }
        Set-WinUtilDNS -DNSProvider 'Fastest' | Should -BeFalse
        Should -Invoke Get-NetAdapter -Times 0 -Exactly
        Should -Invoke Set-DnsClientServerAddress -Times 0 -Exactly
    }

    It "aplica o provedor Fastest bem-sucedido pelo caminho existente de DNS e DoH" {
        Mock Get-WinUtilDNSBenchmark {
            [pscustomobject]@{ Provider = 'Cloudflare'; LatencyMs = 12 }
            [pscustomobject]@{ Provider = 'Google'; LatencyMs = 9999 }
        }
        Set-WinUtilDNS -DNSProvider 'Fastest' | Should -BeTrue
        Should -Invoke Set-DnsClientServerAddress -Times 1 -Exactly -ParameterFilter {
            $ServerAddresses[0] -eq '1.1.1.1' -and $ServerAddresses[1] -eq '1.0.0.1'
        }
        Should -Invoke Add-DnsClientDohServerAddress -Times 4 -Exactly
    }

    It "atualiza uma entrada DoH existente com as configurações do provedor selecionado" {
        Mock Get-DnsClientDohServerAddress {
            if ($ServerAddress -eq "1.1.1.1") {
                return [pscustomobject]@{ ServerAddress = $ServerAddress }
            }
            return $null
        }

        Set-WinUtilDNS -DNSProvider "Cloudflare"

        Should -Invoke -CommandName Set-DnsClientDohServerAddress -Times 1 -Exactly -ParameterFilter {
            $ServerAddress -eq "1.1.1.1" -and
                $DohTemplate -eq "https://cloudflare-dns.com/dns-query" -and
                $AllowFallbackToUdp -eq $false -and
                $AutoUpgrade -eq $true
        }
        Should -Invoke -CommandName Add-DnsClientDohServerAddress -Times 3 -Exactly
    }

    It "filtra endereços de servidores DNS vazios" {
        Set-WinUtilDNS -DNSProvider "DohOnlyNoSecondary"

        Should -Invoke -CommandName Set-DnsClientServerAddress -Times 1 -Exactly -ParameterFilter {
            $InterfaceIndex -eq 7 -and
                $ServerAddresses.Count -eq 1 -and
                $ServerAddresses[0] -eq "192.0.2.1"
        }
        Should -Invoke -CommandName Set-DnsClientServerAddress -Times 1 -Exactly -ParameterFilter {
            $InterfaceIndex -eq 7 -and
                $ServerAddresses.Count -eq 1 -and
                $ServerAddresses[0] -eq "2001:db8::1"
        }
        Should -Invoke -CommandName Add-DnsClientDohServerAddress -Times 2 -Exactly
    }

    It "aplica o modelo DoH correspondente aos resolvedores secundários" {
        Set-WinUtilDNS -DNSProvider "DohOnlyProvider"

        Should -Invoke -CommandName Add-DnsClientDohServerAddress -Times 2 -Exactly -ParameterFilter {
            $ServerAddress -in @("192.0.2.1", "2001:db8::1") -and
                $DohTemplate -eq "https://doh.example.com/dns-query"
        }
        Should -Invoke -CommandName Add-DnsClientDohServerAddress -Times 2 -Exactly -ParameterFilter {
            $ServerAddress -in @("192.0.2.2", "2001:db8::2") -and
                $DohTemplate -eq "https://secondary.doh.example.com/dns-query"
        }
    }

    It "não aplica um provedor somente DoH quando o DoH não é compatível" {
        Mock Get-Command { return $null } -ParameterFilter { $Name -eq "Add-DnsClientDohServerAddress" }

        $result = Set-WinUtilDNS -DNSProvider "DohOnlyProvider"

        $result | Should -BeFalse
        Should -Invoke -CommandName Set-DnsClientServerAddress -Times 0 -Exactly
        Should -Invoke -CommandName Add-DnsClientDohServerAddress -Times 0 -Exactly
        Should -Invoke -CommandName Write-Warning -Times 1 -Exactly -ParameterFilter {
            $Message -eq "O provedor de DNS DohOnlyProvider exige DNS over HTTPS, que não é suportado neste sistema."
        }
    }

    It "não altera o DNS do adaptador quando o registro DoH falha" {
        Mock Add-DnsClientDohServerAddress { throw "DoH registration failed" }

        $result = Set-WinUtilDNS -DNSProvider "DohOnlyProvider"

        $result | Should -BeFalse
        Should -Invoke -CommandName Set-DnsClientServerAddress -Times 0 -Exactly
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq "ERROR" -and
                $Component -eq "DNS" -and
                $Message -like "O provedor de DNS DohOnlyProvider não foi concluído: *"
        }
    }

    It "recorre ao DNS comum quando o registro opcional do DoH falha" {
        Mock Add-DnsClientDohServerAddress { throw "DoH registration failed" }

        $result = Set-WinUtilDNS -DNSProvider "Cloudflare"

        $result | Should -BeTrue
        Should -Invoke -CommandName Set-DnsClientServerAddress -Times 2 -Exactly
        Should -Invoke -CommandName Write-Warning -Times 1 -Exactly -ParameterFilter {
            $Message -eq "A configuração de DNS over HTTPS para o provedor Cloudflare falhou; continuando com DNS simples."
        }
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq "WARN" -and
                $Component -eq "DNS" -and
                $Message -like "A configuração de DNS over HTTPS para o provedor Cloudflare falhou; continuando com DNS simples: *"
        }
    }

    It "redefine o DNS para DHCP e remove a configuração DoH aplicada" {
        Mock Test-Path { return $true } -ParameterFilter { $Path -like "*DohInterfaceSettings*" }
        Mock Get-ChildItem {
            if ($Path -like "*\Doh6") {
                return @(
                    [pscustomobject]@{ PSChildName = "2606:4700:4700::1111" }
                    [pscustomobject]@{ PSChildName = "2606:4700:4700::1001" }
                )
            }

            return @(
                [pscustomobject]@{ PSChildName = "1.1.1.1" }
                [pscustomobject]@{ PSChildName = "1.0.0.1" }
            )
        }
        Mock Get-DnsClientDohServerAddress {
            [pscustomobject]@{ ServerAddress = $ServerAddress }
        }
        
        Set-WinUtilDNS -DNSProvider "DHCP"

        Should -Invoke -CommandName Set-DnsClientServerAddress -Times 1 -Exactly -ParameterFilter {
            $InterfaceIndex -eq 7 -and
                $ResetServerAddresses -eq $true
        }
        Should -Invoke -CommandName netsh -Times 1 -Exactly -ParameterFilter {
            $Arguments[0] -eq "interface" -and
                $Arguments[1] -eq "ip" -and
                $Arguments[2] -eq "set" -and
                $Arguments[3] -eq "dnsservers" -and
                $Arguments[4] -eq "name=Ethernet" -and
                $Arguments[5] -eq "source=dhcp"
        }
        Should -Invoke -CommandName netsh -Times 1 -Exactly -ParameterFilter {
            $Arguments[0] -eq "interface" -and
                $Arguments[1] -eq "ipv6" -and
                $Arguments[2] -eq "set" -and
                $Arguments[3] -eq "dnsservers" -and
                $Arguments[4] -eq "name=Ethernet" -and
                $Arguments[5] -eq "source=dhcp"
        }
        Should -Invoke -CommandName Remove-Item -Times 1 -Exactly -ParameterFilter {
            $Path -like "*DohInterfaceSettings*" -and $Recurse -eq $true -and $Force -eq $true
        }
        Should -Invoke -CommandName Remove-DnsClientDohServerAddress -Times 4 -Exactly
    }

    It "captura falhas não terminantes na definição de DNS para que o runspace do ajuste possa continuar" {
        Mock Set-DnsClientServerAddress { Write-Error "DNS failed" -ErrorAction $ErrorAction }

        $result = Set-WinUtilDNS -DNSProvider "Cloudflare"

        $result | Should -BeFalse
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq "ERROR" -and
                $Component -eq "DNS" -and
                $Message -like "O provedor de DNS Cloudflare não foi concluído: *"
        }
    }

    It "retorna falha para um provedor DNS desconhecido" {
        $result = Set-WinUtilDNS -DNSProvider "Unknown"

        $result | Should -BeFalse
        Should -Invoke -CommandName Set-DnsClientServerAddress -Times 0 -Exactly
    }
}
