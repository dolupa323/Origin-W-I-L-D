# Totem Raid Validation Checklist

Last updated: 2026-03-18
Scope: upkeep expiration -> raid-open permissions, UI warning, owner notification, creature protection off.

## 1. Setup

- Start Studio test server with 2 players (PlayerA owner, PlayerB raider).
- As PlayerA, place one CAMP_TOTEM and at least 1 STORAGE + 1 production facility.
- Put items into storage and facility output/input/fuel slots.
- Confirm totem upkeep is active in totem UI.

## 2. Active Upkeep (must block raid)

- PlayerB tries to open PlayerA storage.
- Expected: denied (NO_PERMISSION path), no item transfer.
- PlayerB tries to open PlayerA facility.
- Expected: denied (NO_PERMISSION path).
- PlayerB tries to dismantle PlayerA structure with [T].
- Expected: denied with message that protection is active.
- Creature enters totem zone during combat.
- Expected: combat break + flee behavior still works while active.

## 3. Expiration Transition (must alert immediately)

- Let upkeep expire naturally (or shorten expire time for debug).
- Expected for PlayerA immediately after expiry:
- Totem.Upkeep.Expired alert toast appears.
- Side notification appears: raid-open warning.
- Totem window shows warning banner with icon ("⚠") and raid-open text.

## 4. Expired Upkeep (raid-open permissions)

- PlayerB opens PlayerA storage.
- Expected: success, items visible.
- PlayerB moves items between storage and inventory.
- Expected: success.
- PlayerB opens PlayerA facility.
- Expected: success.
- PlayerB collects output / removes input / removes fuel.
- Expected: success.
- PlayerB dismantles PlayerA structure.
- Expected: success.
- Creature enters zone during combat.
- Expected: no protection behavior (no forced safe-zone protection).

## 5. Re-Pay Recovery

- PlayerA pays upkeep (1/3/7 days) from totem UI.
- Expected:
- Totem warning banner hides.
- Totem.Upkeep.Changed updates state to active.
- PlayerB raid actions are denied again.

## 6. Regression Checks

- Owner (PlayerA) can always access own structures regardless of expiry.
- Campfire/totem placement exceptions remain unchanged.
- No script errors in Output window during transitions.
- Re-expire after re-pay triggers notification again exactly once per expiry cycle.
