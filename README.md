# Windows Firewall Manager

[![CI](https://github.com/Ranak4n/Windows-Firewall-ManagerPS/actions/workflows/ci.yml/badge.svg)](https://github.com/Ranak4n/Windows-Firewall-ManagerPS/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PowerShell 7+](https://img.shields.io/badge/PowerShell-7%2B-5391FE.svg)](https://github.com/PowerShell/PowerShell)

Priver un logiciel d'accès Internet ne devrait pas prendre vingt minutes.

Sous Windows, bloquer un programme au pare-feu demande de passer par `wf.msc`,
d'y créer une règle, de la nommer, de pointer l'exécutable, de choisir le sens
du trafic — puis de tout recommencer pour le sens inverse. Multipliez par les
huit exécutables que contient un logiciel moderne (le lanceur, la mise à jour,
le service, les helpers) et vous y passez la soirée.

Cet outil fait la même chose en trois clics : vous désignez le dossier du
logiciel, il détecte tous les `.exe` récursivement et crée les règles de
blocage entrantes et sortantes, regroupées sous un nom commun pour pouvoir
les gérer — ou les retirer — en bloc.

## Prérequis

- Windows 10 / 11
- **PowerShell 7+** pour l'interface graphique (thread STA et sélecteur de
  dossier .NET 8+). Le module seul fonctionne aussi sous Windows PowerShell 5.1
- **Droits administrateur** pour créer ou supprimer des règles. La consultation
  fonctionne sans élévation

## Installation

```powershell
git clone https://github.com/Ranak4n/Windows-Firewall-ManagerPS.git
cd Windows-Firewall-ManagerPS
```

## Utilisation

Double-cliquez sur `tools\Start-FirewallManager.cmd` — il demande l'élévation
et ouvre l'interface.

**Créer un blocage** : bouton *Nouveau blocage* → choisissez le dossier du
logiciel dans le sélecteur Windows → la liste des exécutables trouvés
s'affiche, cochez ceux à bloquer (décochez `uninstall.exe` si vous préférez
le laisser tranquille) → nommez l'ensemble → *Créer les règles*.

**Retirer un blocage** : sélectionnez un ou plusieurs ensembles dans la liste
principale, puis *Supprimer la sélection*. Une seule confirmation, quel que
soit le nombre de règles.

Lancée sans élévation, l'interface affiche l'inventaire en lecture seule et
propose un bouton pour se relancer en administrateur.

Les groupes de règles sont préfixés par `*` afin de remonter en tête de liste
dans `wf.msc`. Seules les règles portant les métadonnées de l'outil sont
listées et supprimables : les règles système ne peuvent pas être ciblées par
erreur.

## Le module

Le moteur est isolé dans un module PowerShell sans dépendance à l'affichage :
il retourne des objets, que la CLI, l'interface graphique et les tests
consomment indifféremment.

```powershell
Import-Module .\src\WindowsFirewallManager\WindowsFirewallManager.psd1

# Bloquer tous les exécutables d'un logiciel, entrant et sortant
New-FwmRuleSet -SetName 'Spotify' -Path "$env:APPDATA\Spotify"

# Voir ce qui serait fait, sans rien créer
New-FwmRuleSet -SetName 'Jeu' -Path 'D:\Jeu' -Direction Outbound -WhatIf

# Ne bloquer qu'une sélection d'exécutables
$exes = @(Get-FwmExecutable -Path 'D:\Jeu' | Where-Object Name -ne 'launcher.exe')
New-FwmRuleSet -SetName 'Jeu' -Executable $exes

# Inventorier (aucune élévation nécessaire)
Get-FwmRuleSet | Format-Table SetName, RuleCount, Inbound, Outbound, Enabled

# Retirer un ensemble
Remove-FwmRuleSet -SetName 'Spotify'
```

| Fonction | Rôle |
|---|---|
| `New-FwmRuleSet` | Crée les règles de blocage. Idempotent, supporte `-WhatIf` |
| `Get-FwmRuleSet` | Inventorie les ensembles. Lecture seule, sans élévation |
| `Remove-FwmRuleSet` | Supprime un ensemble, règle par règle, par identifiant unique |
| `Get-FwmExecutable` | Liste les `.exe` d'un dossier |
| `Test-FwmElevation` | Indique si la session est élevée |

### Identification des règles

Chaque règle porte un bloc de métadonnées dans sa description :

```
Blocage sortant de Spotify.exe (ensemble 'Spotify'). Créé par Windows
Firewall Manager. [FWM]{"v":1,"set":"Spotify","root":"...","exe":"...",
"dir":"Outbound","created":"2026-08-13T21:00:00Z"}[/FWM]
```

C'est ce qui permet d'identifier nos règles avec certitude — une règle sans ce
bloc, ou au bloc incomplet, est toujours ignorée — et de retrouver le dossier
d'origine pour la resynchronisation prévue en phase 3.

## Feuille de route

- [x] **Phase 0** — corriger et sécuriser la version CLI existante
- [x] **Phase 1** — moteur extrait en module PowerShell testable
- [x] **Phase 2** — interface graphique WPF ; la CLI est retirée
- [ ] **Phase 3** — resynchronisation après mise à jour d'un logiciel,
      activation/désactivation temporaire, export/import JSON, annulation

L'ancienne CLI reste consultable dans l'historique git (`git show 6818794`).

## Notes techniques

**Précédence des règles.** Sous Windows Firewall, une règle *Block* l'emporte
sur une règle *Allow* de même portée. Bloquer un exécutable déjà autorisé par
ailleurs fonctionne donc comme attendu.

**Blocage par chemin.** Les règles ciblent l'exécutable par son chemin absolu.
Si le logiciel se met à jour en ajoutant un nouvel exécutable, celui-ci n'est
pas couvert — d'où la resynchronisation prévue en phase 3. Un logiciel
déplacé ou réinstallé ailleurs échappe également à ses règles.

**Applications du Microsoft Store.** Les applications UWP/AppX ne se bloquent
pas par chemin d'exécutable : elles nécessitent le SID de leur package. Elles
ne sont pas prises en charge à ce jour.

## Développement

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -SkipPublisherCheck

Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
Invoke-Pester -Path .\tests
```

`-SkipPublisherCheck` est nécessaire : Windows livre une version 3.x de Pester
signée par Microsoft, et l'installation d'une 5.x côte à côte est sinon
refusée pour cause de signataire différent.

Les tests n'écrivent **jamais** dans le pare-feu : `New-NetFirewallRule`,
`Get-NetFirewallRule` et `Remove-NetFirewallRule` sont interceptés par des
mocks, et l'on vérifie que le module les appelle avec les bons paramètres.
C'est la seule façon raisonnable de tester du code qui, exécuté pour de vrai,
modifierait la configuration réseau de la machine.

L'interface est couverte elle aussi : les fichiers XAML sont chargés pour de
bon par `XamlReader`, et chaque nom d'élément demandé par `FindName` dans le
code est confronté aux `x:Name` déclarés dans le balisage. Une faute de frappe
qui ne se verrait qu'au clic est ainsi rattrapée par la CI.

### Arborescence

```
src/WindowsFirewallManager/   moteur (module, aucune dépendance à l'affichage)
src/Gui/                      interface WPF (XAML + câblage PowerShell)
tests/                        suite Pester
tools/                        lanceur avec élévation
```

La CI (GitHub Actions, `windows-latest`) vérifie la syntaxe, passe
PSScriptAnalyzer et exécute la suite Pester à chaque push.

## Licence

[MIT](LICENSE)
