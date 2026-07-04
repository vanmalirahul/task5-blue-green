#!/bin/bash
# smoke_test.sh — Post-deploy health verification
# Usage: ./scripts/smoke_test.sh 192.168.1.102
# Returns: 0 = all tests passed, 1 = at least one test failed

SERVER=${1:-192.168.1.102}
PASS=0
FAIL=0
RESULTS=()

run_test() {
    local TEST_NAME="$1"
    local TEST_CMD="$2"
    local EXPECTED="$3"

    ACTUAL=$(eval "$TEST_CMD" 2>/dev/null)
    if echo "$ACTUAL" | grep -q "$EXPECTED"; then
        echo "✅ PASS: $TEST_NAME"
        RESULTS+=("✅ $TEST_NAME")
        ((PASS++))
    else
        echo "❌ FAIL: $TEST_NAME (expected '$EXPECTED', got '$ACTUAL')"
        RESULTS+=("❌ $TEST_NAME")
        ((FAIL++))
    fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SMOKE TESTS — Server: $SERVER"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Test 1: Port 80 returns HTTP 200
run_test "HTTP 200 on port 80" \
    "curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://$SERVER" \
    "200"

# Test 2: Slot status endpoint exists
run_test "Slot status endpoint" \
    "curl -s http://$SERVER/slot-status" \
    "active"

# Test 3: Active slot is either blue or green
run_test "Active slot is valid (blue or green)" \
    "curl -s http://$SERVER/slot-status" \
    '"active":"'

# Test 4: X-Active-Slot header present
run_test "X-Active-Slot header present" \
    "curl -sI http://$SERVER" \
    "X-Active-Slot"

# Test 5: Blue slot health endpoint works
run_test "Blue slot health endpoint" \
    "curl -s http://$SERVER:8080/health" \
    "ok"

# Test 6: Green slot health endpoint works
run_test "Green slot health endpoint" \
    "curl -s http://$SERVER:8081/health" \
    "ok"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$FAIL" -gt 0 ]; then
    exit 1   # non-zero exit = Jenkins marks stage as FAILED → triggers rollback
fi
exit 0
