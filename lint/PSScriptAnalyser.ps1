@{
    # Somente registros de diagnóstico da severidade especificada serão gerados.
    # Descomente a linha a seguir se quiser apenas erros e avisos, mas não
    # registros de diagnóstico informativos.
    # Severity = @('Error','Warning')

    # Analisa **apenas** as regras a seguir. Use IncludeRules quando quiser
    # invocar somente um pequeno subconjunto das regras padrão.
<#
    IncludeRules = @('PSAvoidDefaultValueSwitchParameter',
                     'PSMisleadingBacktick',
                     'PSMissingModuleManifestField',
                     'PSReservedCmdletChar',
                     'PSReservedParams',
                     'PSShouldProcess',
                     'PSUseApprovedVerbs',
                     'PSUseDeclaredVarsMoreThanAssignments')
#>
    # Não analisa as regras a seguir. Use ExcludeRules quando tiver
    # comentado a configuração IncludeRules acima e quiser incluir todas
    # as regras padrão, exceto as que você excluir abaixo.
    # Observação: se uma regra estiver em IncludeRules e ExcludeRules, a regra
    # será excluída.
    ExcludeRules = @('PSAvoidUsingWriteHost')
}
