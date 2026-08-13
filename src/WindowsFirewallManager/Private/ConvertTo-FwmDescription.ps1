function ConvertTo-FwmDescription {
    <#
    .SYNOPSIS
        Construit la description d'une regle : texte lisible + metadonnees.

    .DESCRIPTION
        La description d'une regle de pare-feu est un champ libre que personne
        d'autre n'exploite. On y inscrit un bloc JSON encadre de marqueurs
        [FWM]...[/FWM], ce qui permet ensuite d'identifier nos regles avec
        certitude, de retrouver le dossier d'origine, et de resynchroniser un
        ensemble apres mise a jour du logiciel.

        Le texte lisible precede le bloc pour que la description reste
        comprehensible dans wf.msc.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$SetName,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ExecutablePath,
        [Parameter(Mandatory)][ValidateSet('Inbound', 'Outbound')][string]$Direction,
        [datetime]$Created = [datetime]::UtcNow
    )

    $metadata = [ordered]@{
        v       = $script:FwmSchemaVersion
        set     = $SetName
        root    = $Root
        exe     = $ExecutablePath
        dir     = $Direction
        created = $Created.ToUniversalTime().ToString('o')
    }

    $json = ConvertTo-Json -InputObject $metadata -Compress
    $sens = if ($Direction -eq 'Inbound') { 'entrant' } else { 'sortant' }
    $human = "Blocage $sens de $(Split-Path -Path $ExecutablePath -Leaf) (ensemble '$SetName'). Cree par Windows Firewall Manager."

    # Separateur espace et non retour ligne : le champ transite par CIM, on
    # evite tout caractere de controle.
    return "$human [FWM]$json[/FWM]"
}
