#!/usr/bin/env bash
# ntp_time_synchronizer.sh
#
# A small shell library for comparing a local system clock against an NTP server.
#
# Design decisions:
# - No external tools beyond coreutils and bash builtins. We use `date` for
#   local time and `ntpdate`/`sntp` only if available; otherwise we fall back to
#   a simple UDP NTP query using bash's /dev/udp redirection. This keeps the
#   library dependency-free while still being functional on most systems.
# - The NTP query uses the standard 48-byte NTP packet. We only need the
#   transmit timestamp (bytes 40-43 for seconds, 44-47 for fraction).
# - The difference is calculated as (ntp_time - local_time) in seconds.
#   Positive means the local clock is behind; negative means ahead.

set -euo pipefail

# Default NTP server. Users can override by setting NTP_SERVER.
: "${NTP_SERVER:=pool.ntp.org}"

# Convert a 64-bit NTP timestamp (seconds since 1900) to Unix time (seconds since 1970).
# NTP epoch is 1900-01-01, Unix epoch is 1970-01-01. The difference is 2208988800 seconds.
# We use bc for floating point? No, bc may not be installed. We use integer arithmetic
# for seconds and a separate calculation for fractions, but keep it simple: we only
# need seconds precision for the difference. The NTP fraction is ignored.
#
# However, to avoid floating point in bash, we compute the difference in seconds as an integer.
# This is sufficient for clock skew detection at second granularity.

# _ntp_query HOST
# Sends an NTP request to HOST and prints the server's transmit timestamp as Unix seconds.
# Uses /dev/udp if no ntpdate/sntp is available. This is a best-effort approach.
_ntp_query() {
  local host="$1"
  local ntp_seconds

  # Try ntpdate first (common on older systems).
  if command -v ntpdate >/dev/null 2>&1; then
    ntp_seconds=$(ntpdate -q "$host" 2>/dev/null | awk '/^server/ {print $10}' | cut -d. -f1)
    if [[ -n "$ntp_seconds" ]]; then
      echo "$ntp_seconds"
      return 0
    fi
  fi

  # Try sntp (common on macOS and some Linux distributions).
  if command -v sntp >/dev/null 2>&1; then
    ntp_seconds=$(sntp -S "$host" 2>/dev/null | awk '{print $1}' | cut -d. -f1)
    if [[ -n "$ntp_seconds" ]]; then
      echo "$ntp_seconds"
      return 0
    fi
  fi

  # Fallback: raw UDP NTP query using /dev/udp. This requires bash 4+ and
  # a working /dev/udp, which is present on most Linux systems.
  # We construct a 48-byte NTP packet with the first byte set to 0x1b (LI=0, VN=3, Mode=3).
  # The rest is zeros. We read the response and extract bytes 40-43 (transmit timestamp seconds).
  # Note: /dev/udp is not available on all systems (e.g., some minimal containers).
  # We detect failure and return an error.
  local packet
  packet=$(printf '\x1b%0.s' {1..47})  # 0x1b followed by 47 null bytes
  local response
  # Use timeout to avoid hanging indefinitely. timeout is coreutils.
  if ! response=$(timeout 5 bash -c "exec 3<>/dev/udp/$host/123; printf '%s' \"$packet\" >&3; dd bs=48 count=1 <&3 2>/dev/null" 2>/dev/null); then
    echo "error: NTP query failed" >&2
    return 1
  fi
  # Extract bytes 40-43 as a 32-bit big-endian integer.
  # We use od to convert to hex, then parse.
  local hex
  hex=$(printf '%s' "$response" | od -An -tx1 | tr -d ' \n')
  # Transmit timestamp seconds are bytes 40-43 (0-indexed), so hex characters 80-87.
  local ts_hex="${hex:80:8}"
  if [[ -z "$ts_hex" ]]; then
    echo "error: short NTP response" >&2
    return 1
  fi
  ntp_seconds=$((16#$ts_hex))
  echo "$ntp_seconds"
}

# get_ntp_time HOST
# Returns the NTP server time as Unix seconds.
# Prints the value to stdout. Returns non-zero on failure.
get_ntp_time() {
  local host="${1:-$NTP_SERVER}"
  _ntp_query "$host"
}

# get_local_time
# Returns the local system time as Unix seconds.
get_local_time() {
  date +%s
}

# time_difference HOST
# Calculates the difference between the NTP server time and the local system time.
# Positive means the local clock is behind the NTP server (local needs to advance).
# Negative means the local clock is ahead.
# Prints the difference in seconds as an integer.
time_difference() {
  local host="${1:-$NTP_SERVER}"
  local ntp_time local_time
  ntp_time=$(get_ntp_time "$host") || return 1
  local_time=$(get_local_time)
  echo $((ntp_time - local_time))
}

# sync_clock HOST
# Prints a human-readable message about the time difference.
# Does not actually modify the system clock (that would require root and is
# outside the scope of a comparison library).
sync_clock() {
  local host="${1:-$NTP_SERVER}"
  local diff
  if ! diff=$(time_difference "$host"); then
    echo "Failed to query NTP server $host" >&2
    return 1
  fi
  if [[ "$diff" -eq 0 ]]; then
    echo "Local clock is in sync with $host"
  elif [[ "$diff" -gt 0 ]]; then
    echo "Local clock is $diff seconds behind $host"
  else
    echo "Local clock is $((-diff)) seconds ahead of $host"
  fi
}
