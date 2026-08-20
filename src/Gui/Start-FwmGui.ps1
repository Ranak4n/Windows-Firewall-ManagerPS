#Requires -Version 7.0
<#
.SYNOPSIS
    Interface graphique de Windows Firewall Manager.

.DESCRIPTION
    Coquille WPF au-dessus du module WindowsFirewallManager : toute la logique
    métier reste dans le module, ce fichier ne fait qu'afficher et collecter.

    PowerShell 7 est requis : la fenêtre a besoin d'un thread STA (que pwsh
    fournit par défaut) et le sélecteur de dossier moderne n'existe qu'à
    partir de .NET 8.

    ATTENTION aux fermetures : GetNewClosure() ne capture que la portée
    LOCALE. Un bloc créé à l'intérieur d'un gestionnaire d'événement ne
    re-capture pas ce que le gestionnaire avait lui-même capturé. Tout bloc
    destiné à être appelé depuis le module (les blocs -Notify) doit donc être
    défini au niveau de la fonction, jamais dans un gestionnaire.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

Import-Module (Join-Path $PSScriptRoot '..\WindowsFirewallManager\WindowsFirewallManager.psd1') -Force
. (Join-Path $PSScriptRoot 'GuiHelpers.ps1')

# ---------------------------------------------------------------------------
# Types de liaison
#
# WPF lie mal les PSCustomObject : on passe par de vraies classes. FwmExeItem
# implémente INotifyPropertyChanged, ce qui sert deux fois : les cases à
# cocher se rafraîchissent quand « Tout cocher » modifie les objets, et le
# décompte se met à jour sur l'événement de changement plutôt que sur un
# événement souris.
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
# Utilitaires d'interface
# ---------------------------------------------------------------------------

function Import-FwmXaml {
    param([Parameter(Mandatory)][string]$FileName)

    $path = Join-Path $PSScriptRoot $FileName
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Fichier d'interface introuvable : $path"
    }

    # Les fichiers sont encodés en UTF-8 avec BOM : PowerShell le retire à la
    # lecture, les accents arrivent intacts jusqu'à XamlReader.
    $xaml = Get-Content -LiteralPath $path -Raw
    return [System.Windows.Markup.XamlReader]::Parse($xaml)
}

function Invoke-FwmUiRefresh {
    <#
        Force un rafraîchissement immédiat de la fenêtre. Les opérations sur
        le pare-feu sont synchrones : sans cela, ni le message d'attente ni
        les lignes du journal ne s'afficheraient avant la fin du traitement.
    #>
    param([Parameter(Mandatory)]$Window)

    $Window.Dispatcher.Invoke(
        [action] {},
        [System.Windows.Threading.DispatcherPriority]::Render
    )
}

function Set-FwmLogBehavior {
    <#
        Agrandit la fenêtre à l'ouverture du journal et la réduit à sa
        fermeture. Sans cela le journal mange la place de la liste, qui
        devient inutilisable sans redimensionnement manuel.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Configure des gestionnaires WPF, sans effet de bord système.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Window et ExtraHeight sont utilisés dans les blocs de script des gestionnaires, que l''analyseur n''inspecte pas.')]
    param(
        [Parameter(Mandatory)]$Window,
        [Parameter(Mandatory)]$Expander,
        [int]$ExtraHeight = 190
    )

    $Expander.Add_Expanded({
            if ($Window.WindowState -ne [System.Windows.WindowState]::Normal) { return }
            $available = [System.Windows.SystemParameters]::WorkArea.Height
            $Window.Height = [Math]::Min($Window.ActualHeight + $ExtraHeight, $available)
        }.GetNewClosure())

    $Expander.Add_Collapsed({
            if ($Window.WindowState -ne [System.Windows.WindowState]::Normal) { return }
            $Window.Height = [Math]::Max($Window.ActualHeight - $ExtraHeight, $Window.MinHeight)
        }.GetNewClosure())
}

