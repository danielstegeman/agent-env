# apm-env-wrapper

Environment manager for APM (Agent Package Manager). Think `pyenv`/`nvm` but for agent configurations — manage named profiles of agent/skill setups and deploy them via `apm`.

## Installation

### Windows (PowerShell)

Run this once to permanently add the scripts directory to your user `PATH`:

```powershell
[Environment]::SetEnvironmentVariable(
    'PATH',
    [Environment]::GetEnvironmentVariable('PATH', 'User') + ";$HOME\apm-env-wrapper",
    'User'
)
```

Restart your terminal, then `apmenv` will work from anywhere.

### Linux / macOS

Make the script executable and add the directory to your `PATH`:

```bash
chmod +x ~/apm-env-wrapper/apmenv.sh
ln -s ~/apm-env-wrapper/apmenv.sh ~/.local/bin/apmenv
```

If `~/.local/bin` is not already in your `PATH`, add this to your `~/.bashrc` or `~/.zshrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Then reload:

```bash
source ~/.bashrc   # or source ~/.zshrc
```

---

Once set up, `apmenv` will be available as a command in any new terminal session.

