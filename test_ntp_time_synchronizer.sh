#!/usr/bin/env bash
# test_ntp_time_synchronizer.sh
#
# Tests for ntp_time_synchronizer.sh. We source the library and call its functions.
# We do not actually query an NTP server; instead we test the pure arithmetic and
# the parsing logic where possible. For the network-dependent functions, we mock
# by overriding get_ntp_time and get_local_time.

set -euo pipefail

# Source the library under test.
# shellcheck source=ntp_time_synchronizer.sh
source ./ntp_time_synchronizer.sh

# TAP-like test output.
test_count=0
fail_count=0

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="${3:-}"
  test_count=$((test_count + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "ok $test_count - $message"
  else
    echo "not ok $test_count - $message"
    echo "# expected: $expected"
    echo "# actual:   $actual"
    fail_count=$((fail_count + 1))
  fi
}

# Test get_local_time returns a numeric value.
local_time=$(get_local_time)
if [[ "$local_time" =~ ^[0-9]+$ ]]; then
  assert_eq "numeric" "numeric" "get_local_time returns an integer"
else
  assert_eq "numeric" "non-numeric" "get_local_time returns an integer"
fi

# Test time_difference with mocked times.
# We override get_ntp_time and get_local_time to return fixed values.
# This tests the arithmetic in time_difference without network access.
original_get_ntp_time=$(declare -f get_ntp_time)
original_get_local_time=$(declare -f get_local_time)

get_ntp_time() { echo 1000; }
get_local_time() { echo 900; }

diff=$(time_difference "example.invalid")
assert_eq "100" "$diff" "time_difference positive when local is behind"

get_ntp_time() { echo 900; }
get_local_time() { echo 1000; }

diff=$(time_difference "example.invalid")
assert_eq "-100" "$diff" "time_difference negative when local is ahead"

get_ntp_time() { echo 500; }
get_local_time() { echo 500; }

diff=$(time_difference "example.invalid")
assert_eq "0" "$diff" "time_difference zero when in sync"

# Test sync_clock output with mocked times.
get_ntp_time() { echo 1000; }
get_local_time() { echo 900; }
output=$(sync_clock "example.invalid")
assert_eq "Local clock is 100 seconds behind example.invalid" "$output" "sync_clock reports behind"

get_ntp_time() { echo 900; }
get_local_time() { echo 1000; }
output=$(sync_clock "example.invalid")
assert_eq "Local clock is 100 seconds ahead of example.invalid" "$output" "sync_clock reports ahead"

get_ntp_time() { echo 500; }
get_local_time() { echo 500; }
output=$(sync_clock "example.invalid")
assert_eq "Local clock is in sync with example.invalid" "$output" "sync_clock reports in sync"

# Test failure propagation: if get_ntp_time fails, time_difference should fail.
get_ntp_time() { return 1; }
if time_difference "example.invalid" >/dev/null 2>&1; then
  assert_eq "failure" "success" "time_difference propagates get_ntp_time failure"
else
  assert_eq "failure" "failure" "time_difference propagates get_ntp_time failure"
fi

# Restore original functions to avoid affecting other tests (none left, but good practice).
eval "$original_get_ntp_time"
eval "$original_get_local_time"

# Test _ntp_query with a non-existent host returns error.
# We cannot actually test network, but we can test that it fails gracefully.
# However, this would attempt network access which is not allowed in the test container.
# So we skip that and only test the logic we can control.

# Report summary.
echo "1..$test_count"
if [[ $fail_count -gt 0 ]]; then
  exit 1
fi
exit 0
