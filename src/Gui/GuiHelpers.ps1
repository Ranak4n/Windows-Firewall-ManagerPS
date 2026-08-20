<#
    Fonctions de presentation pures, sans effet de bord ni dependance a WPF.

    Isolees dans ce fichier pour etre testables : dot-sourcer Start-FwmGui.ps1
    lancerait la fenetre, ce qui interdit de tester les fonctions qu'il
    contient.
#>

function Format-FwmSize {
    <#
    .SYNOPSIS
        Met en forme une taille en octets.

    .EXAMPLE
        Format-FwmSize -Bytes 1258291   # -> 1,2 Mo
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [long]$Bytes
    )

    if ($Bytes -ge 1GB) { return '{0:N1} Go' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} Mo' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N0} Ko' -f ($Bytes / 1KB) }
    return "$Bytes o"
}

function Format-FwmCount {
    <#
    .SYNOPSIS
        Accorde un nom et son participe selon le nombre, en francais.

    .DESCRIPTION
        En francais, zero commande le singulier : « 0 exécutable sélectionné »
        et non « 0 exécutables sélectionnés ». C'est la difference avec
        l'anglais, ou seul 1 est singulier.

    .EXAMPLE
        Format-FwmCount -Count 1 -Singular 'règle créée' -Plural 'règles créées'
        # -> 1 règle créée

    .EXAMPLE
        Format-FwmCount -Count 0 -Singular 'ensemble' -Plural 'ensembles'
        # -> 0 ensemble
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [int]$Count,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$Singular,

        [Parameter(Mandatory, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string]$Plural
    )

    # Les nombres negatifs ne devraient pas survenir, mais s'ils survenaient
    # le pluriel serait plus juste que le singulier (-2 éléments).
    $word = if ($Count -eq 1 -or $Count -eq 0 -or $Count -eq -1) { $Singular } else { $Plural }
    return "$Count $word"
}

function Format-FwmRelativePath {
    <#
    .SYNOPSIS
        Exprime un chemin relativement a un dossier racine.

    .DESCRIPTION
        Retourne le chemin complet inchange si celui-ci ne se trouve pas sous
        la racine indiquee.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)][string]$FullPath,
        [Parameter(Mandatory, Position = 1)][string]$Root
    )

    $normalizedRoot = $Root.TrimEnd('\')

    if ($FullPath.StartsWith($normalizedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        return $FullPath.Substring($normalizedRoot.Length).TrimStart('\')
    }

    return $FullPath
}