function Select-FwmFolder {
    param([string]$Title = 'Choisissez le dossier du logiciel')

    # OpenFolderDialog (.NET 8+) est le sélecteur moderne de Windows.
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

function Copy-FwmTextToClipboard {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return }

    try {
        [System.Windows.Clipboard]::SetText($Text)
    }
    catch {
        # Le presse-papiers peut être verrouillé par une autre application.
        Write-Warning "Copie impossible : $_"
    }
}

function Get-FwmListViewItemUnderCursor {
    <#
        Remonte l'arbre visuel depuis l'élément cliqué jusqu'à la ligne de
        liste qui le contient. Nécessaire parce qu'un clic droit ne
        sélectionne pas la ligne de lui-même dans un ListView.
    #>
    param([Parameter(Mandatory)]$Source)

    $current = $Source
    while ($null -ne $current -and $current -isnot [System.Windows.Controls.ListViewItem]) {
        if ($current -isnot [System.Windows.DependencyObject]) { return $null }
        $current = [System.Windows.Media.VisualTreeHelper]::GetParent($current)
    }
    return $current
}

function New-FwmCopyMenuItem {
    <#
        Fabrique une entrée de menu contextuel qui copie une propriété des
        éléments sélectionnés d'une liste.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Construit un objet WPF en mémoire.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'ListView et Property sont utilisés dans le bloc de script du gestionnaire, que l''analyseur n''inspecte pas.')]
    param(
        [Parameter(Mandatory)][string]$Header,
        [Parameter(Mandatory)]$ListView,
        [Parameter(Mandatory)][string]$Property,
        [string]$Gesture
    )

    $menuItem = New-Object System.Windows.Controls.MenuItem
    $menuItem.Header = $Header
    if ($Gesture) { $menuItem.InputGestureText = $Gesture }

    $menuItem.Add_Click({
            $values = @($ListView.SelectedItems | ForEach-Object { $_.$Property })
            if ($values.Count -eq 0) { return }
            Copy-FwmTextToClipboard -Text ($values -join "`r`n")
        }.GetNewClosure())

    return $menuItem
}

