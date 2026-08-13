function New-FwmRuleSet {
    <#
    .SYNOPSIS
        Cree un ensemble de regles de blocage pour les executables d'un logiciel.

    .DESCRIPTION
        Cree une regle de blocage par executable et par sens de trafic, toutes
        regroupees sous un meme groupe pare-feu et porteuses de metadonnees
        permettant de les retrouver et de les retirer en bloc.

        L'operation est idempotente : un executable deja couvert pour un sens
        donne dans cet ensemble est ignore, pas duplique.

        Necessite des droits administrateur.

    .PARAMETER SetName
        Nom de l'ensemble. Sert a construire le groupe pare-feu et figure dans
        le nom de chaque regle. Les caracteres generiques sont refuses.

    .PARAMETER Path
        Dossier du logiciel. Tous les .exe qu'il contient, sous-dossiers
        compris, seront bloques.

    .PARAMETER Executable
        Liste explicite d'executables a bloquer, en alternative a -Path.
        C'est ce que consommera l'interface graphique lorsque l'utilisateur
        decoche certains executables de la liste proposee.

    .PARAMETER Root
        Dossier de reference associe a l'ensemble lorsqu'on passe par
        -Executable. Par defaut, le repertoire parent commun est deduit du
        premier executable.

    .PARAMETER Direction
        Sens du trafic a bloquer. 'Both' par defaut.

    .EXAMPLE
        New-FwmRuleSet -SetName 'Spotify' -Path "$env:APPDATA\Spotify"

    .EXAMPLE
        New-FwmRuleSet -SetName 'Jeu' -Path 'D:\Jeu' -Direction Outbound -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'FromPath')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$SetName,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'FromPath')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'FromExecutable')]
        [ValidateNotNullOrEmpty()]
        [System.IO.FileInfo[]]$Executable,

        [Parameter(ParameterSetName = 'FromExecutable')]
        [string]$Root,

        [ValidateSet('Inbound', 'Outbound', 'Both')]
        [string]$Direction = 'Both'
    )

    # Valide le nom et construit le groupe. Leve si le nom est inexploitable.
    $group = Resolve-FwmGroupName -SetName $SetName
    $cleanName = $SetName.Trim()

    if ($PSCmdlet.ParameterSetName -eq 'FromPath') {
        # Le @() est indispensable : la sortie d'une fonction est deroulee,
        # zero executable donnerait $null et un seul un scalaire.
        $executables = @(Get-FwmExecutable -Path $Path)
        $rootPath = (Resolve-Path -LiteralPath $Path).Path
    }
    else {
        $executables = @($Executable)
        $rootPath = if ($PSBoundParameters.ContainsKey('Root')) {
            $Root
        }
        else {
            Split-Path -Path $executables[0].FullName -Parent
        }
    }

    if ($executables.Count -eq 0) {
        Write-Warning "Aucun executable trouve. Aucune regle creee pour l'ensemble '$cleanName'."
        return
    }

    $directions = if ($Direction -eq 'Both') { @('Inbound', 'Outbound') } else { @($Direction) }

    # Inventaire de l'existant pour rester idempotent. La comparaison porte
    # sur le couple (chemin, sens) et non sur le nom d'affichage : deux
    # logiciels possedant chacun un 'updater.exe' restent distincts.
    $existing = @{}
    foreach ($set in @(Get-FwmRuleSet -SetName $cleanName)) {
        foreach ($rule in $set.Rules) {
            $metadata = ConvertFrom-FwmDescription -Description $rule.Description
            if ($null -ne $metadata) {
                $existing["$($metadata.exe)|$($metadata.dir)"] = $true
            }
        }
    }

    $created = New-Object System.Collections.Generic.List[object]
    $skipped = 0
    $failed = 0

    foreach ($exe in $executables) {
        foreach ($dir in $directions) {
            $key = "$($exe.FullName)|$dir"
            if ($existing.ContainsKey($key)) {
                Write-Verbose "Deja couvert, ignore : $($exe.Name) ($dir)"
                $skipped++
                continue
            }

            $short = if ($dir -eq 'Inbound') { 'In' } else { 'Out' }
            $displayName = "$group - $($exe.Name) ($short)"

            if (-not $PSCmdlet.ShouldProcess($exe.FullName, "Bloquer le trafic $dir")) {
                continue
            }

            try {
                $description = ConvertTo-FwmDescription -SetName $cleanName `
                    -Root $rootPath `
                    -ExecutablePath $exe.FullName `
                    -Direction $dir

                $rule = New-NetFirewallRule -DisplayName $displayName `
                    -Direction $dir `
                    -Program $exe.FullName `
                    -Action Block `
                    -Profile Any `
                    -Group $group `
                    -Description $description `
                    -ErrorAction Stop

                $created.Add($rule)
                # Protege d'un doublon si le meme executable apparait deux
                # fois dans la liste fournie a -Executable.
                $existing[$key] = $true
                Write-Verbose "Cree : $displayName"
            }
            catch {
                Write-Error "Echec de la creation de '$displayName' : $_"
                $failed++
            }
        }
    }

    [PSCustomObject]@{
        PSTypeName = 'Fwm.RuleSetResult'
        SetName    = $cleanName
        Group      = $group
        Root       = $rootPath
        Created    = $created.Count
        Skipped    = $skipped
        Failed     = $failed
        # .ToArray() et non @(...) : encadrer une List[object] d'un @() dans
        # un litteral de table de hachage leve "Argument types do not match".
        Rules      = $created.ToArray()
    }
}
