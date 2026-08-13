BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module (Get-ModuleManifestPath) -Force
}

AfterAll {
    Remove-Module WindowsFirewallManager -Force -ErrorAction SilentlyContinue
}

Describe 'Metadonnees inscrites dans la description des regles' {

    Context 'ConvertTo-FwmDescription' {

        It 'produit un texte lisible suivi du bloc balise' {
            InModuleScope WindowsFirewallManager {
                $description = ConvertTo-FwmDescription -SetName 'Spotify' `
                    -Root 'C:\Apps\Spotify' `
                    -ExecutablePath 'C:\Apps\Spotify\Spotify.exe' `
                    -Direction 'Outbound'

                $description | Should -BeLike '*Spotify.exe*'
                $description | Should -BeLike '*[[]FWM]*[[]/FWM]*'
            }
        }

        It 'n introduit aucun caractere de controle' {
            # Le champ transite par CIM : on reste sur une seule ligne.
            InModuleScope WindowsFirewallManager {
                $description = ConvertTo-FwmDescription -SetName 'Demo' `
                    -Root 'C:\Demo' `
                    -ExecutablePath 'C:\Demo\demo.exe' `
                    -Direction 'Inbound'

                $description | Should -Not -Match "[`r`n`t]"
            }
        }
    }

    Context 'ConvertFrom-FwmDescription' {

        It 'relit fidelement ce que ConvertTo a ecrit' {
            InModuleScope WindowsFirewallManager {
                $description = ConvertTo-FwmDescription -SetName 'Spotify' `
                    -Root 'C:\Apps\Spotify' `
                    -ExecutablePath 'C:\Apps\Spotify\Spotify.exe' `
                    -Direction 'Outbound'

                $metadata = ConvertFrom-FwmDescription -Description $description

                $metadata.set | Should -Be 'Spotify'
                $metadata.root | Should -Be 'C:\Apps\Spotify'
                $metadata.exe | Should -Be 'C:\Apps\Spotify\Spotify.exe'
                $metadata.dir | Should -Be 'Outbound'
                $metadata.v | Should -Be 1
            }
        }

        It 'lit un bloc conforme au format sans dependre de ConvertTo' {
            $raw = New-FwmTestDescription -SetName 'Autre' -Direction 'Inbound'

            InModuleScope WindowsFirewallManager -Parameters @{ Raw = $raw } {
                param($Raw)
                $metadata = ConvertFrom-FwmDescription -Description $Raw
                $metadata.set | Should -Be 'Autre'
                $metadata.dir | Should -Be 'Inbound'
            }
        }

        It 'retourne null pour une regle etrangere' {
            InModuleScope WindowsFirewallManager {
                ConvertFrom-FwmDescription -Description 'Regle creee par Windows.' |
                    Should -BeNullOrEmpty
            }
        }

        It 'retourne null pour une description vide ou absente' {
            InModuleScope WindowsFirewallManager {
                ConvertFrom-FwmDescription -Description '' | Should -BeNullOrEmpty
                ConvertFrom-FwmDescription -Description $null | Should -BeNullOrEmpty
            }
        }

        It 'retourne null si le JSON est corrompu' {
            InModuleScope WindowsFirewallManager {
                ConvertFrom-FwmDescription -Description 'Texte [FWM]{ceci nest pas du json[/FWM]' |
                    Should -BeNullOrEmpty
            }
        }

        It 'retourne null si un champ obligatoire manque' {
            # Mieux vaut ignorer une regle au schema partiel que la manipuler
            # sur des donnees incompletes.
            InModuleScope WindowsFirewallManager {
                ConvertFrom-FwmDescription -Description 'Texte [FWM]{"v":1,"set":"X"}[/FWM]' |
                    Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'Resolve-FwmGroupName' {

    It 'prefixe le nom d ensemble' {
        InModuleScope WindowsFirewallManager {
            Resolve-FwmGroupName -SetName 'Spotify' | Should -Be '*FWM - Spotify'
        }
    }

    It 'supprime les espaces superflus' {
        InModuleScope WindowsFirewallManager {
            Resolve-FwmGroupName -SetName '  Spotify  ' | Should -Be '*FWM - Spotify'
        }
    }

    It 'refuse les caracteres generiques' {
        # Verifie sur machine reelle : Get-NetFirewallRule -Group '*' remonte
        # 527 des 578 regles. Un nom d'ensemble contenant un motif rendrait
        # la suppression incontrolable.
        InModuleScope WindowsFirewallManager {
            foreach ($bad in @('*', 'Spot*', 'Spot?fy', 'Game[1]')) {
                { Resolve-FwmGroupName -SetName $bad } | Should -Throw '*caracteres generiques*'
            }
        }
    }

    It 'refuse un nom vide' {
        InModuleScope WindowsFirewallManager {
            { Resolve-FwmGroupName -SetName '   ' } | Should -Throw
        }
    }

    It 'refuse un nom trop long' {
        InModuleScope WindowsFirewallManager {
            { Resolve-FwmGroupName -SetName ('a' * 65) } | Should -Throw '*64 caracteres*'
        }
    }
}