function Enable-FwmRightClickSelection {
    <#
        Fait qu'un clic droit sélectionne d'abord la ligne visée : sans cela
        le menu contextuel agirait sur une sélection sans rapport.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Configure un gestionnaire WPF, sans effet de bord système.')]
    param([Parameter(Mandatory)]$ListView)

    # Les arguments d'événement sont lus dans $args plutôt que déclarés en
    # paramètres : $EventArgs est une variable automatique de PowerShell.
    $ListView.Add_PreviewMouseRightButtonDown({
            $evt = $args[1]

            $row = Get-FwmListViewItemUnderCursor -Source $evt.OriginalSource
            if ($row -and -not $row.IsSelected) {
                $ListView.SelectedItems.Clear()
                $row.IsSelected = $true
            }
        }.GetNewClosure())
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
# Fenêtre « Nouveau blocage »
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
    $expLog = $window.FindName('ExpLog')
    $txtLog = $window.FindName('TxtLog')
    $btnCreate = $window.FindName('BtnCreate')
    $btnCancel = $window.FindName('BtnCancel')

    # État partagé entre les gestionnaires d'événements.
    $state = [PSCustomObject]@{
        Items   = New-Object System.Collections.ObjectModel.ObservableCollection[FwmExeItem]
        Root    = $null
        Result  = $null
        # Suspend le recalcul pendant les opérations en lot, qui déclencheraient
        # sinon un événement par élément.
        Suspend = $false
    }
    $lstExes.ItemsSource = $state.Items

    Set-FwmLogBehavior -Window $window -Expander $expLog

    $appendLog = {
        param([string]$Line)

        $txtLog.AppendText("$Line`r`n")
        $txtLog.ScrollToEnd()
    }.GetNewClosure()

    # Défini ici, au niveau de la fonction, et surtout PAS dans le
    # gestionnaire du bouton : ce bloc est appelé depuis le module, et une
    # fermeture créée dans une autre fermeture ne capture pas $appendLog.
    $notifyRule = {
        param($info)

        $prefix = switch ($info.Status) {
            'Created' { '  créée   ' }
            'Skipped' { '  ignorée ' }
            default { '  ÉCHEC   ' }
        }
        & $appendLog "$prefix $($info.DisplayName)"
        Invoke-FwmUiRefresh -Window $window
    }.GetNewClosure()

    $updateSummary = {
        if ($state.Suspend) { return }

        $selected = @($state.Items | Where-Object { $_.Selected }).Count
        $perExe = if ($cmbDirection.SelectedIndex -eq 0) { 2 } else { 1 }
        $rules = $selected * $perExe

        $name = $txtSetName.Text.Trim()
        $txtGroupPreview.Text = if ($name) {
            "Groupe pare-feu : *FWM - $name"
        }
        else {
            'Groupe pare-feu : *FWM - ...'
        }

        if ($state.Items.Count -eq 0) {
            $txtSummary.Text = 'Choisissez un dossier pour commencer.'
        }
        else {
            $picked = Format-FwmCount $selected 'exécutable sélectionné' 'exécutables sélectionnés'
            $planned = Format-FwmCount $rules 'règle à créer' 'règles à créer'
            $txtSummary.Text = "$picked sur $($state.Items.Count) — $planned."
        }

        $btnCreate.IsEnabled = ($selected -gt 0 -and $name.Length -gt 0)
    }.GetNewClosure()

    # Le décompte est mis à jour sur l'événement de changement de l'objet, et
    # non sur un événement souris : PreviewMouseLeftButtonUp se déclenche
    # pendant la phase de tunnelage, donc AVANT que la case ne bascule, ce qui
    # décalait le total d'un cran à chaque clic.
    $onItemChanged = { & $updateSummary }.GetNewClosure()

    $loadFolder = {
        param([string]$Path)

        if ([string]::IsNullOrWhiteSpace($Path)) { return }

        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            Show-FwmMessage -Text "Dossier introuvable :`n$Path" -Icon Warning -Owner $window
            return
        }

        $resolved = (Resolve-Path -LiteralPath $Path).Path

        $state.Suspend = $true
        $state.Items.Clear()
        $state.Root = $resolved
        $txtFolder.Text = $resolved

        # @() indispensable : la sortie d'une fonction est déroulée, zéro
        # exécutable donnerait $null.
        $exes = @(Get-FwmExecutable -Path $resolved)

        foreach ($exe in ($exes | Sort-Object FullName)) {
            $item = [FwmExeItem]::new()
            $item.Selected = $true
            $item.Name = $exe.Name
            $item.FullName = $exe.FullName
            $item.SizeText = Format-FwmSize $exe.Length
            $item.RelativePath = Format-FwmRelativePath $exe.FullName $resolved
            $item.add_PropertyChanged($onItemChanged)
            $state.Items.Add($item)
        }

        $state.Suspend = $false

        if ($state.Items.Count -eq 0) {
            Show-FwmMessage -Text "Aucun exécutable trouvé dans :`n$resolved`n`nSous-dossiers inclus." -Icon Warning -Owner $window
        }

        # Propose le nom du dossier comme nom d'ensemble, sans écraser une
        # saisie déjà faite par l'utilisateur.
        if ([string]::IsNullOrWhiteSpace($txtSetName.Text)) {
            $txtSetName.Text = (Split-Path -Path $resolved -Leaf) -replace '[*?\[\]]', ''
        }

        & $updateSummary
    }.GetNewClosure()

    # --- Menu contextuel de la liste des exécutables ---

    $copySelectedPaths = {
        $paths = @($lstExes.SelectedItems | ForEach-Object { $_.FullName })
        if ($paths.Count -eq 0) { return }
        Copy-FwmTextToClipboard -Text ($paths -join "`r`n")
    }.GetNewClosure()

    $contextMenu = New-Object System.Windows.Controls.ContextMenu
    $null = $contextMenu.Items.Add((New-FwmCopyMenuItem -Header 'Copier le chemin complet' -ListView $lstExes -Property 'FullName' -Gesture 'Ctrl+C'))
    $null = $contextMenu.Items.Add((New-FwmCopyMenuItem -Header 'Copier le nom du fichier' -ListView $lstExes -Property 'Name'))
    $null = $contextMenu.Items.Add((New-Object System.Windows.Controls.Separator))

    $menuOpenFolder = New-Object System.Windows.Controls.MenuItem
    $menuOpenFolder.Header = 'Ouvrir le dossier contenant'
    $menuOpenFolder.Add_Click({
            $first = @($lstExes.SelectedItems)[0]
            if (-not $first) { return }
            # /select met le fichier en surbrillance dans l'Explorateur.
            Start-Process -FilePath 'explorer.exe' -ArgumentList "/select,`"$($first.FullName)`""
        }.GetNewClosure())
    $null = $contextMenu.Items.Add($menuOpenFolder)

    $lstExes.ContextMenu = $contextMenu
    Enable-FwmRightClickSelection -ListView $lstExes

    $lstExes.Add_KeyDown({
            $evt = $args[1]

            $ctrl = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control
            if ($ctrl -and $evt.Key -eq [System.Windows.Input.Key]::C) {
                & $copySelectedPaths
                $evt.Handled = $true
            }
        }.GetNewClosure())

    # --- Gestionnaires ---

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

    $setAllSelected = {
        param([bool]$Value)

        # Un seul recalcul en fin d'opération plutôt qu'un par élément.
        $state.Suspend = $true
        foreach ($item in $state.Items) { $item.Selected = $Value }
        $state.Suspend = $false
        & $updateSummary
    }.GetNewClosure()

    $btnCheckAll.Add_Click({ & $setAllSelected $true }.GetNewClosure())
    $btnUncheckAll.Add_Click({ & $setAllSelected $false }.GetNewClosure())

    $btnCancel.Add_Click({ $window.DialogResult = $false }.GetNewClosure())

    $btnCreate.Add_Click({
            $setName = $txtSetName.Text.Trim()
            $chosen = @($state.Items | Where-Object { $_.Selected })

            if ($chosen.Count -eq 0) {
                Show-FwmMessage -Text 'Aucun exécutable sélectionné.' -Icon Warning -Owner $window
                return
            }

            $direction = switch ($cmbDirection.SelectedIndex) {
                1 { 'Outbound' }
                2 { 'Inbound' }
                default { 'Both' }
            }

            $btnCreate.IsEnabled = $false
            $btnCancel.IsEnabled = $false
            $expLog.IsExpanded = $true
            $txtLog.Clear()

            & $appendLog "Ensemble : $setName"
            & $appendLog "Groupe   : *FWM - $setName"
            & $appendLog "Dossier  : $($state.Root)"
            & $appendLog ('-' * 60)

            $txtSummary.Text = "Création en cours pour $(Format-FwmCount $chosen.Count 'exécutable' 'exécutables')..."
            Invoke-FwmUiRefresh -Window $window

            try {
                $files = foreach ($item in $chosen) { Get-Item -LiteralPath $item.FullName }

                $state.Result = New-FwmRuleSet -SetName $setName `
                    -Executable $files `
                    -Root $state.Root `
                    -Direction $direction `
                    -Notify $notifyRule `
                    -Confirm:$false

                & $appendLog ('-' * 60)
                $summary = '{0}, {1}, {2}' -f
                    (Format-FwmCount $state.Result.Created 'règle créée' 'règles créées'),
                    (Format-FwmCount $state.Result.Skipped 'déjà présente' 'déjà présentes'),
                    (Format-FwmCount $state.Result.Failed 'en échec' 'en échec')
                & $appendLog "Terminé : $summary."

                if ($state.Result.Failed -eq 0) {
                    $window.DialogResult = $true
                }
                else {
                    # On garde la fenêtre ouverte pour que le journal reste
                    # consultable en cas d'échec partiel.
                    $btnCancel.IsEnabled = $true
                    $btnCancel.Content = 'Fermer'
                    $txtSummary.Text = "$(Format-FwmCount $state.Result.Failed 'règle en échec' 'règles en échec'). Voir le journal."
                }
            }
            catch {
                & $appendLog "ERREUR : $_"
                Show-FwmMessage -Text "La création a échoué :`n`n$_" -Icon Error -Owner $window
                $btnCreate.IsEnabled = $true
                $btnCancel.IsEnabled = $true
                & $updateSummary
            }
        }.GetNewClosure())

    $null = $window.ShowDialog()
    return $state.Result
}

