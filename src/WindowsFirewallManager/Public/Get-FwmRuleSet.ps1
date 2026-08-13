function Get-FwmRuleSet {
    <#
    .SYNOPSIS
        Inventorie les ensembles de regles crees par cet outil.

    .DESCRIPTION
        Parcourt les regles du pare-feu et ne retient que celles portant des
        metadonnees FWM valides dans leur description. Les regles creees par
        Windows, par un autre outil, ou a la main sont ignorees.

        Ne necessite pas de droits administrateur.

    .PARAMETER SetName
        Filtre sur le nom d'ensemble. Accepte les caracteres generiques.
        Le filtrage est effectue cote client : aucun caractere generique
        n'est transmis au pare-feu.

    .EXAMPLE
        Get-FwmRuleSet

    .EXAMPLE
        Get-FwmRuleSet -SetName 'Spotify*'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [SupportsWildcards()]
        [string]$SetName = '*'
    )

    Write-Verbose 'Lecture des regles du pare-feu...'
    $allRules = @(Get-NetFirewallRule -ErrorAction SilentlyContinue)
    Write-Verbose "$($allRules.Count) regle(s) lue(s)."

    $matched = foreach ($rule in $allRules) {
        $metadata = ConvertFrom-FwmDescription -Description $rule.Description
        if ($null -eq $metadata) { continue }
        if ($metadata.set -notlike $SetName) { continue }

        [PSCustomObject]@{
            Rule     = $rule
            Metadata = $metadata
        }
    }

    $matched = @($matched)
    if ($matched.Count -eq 0) { return }

    foreach ($group in ($matched | Group-Object -Property { $_.Metadata.set } | Sort-Object -Property Name)) {
        $entries = @($group.Group)
        $rules = @($entries | ForEach-Object { $_.Rule })

        $created = @($entries | ForEach-Object { $_.Metadata.created }) |
            Where-Object { $_ } |
            Sort-Object |
            Select-Object -First 1

        [PSCustomObject]@{
            PSTypeName  = 'Fwm.RuleSet'
            SetName     = $group.Name
            Group       = $entries[0].Rule.Group
            Root        = $entries[0].Metadata.root
            RuleCount   = $rules.Count
            Inbound     = @($entries | Where-Object { $_.Metadata.dir -eq 'Inbound' }).Count
            Outbound    = @($entries | Where-Object { $_.Metadata.dir -eq 'Outbound' }).Count
            # Un ensemble est considere actif seulement si toutes ses regles
            # le sont : un ensemble partiellement desactive ne protege plus.
            Enabled     = @($rules | Where-Object { "$($_.Enabled)" -ne 'True' }).Count -eq 0
            Created     = $created
            Executables = @($entries | ForEach-Object { $_.Metadata.exe } | Sort-Object -Unique)
            Rules       = $rules
        }
    }
}
