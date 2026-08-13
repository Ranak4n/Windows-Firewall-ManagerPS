# Portee de decouverte : -ForEach et -Skip sont evalues avant l'execution des
# blocs BeforeAll. Ces variables doivent donc exister au niveau du fichier.
$GuiRoot = Join-Path $PSScriptRoot '..\src\Gui'
$XamlFiles = @('MainWindow.xaml', 'NewRuleSetDialog.xaml')

# WPF exige un thread STA. pwsh en fournit un par defaut sous Windows, mais on
# ne fait pas echouer la CI si l'hote en decide autrement.
$IsStaThread = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA'

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    # Redeclarees pour la phase d'execution, qui a sa propre portee.
    $script:GuiRoot = Join-Path $PSScriptRoot '..\src\Gui'
    $script:XamlFiles = @('MainWindow.xaml', 'NewRuleSetDialog.xaml')
    $script:GuiScript = Join-Path $script:GuiRoot 'Start-FwmGui.ps1'

    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA') {
        Add-Type -AssemblyName PresentationFramework
        Add-Type -AssemblyName PresentationCore
        Add-Type -AssemblyName WindowsBase
    }
}

Describe 'Interface graphique' {

    Context 'Fichiers presents' {

        It 'fournit les deux definitions de fenetre' {
            foreach ($file in $script:XamlFiles) {
                Join-Path $script:GuiRoot $file | Should -Exist
            }
        }

        It 'fournit le script de lancement' {
            $script:GuiScript | Should -Exist
        }
    }

    Context 'XAML valide' {

        It 'se charge sans erreur : <_>' -ForEach $XamlFiles -Skip:(-not $IsStaThread) {
            $path = Join-Path $script:GuiRoot $_
            $xaml = Get-Content -LiteralPath $path -Raw

            { [System.Windows.Markup.XamlReader]::Parse($xaml) } | Should -Not -Throw
        }

        It 'ne declare pas de code-behind : <_>' -ForEach $XamlFiles {
            # XamlReader ne sait pas charger de classe associee, et les
            # attributs d'evenement echouent pour la meme raison : les
            # gestionnaires doivent etre cables cote PowerShell.
            $xaml = Get-Content -LiteralPath (Join-Path $script:GuiRoot $_) -Raw

            # Les commentaires sont retires : ils documentent justement ces
            # contraintes et declencheraient de faux positifs.
            $markup = [regex]::Replace($xaml, '<!--.*?-->', '', 'Singleline')

            $markup | Should -Not -Match 'x:Class'
            $markup | Should -Not -Match '\sClick\s*='
            $markup | Should -Not -Match '\sSelectionChanged\s*='
        }
    }

    Context 'Coherence entre le XAML et le code' {

        BeforeAll {
            # Tous les noms passes a FindName dans le script de lancement.
            $content = Get-Content -LiteralPath $script:GuiScript -Raw
            $script:RequestedNames = @(
                [regex]::Matches($content, "FindName\(\s*'([^']+)'\s*\)") |
                    ForEach-Object { $_.Groups[1].Value } |
                    Sort-Object -Unique
            )

            # Tous les x:Name declares dans les fenetres.
            $script:DeclaredNames = @(
                foreach ($file in $script:XamlFiles) {
                    $xaml = Get-Content -LiteralPath (Join-Path $script:GuiRoot $file) -Raw
                    [regex]::Matches($xaml, 'x:Name="([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
                }
            ) | Sort-Object -Unique
        }

        It 'interroge effectivement des elements nommes' {
            # Garde-fou : si l'extraction ne trouve rien, le test suivant
            # passerait a vide sans rien verifier.
            $script:RequestedNames.Count | Should -BeGreaterThan 10
        }

        It 'ne demande aucun element absent du XAML' {
            # Une faute de frappe sur un x:Name ne se voit qu'a l'execution,
            # sous forme d'un FindName retournant $null puis d'une erreur de
            # propriete sur objet null. Ce test la fait remonter en CI.
            $missing = @($script:RequestedNames | Where-Object { $_ -notin $script:DeclaredNames })

            $missing -join ', ' | Should -BeNullOrEmpty
        }
    }

    Context 'Script de lancement' {

        It 'ne contient aucune erreur de syntaxe' {
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $script:GuiScript, [ref]$null, [ref]$errors) | Out-Null

            $errors | Should -BeNullOrEmpty
        }

        It 'exige PowerShell 7' {
            # OpenFolderDialog n'existe qu'a partir de .NET 8.
            Get-Content -LiteralPath $script:GuiScript -Raw | Should -Match '#Requires -Version 7'
        }

        It 'ne reimplemente pas la logique metier' {
            # L'interface doit rester une coquille : tout appel direct aux
            # cmdlets NetSecurity signalerait une fuite de logique hors module.
            $content = Get-Content -LiteralPath $script:GuiScript -Raw

            $content | Should -Not -Match 'New-NetFirewallRule'
            $content | Should -Not -Match 'Remove-NetFirewallRule'
        }
    }
}
