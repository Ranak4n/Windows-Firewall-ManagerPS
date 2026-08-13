function ConvertFrom-FwmDescription {
    <#
    .SYNOPSIS
        Extrait les metadonnees FWM d'une description de regle.

    .DESCRIPTION
        Retourne $null si la description ne provient pas de cet outil, si le
        bloc est absent, illisible, ou incomplet. C'est ce qui garantit qu'on
        ne touche jamais a une regle creee par quelqu'un d'autre.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Description
    )

    if ([string]::IsNullOrWhiteSpace($Description)) { return $null }

    $match = [regex]::Match($Description, $script:FwmMetadataRegex)
    if (-not $match.Success) { return $null }

    try {
        $metadata = $match.Groups['json'].Value | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Verbose "Bloc de metadonnees FWM illisible, regle ignoree : $_"
        return $null
    }

    # Une regle dont le schema est incomplet est traitee comme etrangere :
    # mieux vaut l'ignorer que de la manipuler sur des donnees partielles.
    $properties = $metadata.PSObject.Properties.Name
    foreach ($required in @('v', 'set', 'exe', 'dir')) {
        if ($properties -notcontains $required) {
            Write-Verbose "Metadonnees FWM incompletes (champ '$required' absent), regle ignoree."
            return $null
        }
    }

    return $metadata
}
