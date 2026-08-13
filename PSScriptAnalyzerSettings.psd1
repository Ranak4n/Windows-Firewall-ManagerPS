@{
    Severity = @('Error', 'Warning')

    # Aucune exclusion.
    #
    # Les deux regles ecartees pendant la phase CLI ne le sont plus :
    #   - PSAvoidUsingWriteHost : le moteur ne produit plus d'affichage, il
    #     retourne des objets. L'interface graphique n'ecrit pas en console.
    #   - PSUseShouldProcessForStateChangingFunctions : New-FwmRuleSet et
    #     Remove-FwmRuleSet declarent SupportsShouldProcess et honorent
    #     -WhatIf et -Confirm.
    ExcludeRules = @()
}
