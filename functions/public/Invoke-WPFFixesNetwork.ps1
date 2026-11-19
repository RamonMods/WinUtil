function Invoke-WPFFixesNetwork {
    netsh winsock reset
    netsh int ip reset
    Write-Host "A configuração de rede foi redefinida. Reinicie o computador."
}
