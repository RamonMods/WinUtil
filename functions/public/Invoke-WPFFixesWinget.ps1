function Invoke-WPFFixesWinget {

    <#

    .SYNOPSIS
        Corrige o WinGet executando `choco install winget`
    .DESCRIPTION
        BravoNorris pela ideia fantástica de um botão para reinstalar o WinGet
    #>

    Step-WinUtilJob -Status "Reparando o WinGet" -State "Indeterminate"
    Install-WinUtilWinget -Force
}
