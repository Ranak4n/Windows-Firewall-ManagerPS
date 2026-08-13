#Requires -Version 7.0
<#
.SYNOPSIS
    Interface graphique de Windows Firewall Manager.

.DESCRIPTION
    Coquille WPF au-dessus du module WindowsFirewallManager : toute la logique
    metier reste dans le module, ce fichier ne fait qu'afficher et collecter.

    PowerShell 7 est requis : la fenetre a besoin d'un thread STA (que pwsh
    fournit par defaut) et le selecteur de dossier moderne n'existe qu'a
    partir de .NET 8.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$moduleManifest = Join-Path $PSScriptRoot '..\WindowsFirewallManager\WindowsFirewallManager.psd1'
Import-Module $moduleManifest -Force

# ---------------------------------------------------------------------------
# Types de liaison
#
# WPF lie mal les PSCustomObject : on passe par de vraies classes. Seule
# FwmExeItem implemente INotifyPropertyChanged, pour que "Tout cocher"
# se repercute sur les cases affichees.
# ---------------------------------------------------------------------------

if (-not ('FwmExeItem' -as [type])) {
    Add-Type -TypeDefinition @'
using System.ComponentModel;

public class FwmExeItem : INotifyPropertyChanged
{
    private bool _selected = true;

    public bool Selected
    {
        get { return _selected; }
        set
        {
            if (_selected != value)
            {
                _selected = value;
                OnPropertyChanged("Selected");
            }
        }
    }

    public string Name { get; set; }
    public string FullName { get; set; }
    public string SizeText { get; set; }
    public string RelativePath { get; set; }

    public event PropertyChangedEventHandler PropertyChanged;

    protected void OnPropertyChanged(string propertyName)
    {
        PropertyChangedEventHandler handler = PropertyChanged;
        if (handler != null)
        {
            handler(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}

public class FwmSetItem
{
    public string SetName { get; set; }
    public int RuleCount { get; set; }
    public int Inbound { get; set; }
    public int Outbound { get; set; }
    public string StateText { get; set; }
    public string Root { get; set; }
}
'@
}

# ---------------------------------------------------------------------------
# Utilitaires
# ---------------------------------------------------------------------------

function Import-FwmXaml {
    param([Parameter(Mandatory)][string]$FileName)

    $path = Join-Path $PSScriptRoot $FileName
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Fichier d'interface introuvable : $path"
    }

    $xaml = Get-Content -LiteralPath $path -Raw
    return [System.Windows.Markup.XamlReader]::Parse($xaml)
}

function Invoke-FwmUiRefresh {
    <#
        Force un rafraichissement immediat de la fenetre. Les operations sur
        le pare-feu sont synchrones : sans cela l'utilisateur ne verrait pas
        le message d'attente avant le gel de quelques secondes.
    #>
    param([Parameter(Mandatory)]$Window)

    $Window.Dispatcher.Invoke(
        [action] {},
        [System.Windows.Threading.DispatcherPriority]::Render
    )
}

function Select-FwmFolder {
    param([string]$Title = 'Choisissez le dossier du logiciel')

    # OpenFolderDialog (.NET 8+) est le selecteur moderne de Windows.
    if ('Microsoft.Win32.OpenFolderDialog' -as [type]) {
        $dialog = New-Object Microsoft.Win32.OpenFolderDialog
        $dialog.Title = $Title
        if ($dialog.ShowDialog()) { return $dialog.FolderName }
        return $null
    }

    # Repli pour les runtimes plus anciens : l'arborescence WinForms.
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Title
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

function Format-FwmSize {
    param([long]$Bytes)

    if ($Bytes -ge 1GB) { return '{0:N1} Go' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} Mo' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N0} Ko' -f ($Bytes / 1KB) }
    return "$Bytes o"
}

function Show-FwmMessage {
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$Title = 'Windows Firewall Manager',
        [ValidateSet('Info', 'Warning', 'Error')][string]$Icon = 'Info',
        $Owner
    )

    $image = switch ($Icon) {
        'Warning' { [System.Windows.MessageBoxImage]::Warning }
        'Error' { [System.Windows.MessageBoxImage]::Error }
        default { [System.Windows.MessageBoxImage]::Information }
    }

    if ($Owner) {
        return [System.Windows.MessageBox]::Show($Owner, $Text, $Title, [System.Windows.MessageBoxButton]::OK, $image)
    }
    return [System.Windows.MessageBox]::Show($Text, $Title, [System.Windows.MessageBoxButton]::OK, $image)
}

# ---------------------------------------------------------------------------
# Fenetre "Nouveau blocage"
# ---------------------------------------------------------------------------

function Show-FwmNewRuleSetDialog {
    param($Owner)

    $window = Import-FwmXaml -FileName 'NewRuleSetDialog.xaml'
    $window.Owner = $Owner

    $txtFolder = $window.FindName('TxtFolder')
    $btnBrowse = $window.FindName('BtnBrowse')
    $txtSetName = $window.FindName('TxtSetName')
    $txtGroupPreview = $window.FindName('TxtGroupPreview')
    $cmbDirection = $window.FindName('CmbDirection')
    $lstExes = $window.FindName('LstExes')
    $btnCheckAll = $window.FindName('BtnCheckAll')
    $btnUncheckAll = $window.FindName('BtnUncheckAll')
    $txtSummary = $window.FindName('TxtSummary')
    $btnCreate = $window.FindName('BtnCreate')
    $btnCancel = $window.FindName('BtnCancel')

    # Etat partage entre les gestionnaires d'evenements.
    $state = [PSCustomObject]@{
        Items  = New-Object System.Collections.ObjectModel.ObservableCollection[FwmExeItem]
        Root   = $null
        Result = $null
    }
    $lstExes.ItemsSource = $state.Items

    $updateSummary = {
        $selected = @($state.Items | Where-Object { $_.Selected }).Count
        $perExe = if ($cmbDirection.SelectedIndex -eq 0) { 2 } else { 1 }
        $rules = $selected * $perExe

        $name = $txtSetName.Text.Trim()
        $txtGroupPreview.Text = if ($name) { "Groupe pare-feu : *FWM - $name" } else { 'Groupe pare-feu : *FWM - ...' }

        if ($state.Items.Count -eq 0) {
            $txtSummary.Text = 'Choisissez un dossier pour commencer.'
        }
        else {
            $txtSummary.Text = "$selected executable(s) selectionne(s) sur $($state.Items.Count) -> $rules regle(s) a creer."
        }

        $btnCreate.IsEnabled = ($selected -gt 0 -and $name.Length -gt 0)
    }.GetNewClosure()

    $loadFolder = {
        param([string]$Path)

        if ([string]::IsNullOrWhiteSpace($Path)) { return }

        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            Show-FwmMessage -Text "Dossier introuvable :`n$Path" -Icon Warning -Owner $window
            return
        }

        $state.Items.Clear()
        $resolved = (Resolve-Path -LiteralPath $Path).Path
        $state.Root = $resolved
        $txtFolder.Text = $resolved

        # @() indispensable : la sortie d'une fonction est deroulee, zero
        # executable donnerait $null.
        $exes = @(Get-FwmExecutable -Path $resolved)

        foreach ($exe in ($exes | Sort-Object FullName)) {
            $item = [FwmExeItem]::new()
            $item.Selected = $true
            $item.Name = $exe.Name
            $item.FullName = $exe.FullName
            $item.SizeText = Format-FwmSize -Bytes $exe.Length

            $relative = $exe.FullName
            if ($relative.StartsWith($resolved, [StringComparison]::OrdinalIgnoreCase)) {
                $relative = $relative.Substring($resolved.Length).TrimStart('\')
            }
            $item.RelativePath = $relative

            $state.Items.Add($item)
        }

        if ($state.Items.Count -eq 0) {
            Show-FwmMessage -Text "Aucun executable trouve dans :`n$resolved`n`nSous-dossiers inclus." -Icon Warning -Owner $window
        }

        # Propose le nom du dossier comme nom d'ensemble, sans ecraser une
        # saisie deja faite par l'utilisateur.
        if ([string]::IsNullOrWhiteSpace($txtSetName.Text)) {
            $suggestion = (Split-Path -Path $resolved -Leaf) -replace '[*?\[\]]', ''
            $txtSetName.Text = $suggestion
        }

        & $updateSummary
    }.GetNewClosure()

    $btnBrowse.Add_Click({
            $folder = Select-FwmFolder
            if ($folder) { & $loadFolder $folder }
        }.GetNewClosure())

    # Permet aussi de coller un chemin directement dans le champ.
    $txtFolder.Add_LostFocus({
            $typed = $txtFolder.Text.Trim().Trim('"')
            if ($typed -and $typed -ne $state.Root) { & $loadFolder $typed }
        }.GetNewClosure())

    $txtSetName.Add_TextChanged({ & $updateSummary }.GetNewClosure())
    $cmbDirection.Add_SelectionChanged({ & $updateSummary }.GetNewClosure())

    # Les cases a cocher modifient l'objet lie ; on rafraichit le decompte
    # au relachement de la souris sur la liste.
    $lstExes.Add_PreviewMouseLeftButtonUp({ & $updateSummary }.GetNewClosure())

    $btnCheckAll.Add_Click({
            foreach ($item in $state.Items) { $item.Selected = $true }
            & $updateSummary
        }.GetNewClosure())

    $btnUncheckAll.Add_Click({
            foreach ($item in $state.Items) { $item.Selected = $false }
            & $updateSummary
        }.GetNewClosure())

    $btnCancel.Add_Click({ $window.DialogResult = $false }.GetNewClosure())

    $btnCreate.Add_Click({
            $setName = $txtSetName.Text.Trim()
            $chosen = @($state.Items | Where-Object { $_.Selected })

            if ($chosen.Count -eq 0) {
                Show-FwmMessage -Text 'Aucun executable selectionne.' -Icon Warning -Owner $window
                return
            }

            $direction = switch ($cmbDirection.SelectedIndex) {
                1 { 'Outbound' }
                2 { 'Inbound' }
                default { 'Both' }
            }

            $btnCreate.IsEnabled = $false
            $btnCancel.IsEnabled = $false
            $txtSummary.Text = "Creation en cours pour $($chosen.Count) executable(s)..."
            Invoke-FwmUiRefresh -Window $window

            try {
                $files = foreach ($item in $chosen) { Get-Item -LiteralPath $item.FullName }

                $state.Result = New-FwmRuleSet -SetName $setName `
                    -Executable $files `
                    -Root $state.Root `
                    -Direction $direction `
                    -Confirm:$false

                $window.DialogResult = $true
            }
            catch {
                Show-FwmMessage -Text "La creation a echoue :`n`n$_" -Icon Error -Owner $window
                $btnCreate.IsEnabled = $true
                $btnCancel.IsEnabled = $true
                & $updateSummary
            }
        }.GetNewClosure())

    $null = $window.ShowDialog()
    return $state.Result
}

# ---------------------------------------------------------------------------
# Fenetre principale
# ---------------------------------------------------------------------------

function Show-FwmMainWindow {
    $window = Import-FwmXaml -FileName 'MainWindow.xaml'

    $btnNew = $window.FindName('BtnNew')
    $btnRemove = $window.FindName('BtnRemove')
    $btnRefresh = $window.FindName('BtnRefresh')
    $btnElevate = $window.FindName('BtnElevate')
    $borderElevation = $window.FindName('BorderElevation')
    $lstSets = $window.FindName('LstSets')
    $txtStatus = $window.FindName('TxtStatus')
    $txtEmpty = $window.FindName('TxtEmpty')

    $isElevated = Test-FwmElevation

    if (-not $isElevated) {
        $borderElevation.Visibility = [System.Windows.Visibility]::Visible
        $btnNew.IsEnabled = $false
        $btnRemove.IsEnabled = $false
    }

    $refresh = {
        $txtStatus.Text = 'Lecture des regles du pare-feu...'
        Invoke-FwmUiRefresh -Window $window

        try {
            $sets = @(Get-FwmRuleSet)
        }
        catch {
            $txtStatus.Text = "Erreur de lecture : $_"
            return
        }

        $items = New-Object System.Collections.ObjectModel.ObservableCollection[FwmSetItem]
        foreach ($set in $sets) {
            $item = [FwmSetItem]::new()
            $item.SetName = $set.SetName
            $item.RuleCount = $set.RuleCount
            $item.Inbound = $set.Inbound
            $item.Outbound = $set.Outbound
            $item.StateText = if ($set.Enabled) { 'Actif' } else { 'Partiel' }
            $item.Root = $set.Root
            $items.Add($item)
        }

        $lstSets.ItemsSource = $items
        $txtEmpty.Visibility = if ($items.Count -eq 0) {
            [System.Windows.Visibility]::Visible
        }
        else {
            [System.Windows.Visibility]::Collapsed
        }

        $totalRules = ($sets | Measure-Object -Property RuleCount -Sum).Sum
        if (-not $totalRules) { $totalRules = 0 }

        $elevationNote = if ($isElevated) { 'administrateur' } else { 'lecture seule' }
        $txtStatus.Text = "$($items.Count) ensemble(s), $totalRules regle(s) - session $elevationNote."
    }.GetNewClosure()

    $btnRefresh.Add_Click({ & $refresh }.GetNewClosure())

    $btnNew.Add_Click({
            $result = Show-FwmNewRuleSetDialog -Owner $window
            & $refresh

            if ($result) {
                $message = "Ensemble '$($result.SetName)' : $($result.Created) regle(s) creee(s)"
                if ($result.Skipped -gt 0) { $message += ", $($result.Skipped) deja presente(s)" }
                if ($result.Failed -gt 0) { $message += ", $($result.Failed) en echec" }
                $txtStatus.Text = "$message."
            }
        }.GetNewClosure())

    $btnRemove.Add_Click({
            $selected = @($lstSets.SelectedItems)
            if ($selected.Count -eq 0) {
                Show-FwmMessage -Text 'Selectionnez au moins un ensemble dans la liste.' -Icon Warning -Owner $window
                return
            }

            $names = @($selected | ForEach-Object { $_.SetName })
            $ruleTotal = ($selected | Measure-Object -Property RuleCount -Sum).Sum

            $confirmation = [System.Windows.MessageBox]::Show(
                $window,
                "Supprimer $($names.Count) ensemble(s) et $ruleTotal regle(s) ?`n`n$($names -join "`n")`n`nLes logiciels concernes retrouveront leur acces reseau.",
                'Confirmer la suppression',
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning
            )

            if ($confirmation -ne [System.Windows.MessageBoxResult]::Yes) { return }

            $txtStatus.Text = 'Suppression en cours...'
            Invoke-FwmUiRefresh -Window $window

            $removed = 0
            $failed = 0
            foreach ($name in $names) {
                try {
                    $result = Remove-FwmRuleSet -SetName $name -Confirm:$false
                    if ($result) {
                        $removed += $result.Removed
                        $failed += $result.Failed
                    }
                }
                catch {
                    Show-FwmMessage -Text "Echec sur l'ensemble '$name' :`n`n$_" -Icon Error -Owner $window
                }
            }

            & $refresh
            $suffix = if ($failed -gt 0) { ", $failed en echec" } else { '' }
            $txtStatus.Text = "$removed regle(s) supprimee(s)$suffix."
        }.GetNewClosure())

    $btnElevate.Add_Click({
            try {
                Start-Process -FilePath (Get-Process -Id $PID).Path `
                    -Verb RunAs `
                    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath
                $window.Close()
            }
            catch {
                Show-FwmMessage -Text "Elevation refusee ou impossible :`n`n$_" -Icon Warning -Owner $window
            }
        }.GetNewClosure())

    $window.Add_ContentRendered({ & $refresh }.GetNewClosure())

    $null = $window.ShowDialog()
}

Show-FwmMainWindow
