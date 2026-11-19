function Invoke-WPFFixesUpdate {

    <#

    .SYNOPSIS
        Executa diversas tarefas na tentativa de reparar o Windows Update

    .DESCRIPTION
        1. (Somente Agressivo) Verifica o sistema em busca de corrupção usando a função Invoke-WPFSystemRepair
        2. Interrompe os serviços do Windows Update
        3. Remove o arquivo de dados do QMGR, que armazena os jobs do BITS
        4. (Somente Agressivo) Renomeia as pastas DataStore e CatRoot2
            DataStore - Contém o histórico e os arquivos de log do Windows Update
            CatRoot2 - Contém as assinaturas dos pacotes do Windows Update
        5. Renomeia a pasta de download do Windows Update
        6. Exclui o log do Windows Update
        7. (Somente Agressivo) Redefine os descritores de segurança dos serviços do Windows Update
        8. Registra novamente as DLLs do BITS e do Windows Update
        9. Remove as configurações de cliente do WSUS
        10. Redefine o WinSock
        11. Obtém e exclui todos os jobs do BITS
        12. Define o tipo de inicialização dos serviços do Windows Update e os inicia
        13. Força o Windows Update a verificar atualizações

    .PARAMETER Aggressive
        Se especificado, o script executará etapas adicionais para reparar o Windows Update que são mais arriscadas, demoram bastante ou geralmente são desnecessárias

    #>

    param($Aggressive = $false)

    Write-Progress -Id 0 -Activity "Reparando o Windows Update" -PercentComplete 0
    Step-WinUtilJob -State "Indeterminate"
    Write-Host "Iniciando o reparo do Windows Update..."
    # Aguarda a primeira barra de progresso aparecer; caso contrário, a segunda não aparecerá
    Start-Sleep -Milliseconds 200

    if ($Aggressive) {
        Invoke-WPFSystemRepair
    }


    Write-Progress -Id 0 -Activity "Reparando o Windows Update" -Status "Interrompendo os serviços do Windows Update..." -PercentComplete 10
    # Interrompe os serviços do Windows Update
    $services = @("BITS", "wuauserv", "appidsvc", "cryptsvc")
    for ($i = 0; $i -lt $services.Count; $i++) {
        $svc = $services[$i]
        $pct = [int](($i / $services.Count) * 100)
        Write-Progress -Id 2 -ParentId 0 -Activity "Parando serviços" -Status "Parando $svc..." -PercentComplete $pct
        Stop-Service -Name $svc -Force
    }
    Write-Progress -Id 2 -ParentId 0 -Activity "Parando serviços" -Status "Concluído" -PercentComplete 100


    # Remove o arquivo de dados do QMGR
    Write-Progress -Id 0 -Activity "Reparando o Windows Update" -Status "Renomeando/removendo arquivos..." -PercentComplete 20
    Write-Progress -Id 3 -ParentId 0 -Activity "Renomeando/removendo arquivos" -Status "Removendo arquivos de dados do QMGR..." -PercentComplete 0
    Remove-Item "$env:allusersprofile\Application Data\Microsoft\Network\Downloader\qmgr*.dat" -ErrorAction SilentlyContinue


    if ($Aggressive) {
        # Renomeia o log do Windows Update e as pastas de assinaturas
        Write-Progress -Id 3 -ParentId 0 -Activity "Renomeando/removendo arquivos" -Status "Renomeando o log, o download e a pasta de assinaturas do Windows Update..." -PercentComplete 20
        Rename-Item $env:systemroot\SoftwareDistribution\DataStore DataStore.bak -ErrorAction SilentlyContinue
        Rename-Item $env:systemroot\System32\Catroot2 catroot2.bak -ErrorAction SilentlyContinue
    }

    # Renomeia a pasta de download do Windows Update
    Write-Progress -Id 3 -ParentId 0 -Activity "Renomeando/removendo arquivos" -Status "Renomeando a pasta de download do Windows Update..." -PercentComplete 20
    Rename-Item $env:systemroot\SoftwareDistribution\Download Download.bak -ErrorAction SilentlyContinue

    # Exclui o log antigo do Windows Update
    Write-Progress -Id 3 -ParentId 0 -Activity "Renomeando/removendo arquivos" -Status "Removendo o log antigo do Windows Update..." -PercentComplete 80
    Remove-Item $env:systemroot\WindowsUpdate.log -ErrorAction SilentlyContinue
    Write-Progress -Id 3 -ParentId 0 -Activity "Renomeando/removendo arquivos" -Status "Concluído" -PercentComplete 100


    if ($Aggressive) {
        # Redefine os descritores de segurança dos serviços do Windows Update
        Write-Progress -Id 0 -Activity "Reparando o Windows Update" -Status "Redefinindo os descritores de segurança dos serviços do WU..." -PercentComplete 25
        Write-Progress -Id 4 -ParentId 0 -Activity "Redefinindo os descritores de segurança dos serviços do WU" -Status "Redefinindo o descritor de segurança do BITS..." -PercentComplete 0
        Start-Process -NoNewWindow -FilePath "sc.exe" -ArgumentList "sdset", "bits", "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)" -Wait
        Write-Progress -Id 4 -ParentId 0 -Activity "Redefinindo os descritores de segurança dos serviços do WU" -Status "Redefinindo o descritor de segurança do wuauserv..." -PercentComplete 50
        Start-Process -NoNewWindow -FilePath "sc.exe" -ArgumentList "sdset", "wuauserv", "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)" -Wait
        Write-Progress -Id 4 -ParentId 0 -Activity "Redefinindo os descritores de segurança dos serviços do WU" -Status "Concluído" -PercentComplete 100
    }


    # Registra novamente as DLLs do BITS e do Windows Update
    Write-Progress -Id 0 -Activity "Reparando o Windows Update" -Status "Registrando novamente as DLLs..." -PercentComplete 40
    $oldLocation = Get-Location
    Set-Location $env:systemroot\system32
    $i = 0
    $DLLs = @(
        "atl.dll", "urlmon.dll", "mshtml.dll", "shdocvw.dll", "browseui.dll",
        "jscript.dll", "vbscript.dll", "scrrun.dll", "msxml.dll", "msxml3.dll",
        "msxml6.dll", "actxprxy.dll", "softpub.dll", "wintrust.dll", "dssenh.dll",
        "rsaenh.dll", "gpkcsp.dll", "sccbase.dll", "slbcsp.dll", "cryptdlg.dll",
        "oleaut32.dll", "ole32.dll", "shell32.dll", "initpki.dll", "wuapi.dll",
        "wuaueng.dll", "wuaueng1.dll", "wucltui.dll", "wups.dll", "wups2.dll",
        "wuweb.dll", "qmgr.dll", "qmgrprxy.dll", "wucltux.dll", "muweb.dll", "wuwebv.dll"
    )
    foreach ($dll in $DLLs) {
        if ($i % 5 -eq 0 -or $i -eq ($DLLs.Count - 1)) {
            Write-Progress -Id 5 -ParentId 0 -Activity "Registrando novamente as DLLs" -Status "Registrando $dll..." -PercentComplete (($i / $DLLs.Count) * 100)
        }
        $i++
        Start-Process -NoNewWindow -FilePath "regsvr32.exe" -ArgumentList "/s", $dll
    }
    Set-Location $oldLocation
    Write-Progress -Id 5 -ParentId 0 -Activity "Registrando novamente as DLLs" -Status "Concluído" -PercentComplete 100


    # Remove as configurações de cliente do WSUS
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate") {
        Write-Progress -Id 0 -Activity "Reparando o Windows Update" -Status "Removendo as configurações de cliente do WSUS..." -PercentComplete 60
        Write-Progress -Id 6 -ParentId 0 -Activity "Removendo as configurações de cliente do WSUS" -PercentComplete 0
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" -Name "AccountDomainSid" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" -Name "PingID" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" -Name "SusClientId" -ErrorAction SilentlyContinue
        Write-Progress -Id 6 -ParentId 0 -Activity "Removendo as configurações de cliente do WSUS" -Status "Concluído" -PercentComplete 100
    }

    # Remove as configurações de Política de Grupo do Windows Update
    Write-Progress -Id 0 -Activity "Reparando o Windows Update" -Status "Removendo as configurações de Política de Grupo do Windows Update..." -PercentComplete 60
    Write-Progress -Id 7 -ParentId 0 -Activity "Removendo as configurações de Política de Grupo do Windows Update" -PercentComplete 0
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ExcludeWUDriversInQualityUpdate" -ErrorAction SilentlyContinue
    Write-Host "Restaurando a oferta de drivers pelo Windows Update..."
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontPromptForWindowsUpdate" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontSearchWindowsUpdate" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DriverUpdateWizardWuSearchEnabled" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ExcludeWUDriversInQualityUpdate" -ErrorAction SilentlyContinue
    Write-Host "Restaurando a reinicialização automática do Windows Update..."
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoRebootWithLoggedOnUsers" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUPowerManagement" -ErrorAction SilentlyContinue
    Write-Host "Limpando TODAS as configurações de Política do Windows Update..."
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "BranchReadinessLevel" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "DeferFeatureUpdatesPeriodInDays" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "DeferQualityUpdatesPeriodInDays" -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCU:\Software\Microsoft\WindowsSelfHost" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCU:\Software\Policies" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKLM:\Software\Microsoft\Policies" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\WindowsStore\WindowsUpdate" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKLM:\Software\Microsoft\WindowsSelfHost" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKLM:\Software\Policies" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKLM:\Software\WOW6432Node\Microsoft\Policies" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Policies" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\WindowsStore\WindowsUpdate" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Process -NoNewWindow -FilePath "secedit" -ArgumentList "/configure", "/cfg", "$env:windir\inf\defltbase.inf", "/db", "defltbase.sdb", "/verbose" -Wait
    Start-Process -NoNewWindow -FilePath "cmd.exe" -ArgumentList "/c RD /S /Q $env:WinDir\System32\GroupPolicyUsers" -Wait
    Start-Process -NoNewWindow -FilePath "cmd.exe" -ArgumentList "/c RD /S /Q $env:WinDir\System32\GroupPolicy" -Wait
    Start-Process -NoNewWindow -FilePath "gpupdate" -ArgumentList "/force" -Wait
    Write-Progress -Id 7 -ParentId 0 -Activity "Removendo as configurações de Política de Grupo do Windows Update" -Status "Concluído" -PercentComplete 100


    # Redefine o WinSock
    Write-Progress -Id 0 -Activity "Reparando o Windows Update" -Status "Redefinindo o WinSock..." -PercentComplete 65
    Write-Progress -Id 7 -ParentId 0 -Activity "Redefinindo o WinSock" -Status "Redefinindo o WinSock..." -PercentComplete 0
    Start-Process -NoNewWindow -FilePath "netsh" -ArgumentList "winsock", "reset"
    Start-Process -NoNewWindow -FilePath "netsh" -ArgumentList "winhttp", "reset", "proxy"
    Start-Process -NoNewWindow -FilePath "netsh" -ArgumentList "int", "ip", "reset"
    Write-Progress -Id 7 -ParentId 0 -Activity "Redefinindo o WinSock" -Status "Concluído" -PercentComplete 100


    # Obtém e exclui todos os jobs do BITS
    Write-Progress -Id 0 -Activity "Reparando o Windows Update" -Status "Excluindo jobs do BITS..." -PercentComplete 75
    Write-Progress -Id 8 -ParentId 0 -Activity "Excluindo jobs do BITS" -Status "Excluindo jobs do BITS..." -PercentComplete 0
    Get-BitsTransfer | Remove-BitsTransfer
    Write-Progress -Id 8 -ParentId 0 -Activity "Excluindo jobs do BITS" -Status "Concluído" -PercentComplete 100


    # Altera o tipo de inicialização dos serviços do Windows Update e os inicia
    Write-Progress -Id 0 -Activity "Reparando o Windows Update" -Status "Iniciando os serviços do Windows Update..." -PercentComplete 90
    Write-Progress -Id 9 -ParentId 0 -Activity "Iniciando os serviços do Windows Update" -Status "Iniciando o BITS..." -PercentComplete 0
    Get-Service BITS | Set-Service -StartupType Manual -PassThru | Start-Service
    Write-Progress -Id 9 -ParentId 0 -Activity "Iniciando os serviços do Windows Update" -Status "Iniciando o wuauserv..." -PercentComplete 25
    Get-Service wuauserv | Set-Service -StartupType Manual -PassThru | Start-Service
    Write-Progress -Id 9 -ParentId 0 -Activity "Iniciando os serviços do Windows Update" -Status "Iniciando o AppIDSvc..." -PercentComplete 50
    # O serviço AppIDSvc é protegido, então o tipo de inicialização precisa ser alterado no Registro
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\AppIDSvc" -Name "Start" -Value "3" # Manual
    Start-Service AppIDSvc
    Write-Progress -Id 9 -ParentId 0 -Activity "Iniciando os serviços do Windows Update" -Status "Iniciando o CryptSvc..." -PercentComplete 75
    Get-Service CryptSvc | Set-Service -StartupType Manual -PassThru | Start-Service
    Write-Progress -Id 9 -ParentId 0 -Activity "Iniciando os serviços do Windows Update" -Status "Concluído" -PercentComplete 100


    # Força o Windows Update a verificar atualizações
    Write-Progress -Id 0 -Activity "Reparando o Windows Update" -Status "Forçando a detecção..." -PercentComplete 95
    Write-Progress -Id 10 -ParentId 0 -Activity "Forçando a detecção" -Status "Forçando a detecção..." -PercentComplete 0
    try {
        (New-Object -ComObject Microsoft.Update.AutoUpdate).DetectNow()
    } catch {
        Write-WinUtilLog -Level "ERROR" -Component "Updates" -Message "Falha ao criar o objeto COM do Windows Update: $_"
        Write-Warning "Falha ao criar o objeto COM do Windows Update: $_"
    }
    Start-Process -NoNewWindow -FilePath "wuauclt" -ArgumentList "/resetauthorization", "/detectnow"
    Write-Progress -Id 10 -ParentId 0 -Activity "Forçando a detecção" -Status "Concluído" -PercentComplete 100
    Write-Progress -Id 0 -Activity "Reparando o Windows Update" -Status "Concluído" -PercentComplete 100

    Show-WinUtilMessage -Message "Configurações padrão carregadas.`n Reinicie o computador" -Title "Redefinir Windows Update" -Button "OK" -Icon "Information" | Out-Null

    # Remove as barras de progresso
    foreach ($id in 0..10) {
        Write-Progress -Id $id -Activity "Concluído" -Completed -ErrorAction SilentlyContinue
    }
}
