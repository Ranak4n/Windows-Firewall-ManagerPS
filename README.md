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

## Statut

🚧 **En refonte.** La version CLI actuelle est fonctionnelle. Une interface
graphique WPF et un moteur extrait en module PowerShell sont en cours.

## Prérequis

- Windows 10 / 11
- PowerShell 7+ (recommandé) ou Windows PowerShell 5.1
- **Droits administrateur** — toute modification de règle pare-feu les exige

## Installation

```powershell
git clone https://github.com/Ranak4n/Windows-Firewall-ManagerPS.git
cd Windows-Firewall-ManagerPS
```

## Utilisation

Double-cliquez sur `Start-Scripts.cmd` (il demande l'élévation), ou depuis un
terminal administrateur :

```powershell
pwsh -File .\Firewall-Manager.ps1
```

Le menu propose :

| Choix | Action |
|-------|--------|
| 1 | Créer les règles **entrantes** pour tous les `.exe` d'un dossier |
| 2 | Créer les règles **sortantes** |
| 3 | Créer les règles **entrantes et sortantes** |
| 4 | Supprimer un groupe de règles et toutes les règles qu'il contient |
| 5 | Quitter |

Les groupes de règles sont préfixés par `*` afin de remonter en tête de liste
dans `wf.msc`. Seuls ces groupes sont proposés à la suppression : les règles
système ne peuvent pas être ciblées par erreur.

## Feuille de route

- [x] **Phase 0** — corriger et sécuriser la version CLI existante
- [ ] **Phase 1** — extraire le moteur en module PowerShell testable (Pester)
- [ ] **Phase 2** — interface graphique WPF (sélecteur de dossier natif,
      liste des ensembles, sélection multiple à la suppression)
- [ ] **Phase 3** — resynchronisation après mise à jour d'un logiciel,
      activation/désactivation temporaire, export/import JSON, annulation

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
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

La CI (GitHub Actions, `windows-latest`) vérifie la syntaxe, passe
PSScriptAnalyzer et exécutera les tests Pester dès qu'ils existeront.

## Licence

[MIT](LICENSE)
