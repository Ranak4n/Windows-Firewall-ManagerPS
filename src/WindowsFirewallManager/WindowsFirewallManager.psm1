Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Constantes du module
# ---------------------------------------------------------------------------

# Version du schema de metadonnees inscrit dans la description des regles.
# A incrementer si la structure change, pour pouvoir migrer l'existant.
$script:FwmSchemaVersion = 1

# Le '*' initial n'est pas decoratif : il fait remonter nos groupes en tete
# du tri alphabetique dans wf.msc.
$script:FwmGroupPrefix = '*FWM - '

# Les metadonnees sont encadrees par des marqueurs pour cohabiter avec un
# texte lisible par un humain dans la meme description.
$script:FwmMetadataRegex = '\[FWM\](?<json>.+?)\[/FWM\]'

# ---------------------------------------------------------------------------
# Chargement des fonctions
# ---------------------------------------------------------------------------

$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$public = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in @($private + $public)) {
    try {
        . $file.FullName
    }
    catch {
        throw "Impossible de charger $($file.FullName) : $_"
    }
}

Export-ModuleMember -Function $public.BaseName
