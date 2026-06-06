#!/usr/bin/env bash
set -euo pipefail

APM_DIR="/mnt/c/Users/danielst/AppData/Local/Microsoft/WinGet/Packages/Microsoft.APM_Microsoft.Winget.Source_8wekyb3d8bbwe/apm-windows-x86_64"
SCRIPT_DIR="/mnt/c/Users/danielst/apm-env-wrapper"
HW_PKG="C:\\Users\\danielst\\source\\hello-world-agent"
AF_PKG="C:\\Users\\danielst\\source\\agent-framework-starter"

# Create a thin wrapper so subshells can call 'apm' without the .exe extension
TMPBIN="$(mktemp -d)"
printf '#!/usr/bin/env bash\nexec "%s/apm.exe" "$@"\n' "$APM_DIR" > "$TMPBIN/apm"
chmod +x "$TMPBIN/apm"
export PATH="$TMPBIN:$PATH"

# Verify the wrapper works before running tests
apm --version >/dev/null

# Redirect HOME so tests don't clobber the real ~/.apm-envs
export HOME_BAK="$HOME"
export TEST_HOME="$(mktemp -d)"
export HOME="$TEST_HOME"

source "$SCRIPT_DIR/setup.sh"

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT_CODE=1; }
EXIT_CODE=0

echo ""
echo "=== TEST 1: create two environments ==="
apmenv create agent-framework
apmenv create hello-world
apmenv list 2>&1 | tee /tmp/list_out.txt
grep -q "agent-framework" /tmp/list_out.txt && pass "agent-framework listed" || fail "agent-framework not listed"
grep -q "hello-world"     /tmp/list_out.txt && pass "hello-world listed"     || fail "hello-world not listed"

echo ""
echo "=== TEST 2: install into hello-world (auto copilot target) ==="
apmenv activate hello-world
apmenv setup --targets copilot
apmenv install "$HW_PKG" 2>&1 | tee /tmp/install_out.txt
grep -q "Targets: copilot" /tmp/install_out.txt && pass "copilot target injected" || fail "copilot target not injected"
grep -q "agents integrated\|agents adopted" /tmp/install_out.txt && pass "agent deployed" || fail "agent not deployed"
grep -q "skill" /tmp/install_out.txt && pass "skill deployed" || fail "skill not deployed"

echo ""
echo "=== TEST 3: verify copilot files in env folder ==="
test -f "$TEST_HOME/.apm-envs/hello-world/.github/agents/hello-world.agent.md" && pass "agent file exists" || fail "agent file missing"
test -f "$TEST_HOME/.apm-envs/hello-world/.agents/skills/hello-skill/SKILL.md" && pass "skill file exists" || fail "skill file missing"

echo ""
echo "=== TEST 4: switch to agent-framework, verify isolation ==="
apmenv activate agent-framework
apmenv install "$AF_PKG" 2>&1 | tee /tmp/af_out.txt
grep -q "agents integrated\|agents adopted" /tmp/af_out.txt && pass "agent-framework agent deployed" || fail "agent-framework agent not deployed"
test ! -f "$TEST_HOME/.apm-envs/agent-framework/.github/agents/hello-world.agent.md" && pass "hello-world agent isolated" || fail "hello-world agent leaked"

echo ""
echo "=== TEST 5: switch back to hello-world, verify restore ==="
apmenv activate hello-world
test -f "$TEST_HOME/.apm-envs/hello-world/.github/agents/hello-world.agent.md" && pass "hello-world agent restored" || fail "hello-world agent missing after switch"
test ! -f "$TEST_HOME/.apm-envs/hello-world/.github/agents/code-first-agent.agent.md" && pass "agent-framework agent isolated" || fail "agent-framework agent leaked"

echo ""
echo "=== TEST 6: activate with --target claude override ==="
apmenv activate hello-world --target claude 2>&1 | tee /tmp/act_claude.txt
grep -q "claude" /tmp/act_claude.txt && pass "claude target used on activate" || fail "claude target not used on activate"

echo ""
echo "=== TEST 7: install with explicit --target claude ==="
apmenv activate hello-world
apmenv install "$HW_PKG" --target claude 2>&1 | tee /tmp/install_claude.txt
grep -q "Targets: claude" /tmp/install_claude.txt && pass "claude target override on install" || fail "claude target not overridden"

echo ""
echo "=== TEST 8: install with --target copilot,claude ==="
apmenv install "$HW_PKG" --target copilot,claude 2>&1 | tee /tmp/install_multi.txt
grep -q "copilot,claude\|copilot" /tmp/install_multi.txt && pass "multi-target accepted" || fail "multi-target failed"

echo ""
echo "=== TEST 9: saved target restored after explicit override ==="
apmenv install "$HW_PKG" 2>&1 | tee /tmp/install_default.txt
grep -q "Targets: copilot" /tmp/install_default.txt && pass "saved copilot target restored" || fail "saved target not restored"

echo ""
echo "=== TEST 10: deactivate cleans active state ==="
apmenv deactivate
current=$(apmenv current)
test "$current" = "(none)" && pass "current is (none) after deactivate" || fail "current is '$current' (expected '(none)')"

echo ""
echo "=== CLEANUP ==="
export HOME="$HOME_BAK"
rm -rf "$TEST_HOME"
echo "Temp HOME removed."

echo ""
if [ "$EXIT_CODE" -eq 0 ]; then
    echo "ALL TESTS PASSED"
else
    echo "SOME TESTS FAILED"
fi
exit "$EXIT_CODE"
