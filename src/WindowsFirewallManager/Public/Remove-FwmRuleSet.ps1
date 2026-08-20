function Remove-FwmRuleSet {
    <#
    .SYNOPSIS
        Supprime un ensemble de regles et toutes les regles qu'il contient.

    .DESCRIPTION
        Ne supprime que des regles portant des metadonnees FWM valides, et
        les supprime une par une via leur nom unique.

        Le nom d'ensemble est compare en egalite stricte, jamais en motif :
        les cmdlets NetSecurity interpretent les caracteres generiques cote
        pare-feu, ou 'Remove-NetFirewallRule -Group *' effacerait la quasi-
        totalite des regles de la machine.

        Necessite des droits administrateur.

    .PARAMETER SetName
        Nom exact de l'ensemble a supprimer. Accepte l'entree par pipeline
        depuis Get-FwmRuleSet.

    .PARAMETER Notify
        Bloc de script appele apres chaque regle traitee, avec un objet
        portant Status ('Removed' ou 'Failed') et DisplayName.

        Destine aux interfaces : l'operation etant synchrone, c'est le seul
        moyen d'afficher l'avancement plutot que d'attendre le bilan final.

    .EXAMPLE
        Remove-FwmRuleSet -SetName 'Spotify'

    .EXAMPLE
        Get-FwmRuleSet -SetName 'Test*' | Remove-FwmRuleSet -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Notify est invoque depuis le bloc $report, que l''analyseur n''inspecte pas.')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$SetName,

        [scriptblock]$Notify
    )

    process {
        $target = $SetName.Trim()

        $report = {
            param([string]$Status, [string]$DisplayName)

            if (-not $Notify) { return }

            & $Notify ([PSCustomObject]@{
                    Status      = $Status
                    DisplayName = $DisplayName
                })
        }

        # Egalite stricte, cote client : aucun motif ne peut elargir la cible.
        $sets = @(Get-FwmRuleSet | Where-Object { $_.SetName -eq $target })

        if ($sets.Count -eq 0) {
            Write-Warning "Aucun ensemble nomme '$target'."
            return
        }

        $removed = 0
        $failed = 0

        foreach ($set in $sets) {
            # Confirmation au niveau de l'ensemble et non de la regle : un
            # ensemble de 12 regles ne doit pas declencher 12 invites.
            $action = "Supprimer l'ensemble et ses $($set.RuleCount) regle(s)"
            if (-not $PSCmdlet.ShouldProcess($set.SetName, $action)) {
                continue
            }

            foreach ($rule in $set.Rules) {
                try {
                    # Suppression par -Name, identifiant unique de la regle.
                    # Jamais par -Group, qui accepte les caracteres generiques.
                    Remove-NetFirewallRule -Name $rule.Name -ErrorAction Stop
                    $removed++
                    Write-Verbose "Supprimee : $($rule.DisplayName)"
                    & $report 'Removed' $rule.DisplayName
                }
                catch {
                    Write-Error "Echec de la suppression de '$($rule.DisplayName)' : $_"
                    $failed++
                    & $report 'Failed' $rule.DisplayName
                }
            }
        }

        [PSCustomObject]@{
            PSTypeName = 'Fwm.RemoveResult'
            SetName    = $target
            Removed    = $removed
            Failed     = $failed
        }
    }
}
