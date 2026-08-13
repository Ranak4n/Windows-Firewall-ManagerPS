function Test-FwmElevation {
    <#
    .SYNOPSIS
        Indique si la session courante dispose des droits administrateur.

    .DESCRIPTION
        Toute modification de regle pare-feu les exige. La lecture, elle,
        fonctionne sans elevation : Get-FwmRuleSet est utilisable tel quel.

    .EXAMPLE
        if (-not (Test-FwmElevation)) { throw 'Droits administrateur requis.' }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity

    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
