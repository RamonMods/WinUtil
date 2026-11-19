function Invoke-WPFtweaksbutton {
  <#

    .SYNOPSIS
        Invoca as funções associadas a cada grupo de caixas de seleção

  #>

  $Tweaks = $sync.selectedTweaks
  $dnsProvider = $sync["WPFchangedns"].text
  if (-not ($dnsProvider)) {
    $dnsProvider = "Default"
  }

  if ($Tweaks.count -eq 0 -and $dnsProvider -eq "Default") {
    Show-WinUtilMessage -Message "Marque os ajustes que deseja executar." -Title "WinUtil" -Button "OK" -Icon "Warning"
    return
  }

  Write-WinUtilLog -Component "Tweaks" -Message "Ajustes solicitados: $(@($Tweaks).Count) ajuste(s) selecionado(s), provedor de DNS: $dnsProvider"

  Start-WinUtilJob -Name "Tweaks" -Description "Aplicando ajustes" -QueueIfBusy -Parameters @{
    Tweaks = @($Tweaks)
    DnsProvider = $dnsProvider
  } -ScriptBlock {
    param($Tweaks, $DnsProvider)

    # O ponto de restauração precisa ser criado antes de qualquer outra alteração
    $restorePointTweak = "WPFTweaksRestorePoint"
    $tweaksToRun = @($Tweaks | Where-Object { $_ -ne $restorePointTweak })
    $totalSteps = [Math]::Max(@($Tweaks).Count, 1)
    $completedSteps = 0

    if ($Tweaks -contains $restorePointTweak) {
      Step-WinUtilJob -Status "Criando ponto de restauração" -Percent 0
      Write-WinUtilLog -Component "Tweaks" -Message "Criando ponto de restauração antes de aplicar os ajustes selecionados."
      Measure-WinUtilStep -Scope "Tweaks" -Name $restorePointTweak -ScriptBlock {
        Invoke-WinUtilTweaks $restorePointTweak
      }
      $completedSteps = 1
    }

    if ($DnsProvider -ne "Default") {
      $dnsResult = Measure-WinUtilStep -Scope "Tweaks" -Name "Definir DNS para $DnsProvider" -ScriptBlock {
        @(Set-WinUtilDNS -DNSProvider $DnsProvider)
      }

      # Continuar após a falha na alteração de DNS deixaria a máquina meio configurada, então a
      # execução termina aqui e a camada de jobs reporta o problema
      if (@($dnsResult)[-1] -ne $true) {
        throw "A alteração de DNS para $DnsProvider falhou, portanto os ajustes restantes não foram aplicados."
      }
    }

    foreach ($tweak in $tweaksToRun) {
      $tweakLabel = Get-WinUtilTweakDisplayName -Key $tweak
      Step-WinUtilJob -Status "Aplicando $tweakLabel ($($completedSteps + 1)/$totalSteps)" -Percent ([int](($completedSteps / $totalSteps) * 100))
      Measure-WinUtilStep -Scope "Tweaks" -Name $tweak -ScriptBlock {
        Invoke-WinUtilTweaks $tweak
      }
      $completedSteps++
      Step-WinUtilJob -Percent ([int](($completedSteps / $totalSteps) * 100))
    }
  }
}
