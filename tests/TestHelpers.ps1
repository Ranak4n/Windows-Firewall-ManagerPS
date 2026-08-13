# Utilitaires partages par les tests. Ce fichier n'est pas un fichier de test
# (pas de suffixe .Tests.ps1) : il est dot-source depuis les BeforeAll.

function Get-ModuleManifestPath {
    return (Join-Path $PSScriptRoot '..\src\WindowsFirewallManager\WindowsFirewallManager.psd1')
}

function New-FwmTestDescription {
    <#
        Reproduit le format produit par ConvertTo-FwmDescription sans passer
        par le module : les tests de lecture doivent valider le contrat de
        format, pas se contenter d'un aller-retour avec leur propre code.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Fabrique de test : construit une chaine, aucun effet de bord.')]
    param(
        [string]$SetName = 'Demo',
        [string]$Root = 'C:\Apps\Demo',
        [string]$ExecutablePath = 'C:\Apps\Demo\demo.exe',
        [ValidateSet('Inbound', 'Outbound')][string]$Direction = 'Outbound',
        [string]$Created = '2026-01-15T10:00:00.0000000Z',
        [int]$Version = 1
    )

    $json = '{{"v":{0},"set":"{1}","root":"{2}","exe":"{3}","dir":"{4}","created":"{5}"}}' -f @(
        $Version
        $SetName
        $Root.Replace('\', '\\')
        $ExecutablePath.Replace('\', '\\')
        $Direction
        $Created
    )

    return "Blocage de test. [FWM]$json[/FWM]"
}

function New-FakeFirewallRule {
    <#
        Imite la forme d'un objet retourne par Get-NetFirewallRule, limitee
        aux proprietes que le module consulte reellement.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Fabrique de test : construit un objet en memoire.')]
    param(
        [string]$Name = [guid]::NewGuid().ToString(),
        [string]$DisplayName = 'Regle de test',
        [string]$Description = '',
        [string]$Group = '*FWM - Demo',
        [string]$Direction = 'Outbound',
        [string]$Enabled = 'True'
    )

    return [PSCustomObject]@{
        Name        = $Name
        DisplayName = $DisplayName
        Description = $Description
        Group       = $Group
        Direction   = $Direction
        Enabled     = $Enabled
    }
}

function New-TestExecutable {
    <#
        Cree des fichiers .exe vides dans un dossier temporaire et retourne
        le chemin du dossier.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Fabrique de test : ecrit uniquement dans le TestDrive de Pester.')]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$Name = @('app.exe')
    )

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    foreach ($file in $Name) {
        $full = Join-Path $Path $file
        New-Item -ItemType Directory -Path (Split-Path $full -Parent) -Force | Out-Null
        # New-Item plutot que Set-Content : le contenu n'a aucune importance,
        # et -Encoding Byte n'existe plus depuis PowerShell 6.
        New-Item -ItemType File -Path $full -Force | Out-Null
    }

    return $Path
}
