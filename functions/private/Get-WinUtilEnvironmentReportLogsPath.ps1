function Get-WinUtilEnvironmentReportLogsPath {
    <#
    .SYNOPSIS
        Deriva o caminho do .txt de logs companheiro a partir do caminho de salvamento do JSON do relatório de ambiente.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$JsonPath
    )

    # ChangeExtension($JsonPath, $null) deixa um ponto final em vez de removê-lo, então monte o
    # nome a partir de suas partes.
    $directory = [System.IO.Path]::GetDirectoryName($JsonPath)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($JsonPath)
    return [System.IO.Path]::Combine($directory, "${baseName}_logs.txt")
}
