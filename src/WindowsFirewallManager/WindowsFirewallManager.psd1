@{
    RootModule           = 'WindowsFirewallManager.psm1'
    FormatsToProcess     = @('WindowsFirewallManager.format.ps1xml')
    ModuleVersion        = '0.1.0'
    GUID                 = '61c9d2f3-c098-4ab8-95ab-e984ab68f276'
    Author               = 'Ranak4n'
    Copyright            = '(c) 2026 Ranak4n. Distribue sous licence MIT.'
    Description          = 'Gestion d''ensembles de regles de blocage du pare-feu Windows : bloque tous les executables d''un logiciel en entrant et sortant, et permet de les retirer en bloc.'

    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport    = @(
        'New-FwmRuleSet',
        'Get-FwmRuleSet',
        'Remove-FwmRuleSet',
        'Get-FwmExecutable',
        'Test-FwmElevation'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags         = @('Firewall', 'Security', 'Windows', 'NetSecurity')
            LicenseUri   = 'https://github.com/Ranak4n/Windows-Firewall-ManagerPS/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/Ranak4n/Windows-Firewall-ManagerPS'
            ReleaseNotes = 'Version initiale du moteur : creation, inventaire et suppression d''ensembles de regles.'
        }
    }
}
