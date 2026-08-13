BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module (Get-ModuleManifestPath) -Force
}

AfterAll {
    Remove-Module WindowsFirewallManager -Force -ErrorAction SilentlyContinue
}

Describe 'Get-FwmRuleSet' {

    Context 'Inventaire' {

        BeforeEach {
            Mock -ModuleName WindowsFirewallManager Get-NetFirewallRule {
                @(
                    New-FakeFirewallRule -Name 'r1' -Group '*FWM - Spotify' -Direction 'Inbound' -Description (
                        New-FwmTestDescription -SetName 'Spotify' -Root 'C:\Apps\Spotify' -ExecutablePath 'C:\Apps\Spotify\Spotify.exe' -Direction 'Inbound')
                    New-FakeFirewallRule -Name 'r2' -Group '*FWM - Spotify' -Direction 'Outbound' -Description (
                        New-FwmTestDescription -SetName 'Spotify' -Root 'C:\Apps\Spotify' -ExecutablePath 'C:\Apps\Spotify\Spotify.exe' -Direction 'Outbound')
                    New-FakeFirewallRule -Name 'r3' -Group '*FWM - Jeu' -Direction 'Outbound' -Description (
                        New-FwmTestDescription -SetName 'Jeu' -Root 'D:\Jeu' -ExecutablePath 'D:\Jeu\jeu.exe' -Direction 'Outbound')

                    # Regles etrangeres : ne doivent jamais apparaitre.
                    New-FakeFirewallRule -Name 'sys1' -Group '@FirewallAPI.dll,-32752' -Description 'Regle systeme Windows.'
                    New-FakeFirewallRule -Name 'sys2' -Group '*CustomBlock' -Description ''
                    New-FakeFirewallRule -Name 'sys3' -Group '*Autre' -Description 'Texte [FWM]{"pas":"conforme"}[/FWM]'
                )
            }
        }

        It 'regroupe les regles par ensemble' {
            $sets = @(Get-FwmRuleSet)

            $sets.Count | Should -Be 2
            $sets.SetName | Should -Contain 'Spotify'
            $sets.SetName | Should -Contain 'Jeu'
        }

        It 'ignore les regles ne portant pas de metadonnees valides' {
            $sets = @(Get-FwmRuleSet)

            @($sets | ForEach-Object { $_.Rules }).Name | Should -Not -Contain 'sys1'
            @($sets | ForEach-Object { $_.Rules }).Name | Should -Not -Contain 'sys2'
            @($sets | ForEach-Object { $_.Rules }).Name | Should -Not -Contain 'sys3'
        }

        It 'compte les regles par sens' {
            $spotify = Get-FwmRuleSet -SetName 'Spotify'

            $spotify.RuleCount | Should -Be 2
            $spotify.Inbound | Should -Be 1
            $spotify.Outbound | Should -Be 1
        }

        It 'restitue le dossier d origine' {
            (Get-FwmRuleSet -SetName 'Spotify').Root | Should -Be 'C:\Apps\Spotify'
        }

        It 'filtre par motif sans transmettre le motif au pare-feu' {
            # Le filtrage est fait cote client avec -like : aucun caractere
            # generique ne part vers les cmdlets NetSecurity.
            $sets = @(Get-FwmRuleSet -SetName 'Spot*')

            $sets.Count | Should -Be 1
            $sets[0].SetName | Should -Be 'Spotify'

            Should -Invoke Get-NetFirewallRule -ModuleName WindowsFirewallManager `
                -ParameterFilter { -not $PSBoundParameters.ContainsKey('Group') }
        }

        It 'ne retourne rien si aucun ensemble ne correspond' {
            @(Get-FwmRuleSet -SetName 'Inexistant').Count | Should -Be 0
        }
    }

    Context 'Etat d activation' {

        It 'signale un ensemble actif quand toutes ses regles le sont' {
            Mock -ModuleName WindowsFirewallManager Get-NetFirewallRule {
                @(
                    New-FakeFirewallRule -Name 'a' -Enabled 'True' -Description (New-FwmTestDescription -SetName 'X' -Direction 'Inbound')
                    New-FakeFirewallRule -Name 'b' -Enabled 'True' -Description (New-FwmTestDescription -SetName 'X' -Direction 'Outbound')
                )
            }

            (Get-FwmRuleSet -SetName 'X').Enabled | Should -BeTrue
        }

        It 'signale un ensemble inactif des qu une regle est desactivee' {
            # Un ensemble partiellement desactive ne protege plus : il ne doit
            # pas s'afficher comme actif.
            Mock -ModuleName WindowsFirewallManager Get-NetFirewallRule {
                @(
                    New-FakeFirewallRule -Name 'a' -Enabled 'True' -Description (New-FwmTestDescription -SetName 'X' -Direction 'Inbound')
                    New-FakeFirewallRule -Name 'b' -Enabled 'False' -Description (New-FwmTestDescription -SetName 'X' -Direction 'Outbound')
                )
            }

            (Get-FwmRuleSet -SetName 'X').Enabled | Should -BeFalse
        }
    }

    Context 'Pare-feu vide' {

        It 'ne retourne rien plutot que de lever une exception' {
            Mock -ModuleName WindowsFirewallManager Get-NetFirewallRule { }

            @(Get-FwmRuleSet).Count | Should -Be 0
        }
    }
}
