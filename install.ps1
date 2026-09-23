# Fable Toolkit installer for Windows PowerShell 5.1 and PowerShell 7.
#
#   irm https://raw.githubusercontent.com/ddivyanshsharmaa/fable-toolkit/main/install.ps1 | iex
#
# Copies the skills and agents into your Claude Code config folder, backing up anything it
# replaces, then checks which AI engines this machine can use. On Windows this is more reliable
# than Claude Code's plugin install from GitHub, which can fail there with a file lock
# (EBUSY or EPERM while renaming the downloaded folder).
#
# Optional environment variables:
#   FABLE_TOOLKIT_MODE=plugin   use Claude Code's plugin system instead of copying files
#   FABLE_TOOLKIT_REF=<branch>  install another branch (default: main)
#   FABLE_TOOLKIT_SRC=<folder>  install from a local checkout instead of GitHub
#   FABLE_TOOLKIT_CODEX=yes|no  answer the Codex question in advance (unattended installs)
#   FABLE_TOOLKIT_AGY=yes|no    answer the Antigravity question in advance
#   CLAUDE_CONFIG_DIR           respected, same as Claude Code itself
#
# At the end it asks three questions (Claude Code, Codex, Antigravity), saves the answers, and
# shows who will do what. Change them any time by running the installer again.
#
# Everything runs inside one function, so a partial download never runs, preferences in your
# session stay untouched, and a failure never closes your PowerShell window.

