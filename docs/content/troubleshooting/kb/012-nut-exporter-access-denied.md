---
description: nut-exporter crash loops with Access denied after a UPS firmware update
---

# KB-012: nut-exporter crash loops with `ACCESS-DENIED`

## Symptom

The nut-exporter pod crash loops with `Error: Access denied`, and UPS metrics
and alerts stop.

## Cause

nut-exporter relays the UniFi UPS through `dummy-ups` in repeater mode, which
has no username or password option and needs **anonymous reads**. UPS
firmware 1.6.4 started enforcing the NUT server's "credential required"
setting, so every read returns `ERR ACCESS-DENIED`. Logging in from
nut_exporter directly doesn't work either: the UPS answers `LIST CLIENT` and
`GET NUMLOGINS` with `ERR INVALID-ARGUMENT`.

## Fix

Turn off "credential required" for the NUT server in the UPS settings in
UniFi. The pod recovers by itself. Check anonymous reads with:

```sh
printf 'GET VAR ups-2u ups.status\nLOGOUT\n' | nc -w5 ups.internal 3493
```

## Seen

2026-10-22, after the UPS auto-updated its firmware overnight.
