BeforeAll {
    $tweaks = Get-Content (Join-Path $PSScriptRoot '..\config\tweaks.json') -Raw | ConvertFrom-Json
    $invokeText = $tweaks.WPFTweaksRemoveOneDrive.InvokeScript -join "`n"
    # Intercepta a gravação persistente no ambiente; os artefatos do sistema de arquivos ficam no TestDrive.
    $invokeText = $invokeText.Replace("[Environment]::SetEnvironmentVariable('OneDrive', `$null, 'User')", 'Clear-TestOneDriveEnvironment')
    $script:removeOneDrive = [scriptblock]::Create($invokeText)
    function icacls {
        param($Target, $Operation, $Principal)
        throw "icacls must be mocked: $Target $Operation $Principal"
    }
    function Clear-TestOneDriveEnvironment {
        throw 'The persistent environment write must be mocked.'
    }
}

Describe 'Remoção do OneDrive' {
    BeforeEach {
        $script:savedOneDrive = $Env:OneDrive
        $script:savedLocalAppData = $Env:LocalAppData
        $script:savedProgramData = $Env:ProgramData
        $script:savedExitCode = $global:LASTEXITCODE
        $script:fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:oneDrivePath = Join-Path $script:fixtureRoot 'OneDrive'
        $Env:OneDrive = $script:oneDrivePath
        $Env:LocalAppData = Join-Path $script:fixtureRoot 'LocalAppData'
        $Env:ProgramData = Join-Path $script:fixtureRoot 'ProgramData'
        $script:aclOperations = [System.Collections.Generic.List[string]]::new()
        $script:originalAcl = [System.Security.AccessControl.DirectorySecurity]::new()
        Mock Get-Acl { $script:originalAcl }
        Mock Set-Acl { $script:aclOperations.Add('restore') }
        Mock icacls {
            $script:aclOperations.Add($Operation)
            $global:LASTEXITCODE = 0
        }
        Mock Start-Process { }
        $script:explorer = [System.Diagnostics.Process]::new()
        $script:explorer | Add-Member -MemberType NoteProperty -Name ProcessName -Value 'Explorer' -Force
        Mock Get-Process { $script:explorer }
        Mock Stop-Process { }
        Mock Set-Service { }
        Mock Remove-Item { }
        Mock Clear-TestOneDriveEnvironment { }
        Mock Write-Host { }
    }

    AfterEach {
        $Env:OneDrive = $script:savedOneDrive
        $Env:LocalAppData = $script:savedLocalAppData
        $Env:ProgramData = $script:savedProgramData
        $global:LASTEXITCODE = $script:savedExitCode
    }

    It 'ignora um caminho de pasta vazio ou ausente, mas ainda assim desinstala' -TestCases @(
        @{ EmptyPath = $true }, @{ EmptyPath = $false }
    ) {
        param($EmptyPath)
        if ($EmptyPath) { $Env:OneDrive = '' }
        & $script:removeOneDrive
        Should -Invoke icacls -Times 0 -Exactly
        Should -Invoke Get-Acl -Times 0 -Exactly
        Should -Invoke Set-Acl -Times 0 -Exactly
        Should -Invoke Clear-TestOneDriveEnvironment -Times 0 -Exactly
        Should -Invoke Remove-Item -Times 0 -Exactly
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $ArgumentList -eq '/uninstall' -and $Wait }
        Should -Invoke Set-Service -Times 1 -Exactly -ParameterFilter { $Name -eq 'OneSyncSvc' -and $StartupType -eq 'Disabled' }
        Should -Invoke Stop-Process -Times 1 -Exactly -ParameterFilter { $InputObject -eq $script:explorer }
    }

    It 'protege uma pasta existente durante a desinstalação e a exclui somente quando vazia' {
        New-Item -ItemType Directory -Path $script:oneDrivePath -Force | Out-Null
        Mock Start-Process { $script:aclOperations.ToArray() | Should -Be @('/deny') }
        & $script:removeOneDrive
        $script:aclOperations.ToArray() | Should -Be @('/deny', 'restore')
        Should -Invoke Set-Acl -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq $script:oneDrivePath -and $AclObject -eq $script:originalAcl }
        Test-Path -LiteralPath $script:oneDrivePath | Should -BeFalse
        Should -Invoke Clear-TestOneDriveEnvironment -Times 1 -Exactly
    }

    It 'preserva uma pasta do OneDrive que contém apenas arquivos ocultos' {
        New-Item -ItemType Directory -Path $script:oneDrivePath -Force | Out-Null
        $hiddenFile = New-Item -ItemType File -Path (Join-Path $script:oneDrivePath 'notes.txt')
        $hiddenFile.Attributes = $hiddenFile.Attributes -bor [System.IO.FileAttributes]::Hidden
        & $script:removeOneDrive
        Test-Path -LiteralPath $hiddenFile.FullName | Should -BeTrue
        Should -Invoke Clear-TestOneDriveEnvironment -Times 0 -Exactly
    }

    It 'se recusa a excluir arquivos adicionados após a verificação de pasta vazia' {
        New-Item -ItemType Directory -Path $script:oneDrivePath -Force | Out-Null
        Mock Get-ChildItem {
            New-Item -ItemType File -Path (Join-Path $script:oneDrivePath 'new-file.txt') | Out-Null
        } -ParameterFilter { $LiteralPath -eq $script:oneDrivePath }
        { & $script:removeOneDrive } | Should -Throw
        Test-Path -LiteralPath (Join-Path $script:oneDrivePath 'new-file.txt') | Should -BeTrue
        Should -Invoke Clear-TestOneDriveEnvironment -Times 0 -Exactly
    }

    It 'interrompe apenas um processo FileCoAuth em execução e ainda assim interrompe o Explorer' {
        $script:fileCoAuth = [System.Diagnostics.Process]::new()
        $script:fileCoAuth | Add-Member -MemberType NoteProperty -Name ProcessName -Value 'FileCoAuth' -Force
        Mock Get-Process { $script:fileCoAuth; $script:explorer }
        & $script:removeOneDrive
        Should -Invoke Stop-Process -Times 1 -Exactly -ParameterFilter { $InputObject -eq $script:fileCoAuth }
        Should -Invoke Stop-Process -Times 1 -Exactly -ParameterFilter { $InputObject -eq $script:explorer }
    }

    It 'continua a limpeza quando o Explorer não está em execução' {
        Mock Get-Process { }
        New-Item -ItemType Directory -Path $script:oneDrivePath -Force | Out-Null
        & $script:removeOneDrive
        Should -Invoke Stop-Process -Times 0 -Exactly
        Test-Path -LiteralPath $script:oneDrivePath | Should -BeFalse
        Should -Invoke Clear-TestOneDriveEnvironment -Times 1 -Exactly
        Should -Invoke Set-Service -Times 1 -Exactly -ParameterFilter { $Name -eq 'OneSyncSvc' }
    }

    It 'restaura permissões e informa falha ao interromper um processo' {
        New-Item -ItemType Directory -Path $script:oneDrivePath -Force | Out-Null
        Mock Stop-Process { throw 'Process stop denied' }
        { & $script:removeOneDrive } | Should -Throw '*Process stop denied*'
        $script:aclOperations.ToArray() | Should -Be @('/deny', 'restore')
        Test-Path -LiteralPath $script:oneDrivePath | Should -BeTrue
        Should -Invoke Clear-TestOneDriveEnvironment -Times 0 -Exactly
    }

    It 'limpa apenas diretórios opcionais que existem' {
        $leftoverPath = Join-Path $Env:LocalAppData 'Microsoft\OneDrive'
        New-Item -ItemType Directory -Path $leftoverPath -Force | Out-Null
        & $script:removeOneDrive
        Should -Invoke Remove-Item -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq $leftoverPath -and $Recurse -and $Force }
    }

    It 'restaura permissões e informa falha na desinstalação' {
        New-Item -ItemType Directory -Path $script:oneDrivePath -Force | Out-Null
        Mock Start-Process { throw 'Uninstaller failed' }
        { & $script:removeOneDrive } | Should -Throw '*Uninstaller failed*'
        $script:aclOperations.ToArray() | Should -Be @('/deny', 'restore')
        Test-Path -LiteralPath $script:oneDrivePath | Should -BeTrue
        Should -Invoke Clear-TestOneDriveEnvironment -Times 0 -Exactly
    }

    It 'restaura permissões e informa erro na limpeza de resíduos' {
        New-Item -ItemType Directory -Path $script:oneDrivePath -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $Env:LocalAppData 'Microsoft\OneDrive') -Force | Out-Null
        Mock Remove-Item { throw 'Cleanup access denied' }
        { & $script:removeOneDrive } | Should -Throw '*Cleanup access denied*'
        $script:aclOperations.ToArray() | Should -Be @('/deny', 'restore')
        Should -Invoke Clear-TestOneDriveEnvironment -Times 0 -Exactly
    }

    It 'informa falha de ACL antes de tentar a desinstalação' {
        New-Item -ItemType Directory -Path $script:oneDrivePath -Force | Out-Null
        Mock icacls { $global:LASTEXITCODE = 5 }
        { & $script:removeOneDrive } | Should -Throw '*Unable to protect*'
        Should -Invoke Set-Acl -Times 1 -Exactly
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'informa falha na restauração de permissões e mantém a pasta' {
        New-Item -ItemType Directory -Path $script:oneDrivePath -Force | Out-Null
        Mock Set-Acl { throw 'ACL restoration failed' }
        { & $script:removeOneDrive } | Should -Throw '*ACL restoration failed*'
        Test-Path -LiteralPath $script:oneDrivePath | Should -BeTrue
        Should -Invoke Clear-TestOneDriveEnvironment -Times 0 -Exactly
    }

    It 'não interpreta uma enumeração de pasta falha como pasta vazia' {
        New-Item -ItemType Directory -Path $script:oneDrivePath -Force | Out-Null
        Mock Get-ChildItem { throw 'Enumeration access denied' } -ParameterFilter { $LiteralPath -eq $script:oneDrivePath }
        { & $script:removeOneDrive } | Should -Throw '*Enumeration access denied*'
        Test-Path -LiteralPath $script:oneDrivePath | Should -BeTrue
        Should -Invoke Clear-TestOneDriveEnvironment -Times 0 -Exactly
    }
}
