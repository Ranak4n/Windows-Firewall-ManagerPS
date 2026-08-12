#Requires -Version 5.1
<#
.SYNOPSIS
    Outil interactif de blocage de logiciels dans le pare-feu Windows.

.DESCRIPTION
    Parcourt un dossier, y detecte les executables, et cree une regle de
    blocage (entrante et/ou sortante) pour chacun, regroupees sous un nom
    de groupe commun pour pouvoir les gerer en bloc.

    NOTE : version CLI transitoire. Le moteur sera extrait en module et
    l'interface passera en WPF. Voir README.md.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Elevation
# ---------------------------------------------------------------------------

function Test-Elevation {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Elevation {
    if (Test-Elevation) { return }

    Write-Host ""
    Write-Host "Droits administrateur requis pour modifier les regles du pare-feu." -ForegroundColor Yellow
    Write-Host "Relancez via Start-Scripts.cmd, ou acceptez l'elevation ci-dessous."
    Write-Host ""

    $answer = Read-Host "Relancer en tant qu'administrateur ? (O/n)"
    if ($answer -match '^(n|no|non)$') {
        Write-Host "Abandon." -ForegroundColor Yellow
        exit 1
    }

    $exe = (Get-Process -Id $PID).Path
    try {
        Start-Process -FilePath $exe `
            -Verb RunAs `
            -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath
    }
    catch {
        Write-Host "Elevation refusee ou impossible : $_" -ForegroundColor Red
        exit 1
    }
    exit 0
}

# ---------------------------------------------------------------------------
# Affichage
# ---------------------------------------------------------------------------

function Show-Banner {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "   Outil de gestion des regles pare-feu" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Read-MenuChoice {
    Write-Host "1 - Ajouter des regles entrantes"
    Write-Host "2 - Ajouter des regles sortantes"
    Write-Host "3 - Ajouter regles entrantes et sortantes"
    Write-Host "4 - Supprimer un groupe et ses regles"
    Write-Host "5 - Quitter"
    Write-Host ""
    return (Read-Host "Votre choix (1-5)")
}

# ---------------------------------------------------------------------------
# Saisies
# ---------------------------------------------------------------------------

function Read-FolderPath {
    while ($true) {
        $path = Read-Host "Dossier contenant les executables (.exe)"

        if ([string]::IsNullOrWhiteSpace($path)) { continue }

        # "Copier en tant que chemin" de l'Explorateur entoure de guillemets.
        $path = $path.Trim().Trim('"')

        # -LiteralPath : un dossier nomme "Game [2024]" ne doit pas etre
        # interprete comme un motif de caracteres.
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            Write-Host "Dossier introuvable. Merci de reessayer." -ForegroundColor Yellow
            continue
        }

        return (Resolve-Path -LiteralPath $path).Path
    }
}

function Read-RuleGroupName {
    while ($true) {
        $group = Read-Host "Nom du groupe de regles (defaut: *CustomBlock)"

        if ([string]::IsNullOrWhiteSpace($group)) { return '*CustomBlock' }

        $group = $group.Trim()

        # Le '*' initial est une convention de tri (remonte le groupe en tete
        # dans wf.msc). Tout autre wildcard rendrait le groupe impossible a
        # cibler sans ambiguite lors de la suppression.
        $rest = if ($group.StartsWith('*')) { $group.Substring(1) } else { $group }
        if ($rest -match '[*?\[\]]') {
            Write-Host "Caracteres * ? [ ] interdits (hors '*' initial) : ils rendraient" -ForegroundColor Yellow
            Write-Host "la suppression ambigue. Merci de choisir un autre nom." -ForegroundColor Yellow
            continue
        }

        return $group
    }
}

# ---------------------------------------------------------------------------
# Pare-feu
# ---------------------------------------------------------------------------

function Get-ExecutableFromFolder {
    param(
        [Parameter(Mandatory)][string]$FolderPath
    )

    try {
        # -Filter est nettement plus rapide que -Include et ne souffre pas de
        # ses effets de bord sur le premier niveau de l'arborescence.
        return @(Get-ChildItem -LiteralPath $FolderPath -Recurse -File -Filter '*.exe' -ErrorAction SilentlyContinue)
    }
    catch {
        Write-Host "Erreur lors du parcours du dossier : $_" -ForegroundColor Red
        return @()
    }
}

function Get-RuleByGroupLiteral {
    param(
        [Parameter(Mandatory)][string]$Group
    )

    # -Group interprete les wildcards cote pare-feu : passer "*" y supprimerait
    # des centaines de regles systeme. On recupere tout et on filtre en -eq.
    return @(Get-NetFirewallRule -ErrorAction SilentlyContinue |
        Where-Object { $_.Group -eq $Group })
}

function New-BlockRuleForExe {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$Executable,
        [Parameter(Mandatory)][string]$Group,
        [Parameter(Mandatory)][ValidateSet('Inbound', 'Outbound')][string]$Direction
    )

    # Le nom du groupe fait partie du DisplayName : sans lui, deux logiciels
    # possedant chacun un "updater.exe" entrent en collision et le second
    # n'est jamais bloque.
    $short = if ($Direction -eq 'Inbound') { 'In' } else { 'Out' }
    $displayName = "$Group - $($Executable.Name) ($short)"

    $existing = Get-NetFirewallRule -DisplayName $displayName -ErrorAction SilentlyContinue |
        Where-Object { $_.Direction -eq $Direction }

    if ($existing) {
        Write-Host "  Deja present : $displayName" -ForegroundColor DarkGray
        return 'Skipped'
    }

    try {
        New-NetFirewallRule `
            -DisplayName $displayName `
            -Direction $Direction `
            -Program $Executable.FullName `
            -Action Block `
            -Profile Any `
            -Group $Group `
            -ErrorAction Stop | Out-Null

        Write-Host "  Ajoute       : $displayName" -ForegroundColor Green
        return 'Created'
    }
    catch {
        Write-Host "  Echec        : $displayName -> $_" -ForegroundColor Red
        return 'Failed'
    }
}

function Invoke-RuleCreation {
    param(
        [Parameter(Mandatory)][string[]]$Directions
    )

    $folder = Read-FolderPath
    $group = Read-RuleGroupName

    $executables = Get-ExecutableFromFolder -FolderPath $folder
    if ($executables.Count -eq 0) {
        Write-Host "Aucun executable trouve dans $folder" -ForegroundColor Yellow
        return
    }

    $total = $executables.Count * $Directions.Count

    Write-Host ""
    Write-Host "Dossier    : $folder"
    Write-Host "Groupe     : $group"
    Write-Host "Executables: $($executables.Count)"
    Write-Host "Sens       : $($Directions -join ', ')"
    Write-Host "Regles a creer : $total" -ForegroundColor Cyan
    Write-Host ""

    $confirm = Read-Host "Confirmer la creation ? (O/n)"
    if ($confirm -match '^(n|no|non)$') {
        Write-Host "Annule." -ForegroundColor Yellow
        return
    }
    Write-Host ""

    $stats = @{ Created = 0; Skipped = 0; Failed = 0 }

    foreach ($exe in $executables) {
        Write-Host "$($exe.Name)" -ForegroundColor White
        foreach ($direction in $Directions) {
            $result = New-BlockRuleForExe -Executable $exe -Group $group -Direction $direction
            $stats[$result]++
        }
    }

    Write-Host ""
    Write-Host "Termine : $($stats.Created) creee(s), $($stats.Skipped) ignoree(s), $($stats.Failed) en echec." -ForegroundColor Cyan
}

function Remove-RuleGroupInteractive {
    Write-Host "Lecture des regles existantes..." -ForegroundColor DarkGray

    # On ne propose que les groupes crees par cet outil : ceux commencant par
    # '*'. Impossible de designer accidentellement un groupe systeme.
    $groups = @(Get-NetFirewallRule -ErrorAction SilentlyContinue |
        Where-Object { $_.Group -and $_.Group.StartsWith('*') } |
        Group-Object -Property Group |
        Sort-Object -Property Name)

    if ($groups.Count -eq 0) {
        Write-Host "Aucun groupe personnalise trouve." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "Groupes personnalises :" -ForegroundColor Cyan
    for ($i = 0; $i -lt $groups.Count; $i++) {
        "{0,3} - {1}  ({2} regle(s))" -f ($i + 1), $groups[$i].Name, $groups[$i].Count | Write-Host
    }
    Write-Host "  0 - Annuler"
    Write-Host ""

    $answer = Read-Host "Groupe a supprimer (numero)"

    [int]$index = 0
    if (-not [int]::TryParse($answer, [ref]$index) -or $index -lt 0 -or $index -gt $groups.Count) {
        Write-Host "Choix invalide." -ForegroundColor Yellow
        return
    }
    if ($index -eq 0) {
        Write-Host "Annule." -ForegroundColor Yellow
        return
    }

    $target = $groups[$index - 1]
    $rules = @($target.Group)

    Write-Host ""
    Write-Host "$($rules.Count) regle(s) seront supprimees du groupe '$($target.Name)' :" -ForegroundColor Yellow
    $rules | Select-Object -First 10 | ForEach-Object { Write-Host "  $($_.DisplayName)" }
    if ($rules.Count -gt 10) {
        Write-Host "  ... et $($rules.Count - 10) autre(s)"
    }
    Write-Host ""

    $confirm = Read-Host "Confirmer la suppression ? (o/N)"
    if ($confirm -notmatch '^(o|oui|y|yes)$') {
        Write-Host "Annule." -ForegroundColor Yellow
        return
    }

    $removed = 0
    $failed = 0
    foreach ($rule in $rules) {
        try {
            # Suppression par -Name (identifiant unique de la regle) et non
            # par -Group : aucune interpretation de wildcard possible.
            Remove-NetFirewallRule -Name $rule.Name -ErrorAction Stop
            $removed++
        }
        catch {
            Write-Host "  Echec : $($rule.DisplayName) -> $_" -ForegroundColor Red
            $failed++
        }
    }

    Write-Host ""
    Write-Host "Termine : $removed supprimee(s), $failed en echec." -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# Boucle principale
# ---------------------------------------------------------------------------

Assert-Elevation

$running = $true
while ($running) {
    Show-Banner
    $choice = Read-MenuChoice
    Write-Host ""

    try {
        switch ($choice) {
            '1' { Invoke-RuleCreation -Directions @('Inbound') }
            '2' { Invoke-RuleCreation -Directions @('Outbound') }
            '3' { Invoke-RuleCreation -Directions @('Inbound', 'Outbound') }
            '4' { Remove-RuleGroupInteractive }
            # Un 'break' ici sortirait du switch, pas de la boucle : c'est
            # exactement ce qui empechait le script de se terminer.
            '5' { $running = $false }
            default { Write-Host "Choix invalide, merci de reessayer." -ForegroundColor Yellow }
        }
    }
    catch {
        Write-Host "Erreur inattendue : $_" -ForegroundColor Red
    }

    if ($running) {
        Write-Host ""
        Read-Host "Appuyez sur Entree pour revenir au menu" | Out-Null
    }
}

Write-Host ""
Write-Host "Fin de l'outil." -ForegroundColor Cyan
