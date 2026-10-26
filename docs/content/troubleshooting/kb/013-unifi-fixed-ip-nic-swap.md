---
description: UniFi refuses to move a node's fixed IP to a new NIC
---

# KB-013: UniFi refuses a fixed IP after a NIC swap

## Symptom

Moving a node's DHCP reservation to the MAC of a new NIC fails with
`FixedIpAlreadyUsedByClient`, even after the fixed IP is cleared from the old
client.

## Cause

Node IPs are reservations on `bond0`'s MAC, which is the MAC of the `net0`
link. UniFi won't move the IP while the old client is online, and Intel
onboard NICs stay online while the node is powered off. Unplugging the old NIC
isn't enough either, because UniFi is slow to age clients out.

## Fix

Forget the old client in UniFi, then immediately set the fixed IP and local
DNS record on the new MAC. The full procedure is in the
[Talos gotchas](../../kubernetes/talos.md#gotchas).

## Seen

2026-10-25: k8s-03 moving to a replacement 10G NIC
([#3062](https://github.com/bykaj/home-ops/pull/3062)).
