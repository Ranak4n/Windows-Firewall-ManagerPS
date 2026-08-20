BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module (Get-ModuleManifestPath) -Force
}

AfterAll {
    Remove-Module WindowsFirewallManager -Force -ErrorAction SilentlyContinue
}

Describe 'New-FwmRuleSet' {

    BeforeEach {
        # Le pare-feu reel n'est jamais sollicite : on verifie que le module
        # appelle les bons cmdlets avec les bons parametres.
        Mock -ModuleName WindowsFirewallManager New-NetFirewallRule {
            New-FakeFirewallRule -DisplayName $DisplayName -Group $Group -Description $Description
        }
        Mock -ModuleName WindowsFirewallManager Get-NetFirewallRule { }
    }

    Context 'Creation nominale' {

        It 'cree deux regles par executable en mode Both' {
            $folder = New-TestExecutable -Path (Join-Path $TestDrive 'both') -Name @('a.exe', 'b.exe')

            $result = New-FwmRuleSet -SetName 'Demo' -Path $folder -Confirm:$false

            Should -Invoke New-NetFirewallRule -ModuleName WindowsFirewallManager -Times 4 -Exactly
            $result.Created | Should -Be 4
            $result.Failed | Should -Be 0
        }

        It 'ne cree qu une regle par executable pour un seul sens' {
            $folder = New-TestExecutable -Path (Join-Path $TestDrive 'sortant') -Name @('a.exe', 'b.exe')

            $result = New-FwmRuleSet -SetName 'Demo' -Path $folder -Direction Outbound -Confirm:$false

            Should -Invoke New-NetFirewallRule -ModuleName WindowsFirewallManager -Times 2 -Exactly
            Should -Invoke New-NetFirewallRule -ModuleName WindowsFirewallManager -Times 2 -Exactly `
                -ParameterFilter { $Direction -eq 'Outbound' }
            $result.Created | Should -Be 2
        }

        It 'place toutes les regles dans le groupe prefixe' {
            $folder = New-TestExecutable -Path (Join-Path $TestDrive 'groupe') -Name @('a.exe')

            New-FwmRuleSet -SetName 'Spotify' -Path $folder -Direction Inbound -Confirm:$false | Out-Null

            Should -Invoke New-NetFirewallRule -ModuleName WindowsFirewallManager -Times 1 -Exactly `
                -ParameterFilter { $Group -eq '*FWM - Spotify' }
        }

        It 'bloque le trafic plutot que de l autoriser' {
            $folder = New-TestExecutable -Path (Join-Path $TestDrive 'action') -Name @('a.exe')

            New-FwmRuleSet -SetName 'Demo' -Path $folder -Direction Inbound -Confirm:$false | Out-Null

            Should -Invoke New-NetFirewallRule -ModuleName WindowsFirewallManager -Times 1 -Exactly `
                -ParameterFilter { $Action -eq 'Block' }
        }

        It 'inscrit les metadonnees dans la description de chaque regle' {
            $folder = New-TestExecutable -Path (Join-Path $TestDrive 'meta') -Name @('a.exe')

            New-FwmRuleSet -SetName 'Demo' -Path $folder -Direction Outbound -Confirm:$false | Out-Null

            Should -Invoke New-NetFirewallRule -ModuleName WindowsFirewallManager -Times 1 -Exactly `
                -ParameterFilter { $Description -match '\[FWM\].+\[/FWM\]' }
        }

        It 'cible l executable par son chemin absolu' {
            $folder = New-TestExecutable -Path (Join-Path $TestDrive 'chemin') -Name @('a.exe')
            $expected = Join-Path (Resolve-Path $folder).Path 'a.exe'

            New-FwmRuleSet -SetName 'Demo' -Path $folder -Direction Outbound -Confirm:$false | Out-Null

            Should -Invoke New-NetFirewallRule -ModuleName WindowsFirewallManager -Times 1 -Exactly `
                -ParameterFilter { $Program -eq $expected }
        }
    }

    Context 'Compte rendu via -Notify' {

        It 'signale chaque regle creee' {
            # C'est ce canal qui alimente le journal de l'interface pendant
            # l'operation, plutot que d'attendre le bilan final.
            $folder = New-TestExecutable -Path (Join-Path $TestDrive 'notify') -Name @('a.exe', 'b.exe')
            $events = New-Object System.Collections.Generic.List[object]

            New-FwmRuleSet -SetName 'Demo' -Path $folder -Direction Outbound -Confirm:$false `
                -Notify { param($info) $events.Add($info) }.GetNewClosure() | Out-Null

            $events.Count | Should -Be 2
            @($events | Where-Object { $_.Status -eq 'Created' }).Count | Should -Be 2
            $events[0].DisplayName | Should -BeLike '*FWM - Demo*'
            $events[0].Direction | Should -Be 'Outbound'
        }

        It 'signale aussi les regles ignorees' {
            $folder = New-TestExecutable -Path (Join-Path $TestDrive 'notifyskip') -Name @('a.exe')
            $exePath = Join-Path (Resolve-Path $folder).Path 'a.exe'

            Mock -ModuleName WindowsFirewallManager Get-NetFirewallRule {
                New-FakeFirewallRule -Description (New-FwmTestDescription -SetName 'Demo' -ExecutablePath $exePath -Direction 'Outbound')
            }

            $events = New-Object System.Collections.Generic.List[object]

            New-FwmRuleSet -SetName 'Demo' -Path $folder -Direction Outbound -Confirm:$false `
                -Notify { param($info) $events.Add($info) }.GetNewClosure() | Out-Null

            $events.Count | Should -Be 1
            $events[0].Status | Should -Be 'Skipped'
        }

        It 'fonctionne sans -Notify' {
            $folder = New-TestExecutable -Path (Join-Path $TestDrive 'sansnotify') -Name @('a.exe')

            { New-FwmRuleSet -SetName 'Demo' -Path $folder -Direction Outbound -Confirm:$false } |
                Should -Not -Throw
        }
    }

    Context 'Selection explicite d executables' {

        It 'ne bloque que les executables fournis' {
            # C'est le chemin qu'empruntera l'interface graphique quand
            # l'utilisateur decoche certains executables de la liste.
            $folder = New-TestExecutable -Path (Join-Path $TestDrive 'selection') -Name @('garde.exe', 'ignore.exe')
            $chosen = @(Get-FwmExecutable -Path $folder | Where-Object { $_.Name -eq 'garde.exe' })

            New-FwmRuleSet -SetName 'Demo' -Executable $chosen -Direction Outbound -Confirm:$false | Out-Null

            Should -Invoke New-NetFirewallRule -ModuleName WindowsFirewallManager -Times 1 -Exactly
            Should -Invoke New-NetFirewallRule -ModuleName WindowsFirewallManager -Times 1 -Exactly `
                -ParameterFilter { $Program -like '*garde.exe' }
        }
    }

    Context 'Idempotence' {

        It 'ignore un executable deja couvert pour ce sens' {
            $folder = New-TestExecutable -Path (Join-Path $TestDrive 'idem') -Name @('a.exe')
            $exePath = Join-Path (Resolve-Path $folder).Path 'a.exe'

            Mock -ModuleName WindowsFirewallManager Get-NetFirewallRule {
                New-FakeFirewallRule -Description (New-FwmTestDescription -SetName 'Demo' -ExecutablePath $exePath -Direction 'Outbound')
            }

            $result = New-FwmRuleSet -SetName 'Demo' -Path $folder -Direction Outbound -Confirm:$false

            Should -Invoke New-NetFirewallRule -ModuleName WindowsFirewallManager -Times 0 -Exactly
            $result.Skipped | Should -Be 1
            $result.Created | Should -Be 0
        }

        It 'complete le sens manquant sans dupliquer l existant' {
            $folder = New-TestExecutable -Path (Join-Path $TestDrive 'complete') -Name @('a.exe')
            $exePath = Join-Path (Resolve-Path $folder).Path 'a.exe'

            Mock -ModuleName WindowsFirewallManager Get-NetFirewallRule {
                New-FakeFirewallRule -Description (New-FwmTestDescription -SetName 'Demo' -ExecutablePath $exePath -Direction 'Outbound')
            }

            $result = New-FwmRuleSet -SetName 'Demo' -Path $folder -Confirm:$false

            $result.Created | Should -Be 1
            $result.Skipped | Should -Be 1
            Should -Invoke New-NetFirewallRule -ModuleName WindowsFirewallManager -Times 1 -Exactly `
                -ParameterFilter { $Direction -eq 'Inbound' }
        }
    }

    Context 'Cas limites' {

        It 'ne cree rien et avertit si le dossier ne contient aucun executable' {
            $folder = Join-Path $TestDrive 'aucun'
            New-Item -ItemType Directory -Path $folder -Force | Out-Null

            New-FwmRuleSet -SetName 'Demo' -Path $folder -Confirm:$false -WarningAction SilentlyContinue |
                Should -BeNullOrEmpty

            Should -Invoke New-NetFirewallRule -ModuleName WindowsFirewallManager -Times 0 -Exactly
        }

        It 'refuse un nom d ensemble contenant un caractere generique' {
            $folder = New-TestExecutable -Path (Join-Path $TestDrive 'wildcard') -Name @('a.exe')

            { New-FwmRuleSet -SetName 'Spot*' -Path $folder -Confirm:$false } | Should -Throw

            Should -Invoke New-NetFirewallRule -ModuleName WindowsFirewallManager -Times 0 -Exactly
        }

        It 'ne touche a rien avec -WhatIf' {
            $folder = New-TestExecutable -Path (Join-Path $TestDrive 'whatif') -Name @('a.exe', 'b.exe')

            New-FwmRuleSet -SetName 'Demo' -Path $folder -WhatIf | Out-Null

            Should -Invoke New-NetFirewallRule -ModuleName WindowsFirewallManager -Times 0 -Exactly
        }
    }
}
