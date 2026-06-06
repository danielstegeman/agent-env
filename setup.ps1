# apmenv setup
#
# PowerShell: Add to your $PROFILE:
#   . ~/apm-env-wrapper/setup.ps1
#
# Bash/Zsh: Add to your .bashrc / .zshrc:
#   source ~/apm-env-wrapper/setup.sh

# Create apmenv function that delegates to the script
function apmenv {
    & "$PSScriptRoot\apmenv.ps1" @args
}

# Show active env in prompt (optional — uncomment to enable)
# function prompt {
#     $env = & "$PSScriptRoot\apmenv.ps1" current 2>$null
#     if ($env -and $env -ne '(none)') {
#         Write-Host "[apm:$env] " -NoNewline -ForegroundColor Cyan
#     }
#     "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) "
# }
