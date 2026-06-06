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

## Testing

The test suite below verifies installing, switching, and deploying to both `copilot` and `claude` targets.
Two environments are used: `agent-framework` (real package) and `hello-world` (minimal test package at `~/source/hello-world-agent`).

### 1 — Baseline: verify both environments exist

```powershell
apmenv list
# Expected: agent-framework and hello-world listed
```

### 2 — Install into hello-world (copilot target)

```powershell
apmenv activate hello-world
apmenv install C:\Users\danielst\source\hello-world-agent
# Expected output contains:
#   Targets: copilot  (source: --target flag)
#   1 agents integrated -> .github/agents/
#   1 skill(s) integrated -> .agents/skills/
```

### 3 — Verify copilot files were deployed

```powershell
apmenv activate hello-world
# Expected: .agent-context\.github\agents\hello-world.agent.md exists
Test-Path "$env:USERPROFILE\.agent-context\.github\agents\hello-world.agent.md"   # True
Test-Path "$env:USERPROFILE\.agent-context\.agents\skills\hello-skill\SKILL.md"   # True
```

### 4 — Switch to agent-framework and verify isolation

```powershell
apmenv activate agent-framework
apmenv current   # agent-framework

# agent-framework's agent should be present, hello-world's should NOT
Test-Path "$env:USERPROFILE\.agent-context\.github\agents\code-first-agent.agent.md"  # True
Test-Path "$env:USERPROFILE\.agent-context\.github\agents\hello-world.agent.md"       # False
```

### 5 — Switch back to hello-world and verify restore

```powershell
apmenv activate hello-world
Test-Path "$env:USERPROFILE\.agent-context\.github\agents\hello-world.agent.md"       # True
Test-Path "$env:USERPROFILE\.agent-context\.github\agents\code-first-agent.agent.md"  # False
```

### 6 — Test claude target override on activate

```powershell
apmenv activate hello-world --target claude
# Expected output contains:
#   Targets: claude
#   Targets: claude  (source: --target flag)
```

### 7 — Install with explicit claude target (overrides saved default)

```powershell
apmenv activate hello-world
apmenv install C:\Users\danielst\source\hello-world-agent --target claude
# Expected output contains:
#   Targets: claude  (source: --target flag)
```

### 8 — Install with both targets simultaneously

```powershell
apmenv activate hello-world
apmenv install C:\Users\danielst\source\hello-world-agent --target copilot,claude
# Expected: files deployed for both runtimes inside the env folder
# Note: use quotes or the --target flag once — PowerShell's comma operator
#       is handled automatically by apmenv.
```

Verify inside the environment folder:

```powershell
Test-Path "$env:USERPROFILE\.apm-envs\hello-world\.github\agents\hello-world.agent.md"  # True (copilot)
Test-Path "$env:USERPROFILE\.apm-envs\hello-world\.claude\agents\hello-world.md"         # True (claude)
```

### 9 — Verify saved target is restored after explicit override

```powershell
# After step 7 or 8, run again without --target
apmenv install C:\Users\danielst\source\hello-world-agent
# Expected: Targets: copilot  (the saved default, not claude)
```

### 10 — Deactivate and verify cleanup

```powershell
apmenv deactivate
apmenv current    # (none)
Test-Path "$env:USERPROFILE\.agent-context"   # False (output folder cleared)
```
