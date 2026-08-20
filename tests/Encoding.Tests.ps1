Describe 'Encodage des fichiers source' {

    BeforeAll {
        $script:SourceFiles = @(
            Get-ChildItem -Path (Join-Path $PSScriptRoot '..') -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1', '*.xaml' |
                Where-Object { $_.FullName -notmatch '\\\.git\\' }
        )
    }

    It 'trouve des fichiers a verifier' {
        $script:SourceFiles.Count | Should -BeGreaterThan 5
    }

    It 'place un BOM sur tout fichier contenant des caracteres accentues' {
        # Sans BOM, Windows PowerShell 5.1 lit le fichier en ANSI et les
        # accents deviennent illisibles. PSScriptAnalyzer applique la meme
        # regle (PSUseBOMForUnicodeEncodedFile) ; ce test la fait porter
        # aussi sur les fichiers XAML, qu'il n'analyse pas.
        $faulty = foreach ($file in $script:SourceFiles) {
            $raw = Get-Content -LiteralPath $file.FullName -Raw
            if (-not $raw) { continue }

            $hasAccents = $raw.ToCharArray() | Where-Object { [int]$_ -gt 127 } | Select-Object -First 1
            if (-not $hasAccents) { continue }

            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            $hasBom = $bytes.Length -ge 3 -and
                      $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF

            if (-not $hasBom) { $file.Name }
        }

        @($faulty) -join ', ' | Should -BeNullOrEmpty
    }

    It 'relit correctement les accents de l interface' {
        # Verification de bout en bout : le fichier tel qu'il est sur le
        # disque redonne bien les caracteres attendus.
        $xaml = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\Gui\NewRuleSetDialog.xaml') -Raw

        $xaml | Should -Match 'Exécutables à bloquer'
        $xaml | Should -Match 'Créer les règles'
        $xaml | Should -Not -Match 'Ã'   # signature classique d'un UTF-8 relu en ANSI
    }
}
