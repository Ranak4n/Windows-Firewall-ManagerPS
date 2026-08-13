function Get-FwmExecutable {
    <#
    .SYNOPSIS
        Liste les executables d'un dossier.

    .DESCRIPTION
        Retourne les fichiers .exe du dossier et, par defaut, de ses
        sous-dossiers.

        ATTENTION : comme toute fonction PowerShell, la sortie est deroulee.
        Zero resultat sort en $null et un resultat sort en scalaire. Les
        appelants doivent encadrer l'appel de @(...) avant de lire .Count ou
        d'iterer dessus.

    .PARAMETER Path
        Dossier a parcourir.

    .PARAMETER NoRecurse
        Limite la recherche au premier niveau.

    .EXAMPLE
        $exes = @(Get-FwmExecutable -Path 'C:\Program Files\Mon Logiciel')
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [switch]$NoRecurse
    )

    process {
        # -LiteralPath : un dossier nomme "Game [2024]" ne doit pas etre
        # interprete comme une classe de caracteres.
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            throw "Dossier introuvable : $Path"
        }

        $resolved = (Resolve-Path -LiteralPath $Path).Path

        $params = @{
            LiteralPath = $resolved
            File        = $true
            # -Filter est traite par le systeme de fichiers : nettement plus
            # rapide que -Include sur une arborescence profonde.
            Filter      = '*.exe'
            ErrorAction = 'SilentlyContinue'
        }
        if (-not $NoRecurse) { $params['Recurse'] = $true }

        Get-ChildItem @params
    }
}
