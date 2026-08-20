BeforeAll {
    # Fichier de fonctions pures : dot-sourçable sans ouvrir de fenêtre,
    # contrairement à Start-FwmGui.ps1.
    . (Join-Path $PSScriptRoot '..\src\Gui\GuiHelpers.ps1')
}

Describe 'Format-FwmCount' {

    Context 'Accord en français' {

        It 'met au singulier pour 1' {
            Format-FwmCount 1 'règle créée' 'règles créées' | Should -Be '1 règle créée'
        }

        It 'met au singulier pour 0' {
            # Particularité du français : zéro commande le singulier, là où
            # l'anglais mettrait le pluriel (0 rules).
            Format-FwmCount 0 'exécutable sélectionné' 'exécutables sélectionnés' |
                Should -Be '0 exécutable sélectionné'
        }

        It 'met au pluriel a partir de 2' {
            Format-FwmCount 2 'règle' 'règles' | Should -Be '2 règles'
            Format-FwmCount 18 'règle' 'règles' | Should -Be '18 règles'
        }

        It 'conserve les accents intacts' {
            Format-FwmCount 3 'règle créée' 'règles créées' | Should -Be '3 règles créées'
        }
    }
}

Describe 'Format-FwmSize' {

    It 'affiche les octets bruts en dessous du kilo-octet' {
        Format-FwmSize 512 | Should -Be '512 o'
    }

    It 'passe en kilo-octets' {
        Format-FwmSize 2048 | Should -Be '2 Ko'
    }

    It 'passe en mega-octets' {
        Format-FwmSize 1258291 | Should -Match '^1,2 Mo$|^1\.2 Mo$'
    }

    It 'passe en giga-octets' {
        Format-FwmSize 3221225472 | Should -Match '^3,0 Go$|^3\.0 Go$'
    }
}

Describe 'Format-FwmRelativePath' {

    It 'retire la racine du chemin' {
        Format-FwmRelativePath 'D:\Jeu\bin\app.exe' 'D:\Jeu' | Should -Be 'bin\app.exe'
    }

    It 'ignore la casse de la racine' {
        Format-FwmRelativePath 'D:\Jeu\app.exe' 'd:\jeu' | Should -Be 'app.exe'
    }

    It 'tolere une barre oblique finale sur la racine' {
        Format-FwmRelativePath 'D:\Jeu\app.exe' 'D:\Jeu\' | Should -Be 'app.exe'
    }

    It 'retourne le chemin complet si celui-ci est hors de la racine' {
        Format-FwmRelativePath 'C:\Autre\app.exe' 'D:\Jeu' | Should -Be 'C:\Autre\app.exe'
    }
}
