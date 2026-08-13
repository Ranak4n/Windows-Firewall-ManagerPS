BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module (Get-ModuleManifestPath) -Force
}

AfterAll {
    Remove-Module WindowsFirewallManager -Force -ErrorAction SilentlyContinue
}

Describe 'Get-FwmExecutable' {

    Context 'Dossier sans aucun executable' {

        It 'retourne zero resultat sans lever d exception' {
            # Regression : un dossier sans .exe (AppData\Local\Spotify) faisait
            # tomber le script v1 sur "La propriete Count est introuvable".
            # La cause etait un 'return @()' deroule en $null a la sortie de
            # la fonction. Le @() ne tient qu'au site d'appel.
            $folder = Join-Path $TestDrive 'vide'
            New-Item -ItemType Directory -Path (Join-Path $folder 'sous-dossier') -Force | Out-Null

            $result = @(Get-FwmExecutable -Path $folder)

            $result.Count | Should -Be 0
        }

        It 'ignore les fichiers qui ne sont pas des .exe' {
            $folder = Join-Path $TestDrive 'sansexe'
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            'x' | Set-Content -LiteralPath (Join-Path $folder 'readme.txt')
            'x' | Set-Content -LiteralPath (Join-Path $folder 'lib.dll')

            @(Get-FwmExecutable -Path $folder).Count | Should -Be 0
        }
    }

    Context 'Dossier contenant des executables' {

        It 'retourne un tableau exploitable meme pour un seul executable' {
            # Second etage du meme piege : un resultat unique sort en scalaire.
            $folder = New-TestExecutable -Path (Join-Path $TestDrive 'un') -Name @('solo.exe')

            $result = @(Get-FwmExecutable -Path $folder)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'solo.exe'
        }

        It 'parcourt les sous-dossiers par defaut' {
            $folder = New-TestExecutable -Path (Join-Path $TestDrive 'arbo') -Name @(
                'racine.exe'
                'bin\enfant.exe'
                'bin\profond\petit-enfant.exe'
            )

            @(Get-FwmExecutable -Path $folder).Count | Should -Be 3
        }

        It 'se limite au premier niveau avec -NoRecurse' {
            $folder = New-TestExecutable -Path (Join-Path $TestDrive 'plat') -Name @(
                'racine.exe'
                'bin\enfant.exe'
            )

            $result = @(Get-FwmExecutable -Path $folder -NoRecurse)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'racine.exe'
        }
    }

    Context 'Chemin invalide' {

        It 'leve une exception explicite si le dossier n existe pas' {
            { Get-FwmExecutable -Path (Join-Path $TestDrive 'nexistepas') } |
                Should -Throw '*Dossier introuvable*'
        }

        It 'traite les crochets comme des caracteres litteraux' {
            # Un dossier "Game [2024]" ne doit pas etre interprete comme une
            # classe de caracteres : d'ou -LiteralPath.
            $folder = New-TestExecutable -Path (Join-Path $TestDrive 'Game [2024]') -Name @('game.exe')

            @(Get-FwmExecutable -Path $folder).Count | Should -Be 1
        }
    }
}
