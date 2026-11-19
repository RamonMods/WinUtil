#===========================================================================
# Testes - Fluxo de triagem de issues do GitHub
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $script:workflowPath = Join-Path $script:repoRoot ".github\workflows\triage-tools.yaml"
    $script:guidePath = Join-Path $script:repoRoot "docs\src\content\docs\code-reference\issue-triage.mdx"
    $script:workflow = Get-Content -Path $script:workflowPath -Raw
    $script:guide = Get-Content -Path $script:guidePath -Raw
}

Describe "Fluxo de triagem de issues do GitHub" {
    It "não pode ser executado em pull requests" {
        $script:workflow | Should -Match '(?m)^\s+if:\s+\$\{\{\s*!github\.event\.issue\.pull_request\s*\}\}\s*$'
        $script:workflow | Should -Match 'if \(context\.payload\.issue\.pull_request\)'
        $script:workflow | Should -Match '(?m)^\s+issues:\s+write\s*$'
        $script:workflow | Should -Match '(?m)^\s+pull-requests:\s+none\s*$'
        $script:workflow | Should -Match '(?m)^\s+contents:\s+none\s*$'
        $script:workflow | Should -Not -Match '(?m)^\s+pull-requests:\s+write\s*$'
    }

    It "autoriza usuários confiáveis por ID numérico imutável" {
        $script:workflow | Should -Match 'trustedUsers\.includes\(commentAuthor\.id\)'
        $script:workflow | Should -Not -Match 'trustedUsers\.includes\(commentAuthor\.login\)'
    }

    It "corresponde a um comando completo por vez" {
        $script:workflow.Contains('const command = comment.body.trim().toLowerCase();') | Should -BeTrue
        $script:workflow.Contains('const triageMatch = command.match(/^\/triage$/);') | Should -BeTrue
        $script:workflow.Contains('const triageOffMatch = command.match(/^\/triageoff$/);') | Should -BeTrue
        $script:workflow.Contains('const notPlannedMatch = command.match(/^\/np(?:\s+(\w+))?$/);') | Should -BeTrue
        $script:workflow.Contains('const duplicateMatch = command.match(/^\/duplicate\s+#?(\d+)$/);') | Should -BeTrue
        $script:workflow.Contains('} else if (triageOffMatch) {') | Should -BeTrue
        $script:workflow.Contains('} else if (notPlannedMatch) {') | Should -BeTrue
        $script:workflow.Contains('} else if (duplicateMatch) {') | Should -BeTrue
    }

    It "preserva rótulos existentes em fechamentos não relacionados" {
        $notRelatedBlock = [regex]::Match(
            $script:workflow,
            '(?s)reason === "notrelated".*?github\.rest\.issues\.addLabels\(\{.*?labels: \["not-related"\].*?github\.rest\.issues\.update'
        )

        $notRelatedBlock.Success | Should -BeTrue
        $notRelatedBlock.Value | Should -Not -Match 'issues\.update\(\{.*?labels:'
    }

    It "valida alvos duplicados antes de fechar a issue" {
        $script:workflow.Contains('const duplicateIssueNumber = Number(duplicateMatch[1]);') | Should -BeTrue
        $script:workflow | Should -Match 'Number\.isSafeInteger\(duplicateIssueNumber\)'
        $script:workflow | Should -Match 'duplicateIssueNumber === issueNumber'
        $script:workflow | Should -Match 'duplicateIssue = response\.data'
        $script:workflow | Should -Match 'duplicateIssue\?\.pull_request'
        $script:workflow | Should -Match 'error\.status !== 404'
        $script:workflow | Should -Match 'throw error'
        $script:workflow | Should -Match 'duplicate_issue_id: duplicateIssue\.id'
    }

    It "mantém o guia do mantenedor no site de documentação" {
        Test-Path -Path (Join-Path $script:repoRoot ".github\TRIAGE_TOOLS.md") | Should -BeFalse
        $script:guide | Should -Match 'Esses comandos funcionam apenas em issues\.'
        $script:guide | Should -Match '`not-related` sem substituir os rótulos existentes'

        $astroConfig = Get-Content -Path (Join-Path $script:repoRoot "docs\astro.config.mjs") -Raw
        $astroConfig | Should -Match "slug: 'code-reference/issue-triage'"
    }
}
