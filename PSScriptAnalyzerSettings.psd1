@{
    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # Outil interactif : Write-Host est le bon outil pour un affichage
        # console destine a l'utilisateur, pas un flux a rediriger.
        'PSAvoidUsingWriteHost',

        # Le script d'entree est un programme interactif, pas un cmdlet a
        # composer dans un pipeline : -WhatIf/-Confirm n'ont pas de sens ici.
        # A reactiver quand le moteur sera extrait en module (phase 1), ou
        # les fonctions publiques devront supporter ShouldProcess.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