function Install-FableToolkit {
    $ErrorActionPreference = 'Continue'
    $ProgressPreference = 'SilentlyContinue'

    $repo = 'ddivyanshsharmaa/fable-toolkit'
    $ref = 'main'
    if ($env:FABLE_TOOLKIT_REF) { $ref = $env:FABLE_TOOLKIT_REF }
    $mode = 'copy'
    if ($env:FABLE_TOOLKIT_MODE) { $mode = $env:FABLE_TOOLKIT_MODE }
    $src = $env:FABLE_TOOLKIT_SRC
    $configDir = Join-Path $HOME '.claude'
    if ($env:CLAUDE_CONFIG_DIR) { $configDir = $env:CLAUDE_CONFIG_DIR }
    $workDir = $null

    function Write-Failure($message) {
        Write-Host ''
        Write-Host "Install failed: $message" -ForegroundColor Red
    }

    # True when two files, or two folders file by file, have identical content.
    function Test-SameContent($a, $b) {
        if (-not (Test-Path -LiteralPath $b)) { return $false }
        $aIsDir = Test-Path -LiteralPath $a -PathType Container
        $bIsDir = Test-Path -LiteralPath $b -PathType Container
        if ($aIsDir -ne $bIsDir) { return $false }
        if (-not $aIsDir) {
            return (Get-FileHash -LiteralPath $a).Hash -eq (Get-FileHash -LiteralPath $b).Hash
        }
        $listing = {
            param($root)
            $base = (Resolve-Path -LiteralPath $root).ProviderPath.TrimEnd('\', '/')
            Get-ChildItem -LiteralPath $base -Recurse -File | ForEach-Object {
                $_.FullName.Substring($base.Length).TrimStart('\', '/') + '|' + (Get-FileHash -LiteralPath $_.FullName).Hash
            } | Sort-Object
        }
        return ((& $listing $a) -join "`n") -eq ((& $listing $b) -join "`n")
    }

    Write-Host 'Fable Toolkit installer'
    Write-Host ''

    if ($mode -ne 'copy' -and $mode -ne 'plugin') {
        Write-Failure "FABLE_TOOLKIT_MODE must be plugin or copy, not '$mode'"
        return
    }

    $claude = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claude) {
        Write-Host 'Claude Code is not on your PATH yet. The toolkit will be ready the moment you install it:'
        Write-Host '  https://code.claude.com/docs/en/setup'
        Write-Host ''
        if ($mode -eq 'plugin') {
            Write-Failure 'plugin mode needs Claude Code installed first.'
            return
        }
    }

    try {
        if ($mode -eq 'plugin') {
            $marketSrc = $repo
            if ($src) { $marketSrc = $src } elseif ($ref -ne 'main') { $marketSrc = "$repo@$ref" }

            $markets = (& claude plugin marketplace list 2>$null | Out-String)
            if ($markets -match 'fable-toolkit') {
                Write-Host 'Refreshing the fable-toolkit marketplace...'
                & claude plugin marketplace update fable-toolkit
            }
            else {
                Write-Host "Adding the fable-toolkit marketplace from $marketSrc..."
                & claude plugin marketplace add $marketSrc
            }
            if ($LASTEXITCODE -ne 0) {
                Write-Failure 'Claude Code could not add the marketplace. Rerun without FABLE_TOOLKIT_MODE to install by copying files.'
                return
            }

            $plugins = (& claude plugin list 2>$null | Out-String)
            if ($plugins -match 'fable-toolkit@fable-toolkit') {
                Write-Host 'Updating the plugin...'
                & claude plugin update fable-toolkit@fable-toolkit
            }
            else {
                Write-Host 'Installing the plugin...'
                & claude plugin install fable-toolkit@fable-toolkit
            }
            if ($LASTEXITCODE -ne 0) {
                Write-Failure 'Claude Code could not install the plugin. Rerun without FABLE_TOOLKIT_MODE to install by copying files.'
                return
            }
        }
        else {
            if (-not $src) {
                try {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
                }
                catch { }
                $workDir = Join-Path ([IO.Path]::GetTempPath()) ('fable-toolkit-' + [guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Path $workDir -Force | Out-Null
                $zip = Join-Path $workDir 'toolkit.zip'
                Write-Host "Downloading $repo ($ref)..."
                try {
                    Invoke-WebRequest -Uri "https://github.com/$repo/archive/refs/heads/$ref.zip" -OutFile $zip -UseBasicParsing -ErrorAction Stop
                    Expand-Archive -LiteralPath $zip -DestinationPath $workDir -Force -ErrorAction Stop
                }
                catch {
                    Write-Failure "could not download https://github.com/$repo (branch $ref): $($_.Exception.Message)"
                    return
                }
                $src = Get-ChildItem -LiteralPath $workDir -Directory | Select-Object -First 1 -ExpandProperty FullName
            }
            if (-not $src -or -not (Test-Path -LiteralPath (Join-Path $src 'skills'))) {
                Write-Failure "no skills folder found in $src"
                return
            }

            $backup = Join-Path $configDir ('fable-toolkit-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
            $count = @{ placed = 0; same = 0; moved = 0 }

            # Identical copies are left alone. Anything different moves to a backup folder outside
            # skills and agents, so Claude Code never loads an old copy next to the new one.
            $place = {
                param($kind, $item)
                $kindDir = Join-Path $configDir $kind
                $to = Join-Path $kindDir $item.Name
                if (Test-Path -LiteralPath $to) {
                    if (Test-SameContent $item.FullName $to) {
                        $count.same++
                        return
                    }
                    $backupKind = Join-Path $backup $kind
                    New-Item -ItemType Directory -Path $backupKind -Force | Out-Null
                    Move-Item -LiteralPath $to -Destination (Join-Path $backupKind $item.Name)
                    $count.moved++
                }
                Copy-Item -LiteralPath $item.FullName -Destination $to -Recurse -Force
                $count.placed++
            }

            New-Item -ItemType Directory -Path (Join-Path $configDir 'skills') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $configDir 'agents') -Force | Out-Null
            Get-ChildItem -LiteralPath (Join-Path $src 'skills') -Directory | ForEach-Object { & $place 'skills' $_ }
            Get-ChildItem -LiteralPath (Join-Path $src 'agents') -Filter '*.md' -File | ForEach-Object { & $place 'agents' $_ }

            $method = Join-Path $src 'FABLE-METHOD.md'
            if (Test-Path -LiteralPath $method) {
                $methodTo = Join-Path $configDir 'FABLE-METHOD.md'
                if ((Test-Path -LiteralPath $methodTo) -and -not (Test-SameContent $method $methodTo)) {
                    New-Item -ItemType Directory -Path $backup -Force | Out-Null
                    Move-Item -LiteralPath $methodTo -Destination (Join-Path $backup 'FABLE-METHOD.md')
                    $count.moved++
                }
                Copy-Item -LiteralPath $method -Destination $methodTo -Force
            }

            Write-Host "Installed into ${configDir}: $($count.placed) updated, $($count.same) already up to date."
            if ($count.moved -gt 0) {
                Write-Host "Your previous versions of $($count.moved) item(s) are saved in $backup"
            }
            Write-Host 'Optional: to load the Fable operating manual in every session, add this line to'
            Write-Host "  $(Join-Path $configDir 'CLAUDE.md') :   @FABLE-METHOD.md"
        }

        # Three questions, then save the answers and show who does what. Claude Code on Windows runs
        # its Bash tool through Git Bash, so the same configure script the /team skill uses runs here.
        Write-Host ''
        Write-Host 'Fable Toolkit engine setup'
        Write-Host 'Three quick questions. Press Enter to accept the detected answer.'
        Write-Host ''

        $answers = $null
        if ($env:FABLE_TOOLKIT_ANSWERS -and (Test-Path -LiteralPath $env:FABLE_TOOLKIT_ANSWERS)) {
            $answers = New-Object System.Collections.Queue
            Get-Content -LiteralPath $env:FABLE_TOOLKIT_ANSWERS | ForEach-Object { $answers.Enqueue($_) }
        }
        $askYesNo = {
            param($question, $default)
            $hint = '[Y/n]'
            if ($default -eq 'no') { $hint = '[y/N]' }
            while ($true) {
                $reply = $null
                if ($answers) {
                    if ($answers.Count -gt 0) { $reply = [string]$answers.Dequeue() } else { $reply = '' }
                    Write-Host "$question $hint $reply"
                }
                else {
                    try { $reply = Read-Host "$question $hint" } catch { return $default }
                }
                if ($null -eq $reply) { return $default }
                $reply = $reply.Trim()
                if ($reply -eq '') { return $default }
                if ($reply -match '^(y|yes)$') { return 'yes' }
                if ($reply -match '^(n|no)$') { return 'no' }
                Write-Host 'Please answer y or n.'
            }
        }
        $normalize = {
            param($value)
            if ($value -match '^(y|yes)$') { return 'yes' }
            if ($value -match '^(n|no)$') { return 'no' }
            return $null
        }
        $codexState = {
            $cmd = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $cmd) { return 'missing' }
            # Codex prints its login status on stderr, so capture both streams as plain text.
            $out = ((& $cmd.Source login status 2>&1 | ForEach-Object { "$_" }) -join "`n")
            if ($out -match 'not logged in') { return 'not-signed-in' }
            if ($out -match 'logged in') { return 'ready' }
            return 'not-signed-in'
        }

        $detectedClaude = 'no'
        if (Get-Command claude -ErrorAction SilentlyContinue) { $detectedClaude = 'yes' }
        $codexNow = & $codexState
        $agyFound = 'no'
        if (Get-Command agy -ErrorAction SilentlyContinue) { $agyFound = 'yes' }

        $claudeLabel = 'installed'
        if ($detectedClaude -eq 'no') { $claudeLabel = 'not installed' }
        $useClaude = & $askYesNo "Do you use Claude Code? (detected: $claudeLabel)" $detectedClaude
        if ($useClaude -eq 'no' -or $detectedClaude -eq 'no') {
            Write-Host '  The team runs inside Claude Code, which needs a Claude subscription or API key.'
            Write-Host '  Install it from https://code.claude.com/docs/en/setup ; everything here is ready for it.'
        }

        $useCodex = & $normalize $env:FABLE_TOOLKIT_CODEX
        if (-not $useCodex) {
            $label = 'not installed'
            $default = 'no'
            if ($codexNow -eq 'ready') { $label = 'installed and signed in'; $default = 'yes' }
            if ($codexNow -eq 'not-signed-in') { $label = 'installed, not signed in'; $default = 'yes' }
            $useCodex = & $askYesNo "Do you use Codex, OpenAI's coding agent? (detected: $label)" $default
        }
        if ($useCodex -eq 'yes') {
            if ($codexNow -eq 'missing') {
                Write-Host '  Codex is not installed yet: https://developers.openai.com/codex/cli'
                Write-Host '  The team starts using it by itself once it is installed and signed in.'
            }
            elseif ($codexNow -eq 'not-signed-in') {
                if ((& $askYesNo '  Sign in to Codex now? It opens a browser.' 'yes') -eq 'yes') {
                    if ($answers) { Write-Host '  (answers file in use, so skipping the real sign-in)' }
                    else { & codex login }
                    $codexNow = & $codexState
                }
                if ($codexNow -ne 'ready') {
                    Write-Host '  Codex is not signed in yet. Run: codex login'
                    Write-Host '  Until then the team works without it and picks it up by itself afterwards.'
                }
            }
        }

        $useAgy = & $normalize $env:FABLE_TOOLKIT_AGY
        if (-not $useAgy) {
            $label = 'not installed'
            $default = 'no'
            if ($agyFound -eq 'yes') { $label = 'installed'; $default = 'yes' }
            $useAgy = & $askYesNo "Do you use Antigravity, Google's agent CLI? (detected: $label)" $default
        }
        if ($useAgy -eq 'yes' -and $agyFound -eq 'no') {
            Write-Host '  Antigravity is not installed yet: https://antigravity.google'
            Write-Host '  The team starts using it by itself once it is installed and signed in.'
        }

        $configure = $null
        if ($mode -eq 'copy') {
            $configure = Join-Path $configDir 'skills\team\scripts\configure.sh'
        }
        else {
            $cache = Join-Path $configDir 'plugins\cache'
            if (Test-Path -LiteralPath $cache) {
                $configure = Get-ChildItem -LiteralPath $cache -Recurse -Filter 'configure.sh' -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -match 'fable-toolkit' } |
                    Sort-Object FullName | Select-Object -Last 1 -ExpandProperty FullName
            }
        }
        $bash = $null
        if ($env:CLAUDE_CODE_GIT_BASH_PATH -and (Test-Path -LiteralPath $env:CLAUDE_CODE_GIT_BASH_PATH)) {
            $bash = $env:CLAUDE_CODE_GIT_BASH_PATH
        }
        if (-not $bash) {
            $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($git) {
                $candidate = Join-Path (Split-Path (Split-Path $git.Source)) 'bin\bash.exe'
                if (Test-Path -LiteralPath $candidate) { $bash = $candidate }
            }
        }

        if (-not $bash -and ($useCodex -eq 'yes' -or $useAgy -eq 'yes')) {
            Write-Host ''
            Write-Host '  Codex and Antigravity run through Git Bash, which comes with Git for Windows (free):'
            Write-Host '  https://git-scm.com/downloads/win'
            Write-Host '  Until it is installed the team works with Claude alone. Once it is, restart Claude Code'
            Write-Host '  and your engines take over by themselves; nothing needs to be set up again.'
        }

        Write-Host ''
        if ($configure -and (Test-Path -LiteralPath $configure) -and $bash) {
            # Both answers are passed in, so the script saves without asking again, then reports.
            & $bash $configure --codex $useCodex --agy $useAgy 2>$null | ForEach-Object { Write-Host $_ }
        }
        else {
            # No Git Bash: save the same file directly. UTF-8 without a byte order mark and LF line
            # endings, because a BOM breaks the first line for the bash scripts that read it.
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
            $conf = Join-Path $configDir 'fable-toolkit.conf'
            $text = "# Fable Toolkit engine setup, saved $(Get-Date -Format 'yyyy-MM-dd') by install.ps1.`n" +
                "# yes: use this engine whenever it is signed in. no: never use it.`n" +
                "FABLE_USE_CODEX=$useCodex`nFABLE_USE_AGY=$useAgy`n"
            [IO.File]::WriteAllText($conf, $text, (New-Object Text.UTF8Encoding $false))
            Write-Host "Saved to $conf"
            Write-Host 'The full engine check runs the first time you ask Claude Code to use the team.'
        }

        Write-Host ''
        Write-Host 'Done. Start a new Claude Code session in any project and just ask, for example:'
        Write-Host '  use the team to add CSV export to the reports page, with tests'
        Write-Host 'It works out which engines you have and runs the right loop on its own.'
        Write-Host ''
        if ($mode -eq 'plugin') {
            Write-Host 'Update later:  claude plugin marketplace update fable-toolkit'
            Write-Host '               claude plugin update fable-toolkit@fable-toolkit'
            Write-Host 'Uninstall:     claude plugin uninstall fable-toolkit@fable-toolkit'
        }
        else {
            Write-Host 'Update later by running the same install command again.'
        }
        Write-Host 'Change which engines the team uses: run the installer again, or ask Claude Code to'
        Write-Host 'reconfigure the team.'
    }
    finally {
        if ($workDir -and (Test-Path -LiteralPath $workDir)) {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Install-FableToolkit
Remove-Item -Path Function:\Install-FableToolkit -ErrorAction SilentlyContinue
