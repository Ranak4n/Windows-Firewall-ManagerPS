[CmdletBinding()]
param()

Set-StrictMode -Version Latest

function Show-Banner {
    Write-Host "============================================"
    Write-Host "   Outil de gestion des regles pare-feu"
    Write-Host "============================================"
    Write-Host ""
}

function Read-MenuChoice {
    Write-Host "1 - Ajouter des regles entrantes"
    Write-Host "2 - Ajouter des regles sortantes"
    Write-Host "3 - Ajouter regles entrantes et sortantes"
    Write-Host "4 - Supprimer un groupe et ses regles"
    Write-Host "5 - Quitter"
    return (Read-Host "Votre choix (1-5)")
}

function Prompt-FolderPath {
    while ($true) {
        $path = Read-Host "Dossier contenant les executables (.exe)"
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }

        if (-not (Test-Path -Path $path)) {
            Write-Host "Dossier introuvable. Merci de reessayer." -ForegroundColor Yellow
            continue
        }

        return (Resolve-Path -Path $path).Path
    }
}

function Prompt-RuleGroup {
    $group = Read-Host "Nom du groupe de regles (defaut: *CustomBlock)"
    if ([string]::IsNullOrWhiteSpace($group)) {
        $group = "*CustomBlock"
    }
    return $group
}

function Get-ExecutablesFromFolder {
    param(
        [Parameter(Mandatory = $true)][string]$FolderPath
    )

    try {
        return Get-ChildItem -Path $FolderPath -Recurse -Include *.exe -File -ErrorAction Stop
    }
    catch {
        Write-Host "Erreur lors du parcours du dossier: $_" -ForegroundColor Red
        return @()
    }
}

function New-BlockRuleForExe {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$Executable,
        [Parameter(Mandatory = $true)][string]$Group,
        [Parameter(Mandatory = $true)][ValidateSet("Inbound", "Outbound")][string]$Direction,
        [Parameter(Mandatory = $true)][bool]$UseDirectionalSuffix
    )

    $baseName = "*Block - $($Executable.Name)"
    $displayName = if ($UseDirectionalSuffix) { "$baseName ($Direction)" } else { $baseName }

    $existing = Get-NetFirewallRule -DisplayName $displayName -ErrorAction SilentlyContinue |
        Where-Object { $_.Direction -eq $Direction }

    if ($existing) {
        Write-Host "Deja present: $displayName" -ForegroundColor Yellow
        return
    }

    try {
        New-NetFirewallRule `
            -DisplayName $displayName `
            -Direction $Direction `
            -Program $Executable.FullName `
            -Action Block `
            -Profile Any `
            -Group $Group | Out-Null

        Write-Host "Ajoute: $displayName -> $($Executable.FullName)" -ForegroundColor Green
    }
    catch {
        Write-Host "Echec pour $displayName : $_" -ForegroundColor Red
    }
}

function Invoke-RuleCreation {
    param(
        [Parameter(Mandatory = $true)][string[]]$Directions
    )

    $folder = Prompt-FolderPath
    $group = Prompt-RuleGroup

    $executables = Get-ExecutablesFromFolder -FolderPath $folder
    if (-not $executables.Count) {
        Write-Host "Aucun executable trouve dans $folder" -ForegroundColor Yellow
        return
    }

    $useSuffix = $Directions.Count -gt 1
    Write-Host ""
    Write-Host "Creation des regles pour $($executables.Count) executable(s)" -ForegroundColor Cyan
    Write-Host "Dossier : $folder"
    Write-Host "Groupe  : $group"
    Write-Host ""

    foreach ($exe in $executables) {
        foreach ($direction in $Directions) {
            New-BlockRuleForExe -Executable $exe -Group $group -Direction $direction -UseDirectionalSuffix:$useSuffix
        }
    }
}

function Remove-RuleGroup {
    $group = Read-Host "Nom du groupe a supprimer"
    if ([string]::IsNullOrWhiteSpace($group)) {
        Write-Host "Nom de groupe requis." -ForegroundColor Yellow
        return
    }

    $rules = Get-NetFirewallRule -Group $group -ErrorAction SilentlyContinue
    if (-not $rules) {
        Write-Host "Aucune regle trouvee dans le groupe $group" -ForegroundColor Yellow
        return
    }

    Write-Host "Suppression de $($rules.Count) regle(s) dans le groupe $group" -ForegroundColor Cyan
    try {
        Remove-NetFirewallRule -Group $group -Confirm:$false
        Write-Host "Groupe supprime." -ForegroundColor Green
    }
    catch {
        Write-Host "Echec de la suppression : $_" -ForegroundColor Red
    }
}

do {
    Show-Banner
    $choice = Read-MenuChoice
    Write-Host ""

    switch ($choice) {
        '1' { Invoke-RuleCreation -Directions @('Inbound') }
        '2' { Invoke-RuleCreation -Directions @('Outbound') }
        '3' { Invoke-RuleCreation -Directions @('Inbound', 'Outbound') }
        '4' { Remove-RuleGroup }
        '5' { break }
        default { Write-Host "Choix invalide, merci de reessayer." -ForegroundColor Yellow }
    }

    if ($choice -ne '5') {
        Write-Host ""
        Read-Host "Appuyez sur Entree pour revenir au menu"
    }
}
while ($true)

Write-Host "Fin de l'outil." -ForegroundColor Cyan