# ---------------------------------------------------------------------------
# Fenêtre principale
# ---------------------------------------------------------------------------

function Show-FwmMainWindow {
    $window = Import-FwmXaml -FileName 'MainWindow.xaml'

    $btnNew = $window.FindName('BtnNew')
    $btnRemove = $window.FindName('BtnRemove')
    $btnRefresh = $window.FindName('BtnRefresh')
    $btnOpenFirewall = $window.FindName('BtnOpenFirewall')
    $btnElevate = $window.FindName('BtnElevate')
    $borderElevation = $window.FindName('BorderElevation')
    $lstSets = $window.FindName('LstSets')
    $txtStatus = $window.FindName('TxtStatus')
    $txtEmpty = $window.FindName('TxtEmpty')
    $expLog = $window.FindName('ExpLog')
    $txtLog = $window.FindName('TxtLog')

    $isElevated = Test-FwmElevation

    if (-not $isElevated) {
        $borderElevation.Visibility = [System.Windows.Visibility]::Visible
        $btnNew.IsEnabled = $false
        $btnRemove.IsEnabled = $false
    }

    Set-FwmLogBehavior -Window $window -Expander $expLog

    $appendLog = {
        param([string]$Line)

        $txtLog.AppendText("$Line`r`n")
        $txtLog.ScrollToEnd()
    }.GetNewClosure()

    # Défini au niveau de la fonction : ce bloc est appelé depuis le module.
    $notifyRemoval = {
        param($info)

        $prefix = if ($info.Status -eq 'Removed') { '  supprimée ' } else { '  ÉCHEC     ' }
        & $appendLog "$prefix $($info.DisplayName)"
        Invoke-FwmUiRefresh -Window $window
    }.GetNewClosure()

    # --- Menu contextuel de la liste des ensembles ---

    $contextMenu = New-Object System.Windows.Controls.ContextMenu
    $null = $contextMenu.Items.Add((New-FwmCopyMenuItem -Header "Copier le nom de l'ensemble" -ListView $lstSets -Property 'SetName'))
    $null = $contextMenu.Items.Add((New-FwmCopyMenuItem -Header "Copier le dossier d'origine" -ListView $lstSets -Property 'Root' -Gesture 'Ctrl+C'))
    $null = $contextMenu.Items.Add((New-Object System.Windows.Controls.Separator))

    $menuOpenRoot = New-Object System.Windows.Controls.MenuItem
    $menuOpenRoot.Header = "Ouvrir le dossier d'origine"
    $menuOpenRoot.Add_Click({
            $first = @($lstSets.SelectedItems)[0]
            if (-not $first -or -not $first.Root) { return }
            if (-not (Test-Path -LiteralPath $first.Root)) {
                Show-FwmMessage -Text "Le dossier n'existe plus :`n$($first.Root)" -Icon Warning -Owner $window
                return
            }
            Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$($first.Root)`""
        }.GetNewClosure())
    $null = $contextMenu.Items.Add($menuOpenRoot)

    $lstSets.ContextMenu = $contextMenu
    Enable-FwmRightClickSelection -ListView $lstSets

    $lstSets.Add_KeyDown({
            $evt = $args[1]

            $ctrl = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control
            if ($ctrl -and $evt.Key -eq [System.Windows.Input.Key]::C) {
                $roots = @($lstSets.SelectedItems | ForEach-Object { $_.Root })
                if ($roots.Count -gt 0) { Copy-FwmTextToClipboard -Text ($roots -join "`r`n") }
                $evt.Handled = $true
            }
        }.GetNewClosure())

    # --- Rafraîchissement ---

    $refresh = {
        $txtStatus.Text = 'Lecture des règles du pare-feu...'
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

        $setsText = Format-FwmCount $items.Count 'ensemble' 'ensembles'
        $rulesText = Format-FwmCount $totalRules 'règle' 'règles'
        $mode = if ($isElevated) { 'administrateur' } else { 'lecture seule' }
        $txtStatus.Text = "$setsText, $rulesText — session $mode."
    }.GetNewClosure()

    $btnRefresh.Add_Click({ & $refresh }.GetNewClosure())

    $btnOpenFirewall.Add_Click({
            try {
                # Windows ne permet pas d'ouvrir la console sur un groupe
                # précis : elle s'ouvre sur la vue par défaut.
                Start-Process -FilePath 'mmc.exe' -ArgumentList 'wf.msc'
            }
            catch {
                Show-FwmMessage -Text "Impossible d'ouvrir le Pare-feu Windows :`n`n$_" -Icon Warning -Owner $window
            }
        }.GetNewClosure())

    $btnNew.Add_Click({
            $result = Show-FwmNewRuleSetDialog -Owner $window
            & $refresh

            if ($result) {
                $created = Format-FwmCount $result.Created 'règle créée' 'règles créées'
                $message = "Ensemble « $($result.SetName) » : $created"
                if ($result.Skipped -gt 0) {
                    $message += ", $(Format-FwmCount $result.Skipped 'déjà présente' 'déjà présentes')"
                }
                if ($result.Failed -gt 0) {
                    $message += ", $(Format-FwmCount $result.Failed 'en échec' 'en échec')"
                }
                $txtStatus.Text = "$message."
                & $appendLog "$message."
            }
        }.GetNewClosure())

    $btnRemove.Add_Click({
            $selected = @($lstSets.SelectedItems)
            if ($selected.Count -eq 0) {
                Show-FwmMessage -Text 'Sélectionnez au moins un ensemble dans la liste.' -Icon Warning -Owner $window
                return
            }

            $names = @($selected | ForEach-Object { $_.SetName })
            $ruleTotal = ($selected | Measure-Object -Property RuleCount -Sum).Sum

            $setsText = Format-FwmCount $names.Count 'ensemble' 'ensembles'
            $rulesText = Format-FwmCount $ruleTotal 'règle' 'règles'

            $confirmation = [System.Windows.MessageBox]::Show(
                $window,
                "Supprimer $setsText et $rulesText ?`n`n$($names -join "`n")`n`nLes logiciels concernés retrouveront leur accès réseau.",
                'Confirmer la suppression',
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning
            )

            if ($confirmation -ne [System.Windows.MessageBoxResult]::Yes) { return }

            $expLog.IsExpanded = $true
            $txtLog.Clear()
            & $appendLog "Suppression de $setsText ($rulesText)"
            & $appendLog ('-' * 60)

            $txtStatus.Text = 'Suppression en cours...'
            Invoke-FwmUiRefresh -Window $window

            $removed = 0
            $failed = 0
            foreach ($name in $names) {
                & $appendLog "Ensemble « $name »"
                try {
                    $result = Remove-FwmRuleSet -SetName $name -Notify $notifyRemoval -Confirm:$false
                    if ($result) {
                        $removed += $result.Removed
                        $failed += $result.Failed
                    }
                }
                catch {
                    & $appendLog "ERREUR : $_"
                    Show-FwmMessage -Text "Échec sur l'ensemble « $name » :`n`n$_" -Icon Error -Owner $window
                }
            }

            & $refresh

            $removedText = Format-FwmCount $removed 'règle supprimée' 'règles supprimées'
            $suffix = if ($failed -gt 0) { ", $(Format-FwmCount $failed 'en échec' 'en échec')" } else { '' }
            & $appendLog ('-' * 60)
            & $appendLog "Terminé : $removedText$suffix."
            $txtStatus.Text = "$removedText$suffix."
        }.GetNewClosure())

    $btnElevate.Add_Click({
            try {
                Start-Process -FilePath (Get-Process -Id $PID).Path `
                    -Verb RunAs `
                    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath
                $window.Close()
            }
            catch {
                Show-FwmMessage -Text "Élévation refusée ou impossible :`n`n$_" -Icon Warning -Owner $window
            }
        }.GetNewClosure())

    $window.Add_ContentRendered({ & $refresh }.GetNewClosure())

    $null = $window.ShowDialog()
}

Show-FwmMainWindow
