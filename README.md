# ntp-time-synchronizer

A small shell library that compares the local system clock against an NTP server and reports the difference in seconds.

## Usage

```bash
source ./ntp_time_synchronizer.sh

# Get the difference in seconds (positive means local clock is behind)
diff=$(time_difference "pool.ntp.org")
echo "Local clock is $diff seconds off"

# Print a human-readable status
sync_clock "pool.ntp.org"
```

The library exports the following functions:

- `get_ntp_time [host]` — returns the NTP server time as Unix seconds.
- `get_local_time` — returns the local system time as Unix seconds.
- `time_difference [host]` — returns the difference (NTP time minus local time) in seconds.
- `sync_clock [host]` — prints a human-readable message about the time difference.

If `host` is omitted, the `NTP_SERVER` environment variable is used (default: `pool.ntp.org`).

## Why this exists

System clocks drift. Before trusting timestamps in logs or distributed systems, you often want a quick check of how far off the local clock is from a reference. This library provides that check without pulling in heavy dependencies. It uses `ntpdate` or `sntp` if available, and falls back to a raw UDP NTP query via bash's `/dev/udp`. The trade-off is that the fallback path is less robust than a dedicated NTP client: it does not handle retries, authentication, or sub-second precision. It is intended for coarse skew detection, not for precise time synchronization.

## Edge cases

- The library does not modify the system clock. `sync_clock` only reports; it does not call `settimeofday` or `adjtime`. This is deliberate: changing the clock requires root and can disrupt running services.
- The raw UDP fallback depends on `/dev/udp`, which is not available in all environments (e.g., some minimal containers). In that case, `get_ntp_time` returns an error. The library does not attempt to install or use external NTP clients beyond `ntpdate` and `sntp`.
- The difference is computed in whole seconds. NTP fraction is ignored, so the result is an integer. This is sufficient for detecting skew of a second or more.
