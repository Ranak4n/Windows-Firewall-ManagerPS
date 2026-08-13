function Resolve-FwmGroupName {
    <#
    .SYNOPSIS
        Valide un nom d'ensemble et retourne le nom de groupe pare-feu associe.

    .DESCRIPTION
        Les caracteres generiques sont refuses : les cmdlets NetSecurity les
        interpretent cote pare-feu, et un nom contenant '*' rendrait le groupe
        impossible a cibler sans ambiguite. Verifie : 'Get-NetFirewallRule
        -Group *' remonte la quasi-totalite des regles de la machine.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SetName
    )

    $trimmed = $SetName.Trim()

    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw "Le nom de l'ensemble ne peut pas etre vide."
    }

    if ($trimmed -match '[*?\[\]]') {
        throw "Le nom de l'ensemble ne peut pas contenir les caracteres * ? [ ] : ils seraient interpretes comme des caracteres generiques par le pare-feu."
    }

    if ($trimmed.Length -gt 64) {
        throw "Le nom de l'ensemble est limite a 64 caracteres (recu : $($trimmed.Length))."
    }

    return "$script:FwmGroupPrefix$trimmed"
}
