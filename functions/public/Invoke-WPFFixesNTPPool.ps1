function Invoke-WPFFixesNTPPool {
    <#
    .SYNOPSIS
        Configura o Windows para usar pool.ntp.org na sincronização NTP

    .DESCRIPTION
        Substitui o servidor NTP padrão do Windows (time.windows.com) por
        pool.ntp.org para melhorar a precisão e a confiabilidade da sincronização de horário.
    #>

    Start-Service w32time
    w32tm /config /update /manualpeerlist:"pool.ntp.org,0x8" /syncfromflags:MANUAL

    Restart-Service w32time
    w32tm /resync

}
