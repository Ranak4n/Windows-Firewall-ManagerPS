BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module (Get-ModuleManifestPath) -Force
}

AfterAll {
    Remove-Module WindowsFirewallManager -Force -ErrorAction SilentlyContinue
}

Describe 'Remove-FwmRuleSet' {

    BeforeEach {
        Mock -ModuleName WindowsFirewallManager Remove-NetFirewallRule { }
        Mock -ModuleName WindowsFirewallManager Get-NetFirewallRule {
            @(
                New-FakeFirewallRule -Name 'spot-in' -Group '*FWM - Spotify' -Description (
                    New-FwmTestDescription -SetName 'Spotify' -Direction 'Inbound')
                New-FakeFirewallRule -Name 'spot-out' -Group '*FWM - Spotify' -Description (
                    New-FwmTestDescription -SetName 'Spotify' -Direction 'Outbound')
                New-FakeFirewallRule -Name 'jeu-out' -Group '*FWM - Jeu' -Description (
                    New-FwmTestDescription -SetName 'Jeu' -Direction 'Outbound')
                New-FakeFirewallRule -Name 'systeme' -Group '@FirewallAPI.dll,-32752' -Description 'Regle systeme Windows.'
            )
        }
    }

    Context 'Suppression nominale' {

        It 'supprime les regles de l ensemble vise' {
            $result = Remove-FwmRuleSet -SetName 'Spotify' -Confirm:$false

            Should -Invoke Remove-NetFirewallRule -ModuleName WindowsFirewallManager -Times 2 -Exactly
            $result.Removed | Should -Be 2
            $result.Failed | Should -Be 0
        }

        It 'supprime par identifiant unique et jamais par groupe' {
            # Le point critique : Remove-NetFirewallRule -Group interprete les
            # caracteres generiques. Verifie sur machine reelle, -Group '*'
            # cible 527 des 578 regles. On passe donc exclusivement par -Name.
            Remove-FwmRuleSet -SetName 'Spotify' -Confirm:$false | Out-Null

            Should -Invoke Remove-NetFirewallRule -ModuleName WindowsFirewallManager -Times 1 -Exactly `
                -ParameterFilter { $Name -eq 'spot-in' }
            Should -Invoke Remove-NetFirewallRule -ModuleName WindowsFirewallManager -Times 1 -Exactly `
                -ParameterFilter { $Name -eq 'spot-out' }
            Should -Invoke Remove-NetFirewallRule -ModuleName WindowsFirewallManager -Times 0 -Exactly `
                -ParameterFilter { $PSBoundParameters.ContainsKey('Group') }
        }

        It 'ne touche pas aux autres ensembles' {
            Remove-FwmRuleSet -SetName 'Spotify' -Confirm:$false | Out-Null

            Should -Invoke Remove-NetFirewallRule -ModuleName WindowsFirewallManager -Times 0 -Exactly `
                -ParameterFilter { $Name -eq 'jeu-out' }
        }

        It 'ne touche jamais aux regles systeme' {
            Remove-FwmRuleSet -SetName 'Spotify' -Confirm:$false | Out-Null

            Should -Invoke Remove-NetFirewallRule -ModuleName WindowsFirewallManager -Times 0 -Exactly `
                -ParameterFilter { $Name -eq 'systeme' }
        }
    }

    Context 'Ciblage strict' {

        It 'exige une correspondance exacte du nom' {
            # 'Spot' ne doit pas emporter 'Spotify'.
            Remove-FwmRuleSet -SetName 'Spot' -Confirm:$false -WarningAction SilentlyContinue | Out-Null

            Should -Invoke Remove-NetFirewallRule -ModuleName WindowsFirewallManager -Times 0 -Exactly
        }

        It 'ne traite pas un caractere generique comme un motif' {
            # '*' est un nom litteral introuvable, surement pas "tout".
            Remove-FwmRuleSet -SetName '*' -Confirm:$false -WarningAction SilentlyContinue | Out-Null

            Should -Invoke Remove-NetFirewallRule -ModuleName WindowsFirewallManager -Times 0 -Exactly
        }

        It 'avertit sans rien supprimer si l ensemble est introuvable' {
            $warnings = @()
            Remove-FwmRuleSet -SetName 'Inexistant' -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null

            $warnings.Count | Should -BeGreaterThan 0
            Should -Invoke Remove-NetFirewallRule -ModuleName WindowsFirewallManager -Times 0 -Exactly
        }
    }

    Context 'Compte rendu via -Notify' {

        It 'signale chaque regle supprimee' {
            $events = New-Object System.Collections.Generic.List[object]

            Remove-FwmRuleSet -SetName 'Spotify' -Confirm:$false `
                -Notify { param($info) $events.Add($info) }.GetNewClosure() | Out-Null

            $events.Count | Should -Be 2
            @($events | Where-Object { $_.Status -eq 'Removed' }).Count | Should -Be 2
            $events[0].DisplayName | Should -Not -BeNullOrEmpty
        }

        It 'signale les echecs' {
            Mock -ModuleName WindowsFirewallManager Remove-NetFirewallRule { throw 'Acces refuse' }
            $events = New-Object System.Collections.Generic.List[object]

            Remove-FwmRuleSet -SetName 'Spotify' -Confirm:$false -ErrorAction SilentlyContinue `
                -Notify { param($info) $events.Add($info) }.GetNewClosure() | Out-Null

            @($events | Where-Object { $_.Status -eq 'Failed' }).Count | Should -Be 2
        }

        It 'fonctionne sans -Notify' {
            { Remove-FwmRuleSet -SetName 'Spotify' -Confirm:$false } | Should -Not -Throw
        }
    }

    Context 'Securites' {

        It 'ne touche a rien avec -WhatIf' {
            Remove-FwmRuleSet -SetName 'Spotify' -WhatIf | Out-Null

            Should -Invoke Remove-NetFirewallRule -ModuleName WindowsFirewallManager -Times 0 -Exactly
        }

        It 'accepte l entree par pipeline depuis Get-FwmRuleSet' {
            Get-FwmRuleSet -SetName 'Spotify' | Remove-FwmRuleSet -Confirm:$false | Out-Null

            Should -Invoke Remove-NetFirewallRule -ModuleName WindowsFirewallManager -Times 2 -Exactly
        }

        It 'comptabilise les echecs sans interrompre le traitement' {
            Mock -ModuleName WindowsFirewallManager Remove-NetFirewallRule {
                throw 'Acces refuse'
            }

            $result = Remove-FwmRuleSet -SetName 'Spotify' -Confirm:$false -ErrorAction SilentlyContinue

            $result.Failed | Should -Be 2
            $result.Removed | Should -Be 0
        }
    }
}
