# Grassland Workbench Asset Naming Guide

Last updated: 2026-03-18

Scope: All newly added grassland workbench elements (recipes, items, icons, models, armor accessory keys).

## Added Elements (Source of Truth)

### Recipes (RecipeData.id)

- CRAFT_SPLIT_LOG_TO_PLANK
- CRAFT_FIRM_STONE_AXE
- CRAFT_FIRM_STONE_PICKAXE
- CRAFT_BONE_SPEAR
- CRAFT_LEATHER_ARMOR
- CRAFT_FEATHER_HELMET

### Output Items (ItemData.id)

- FEATHER_HELMET (깃털 투구)
- LEATHER_ARMOR (가죽옷)
- FIRM_STONE_AXE (돌도끼)
- FIRM_STONE_PICKAXE (돌곡괭이)
- BONE_SPEAR (뼈창)
- PLANK (판재, 나무쪼개기 결과물)

### Related Input Items (for consistency checks)

- LOG
- LEATHER
- DODO_FEATHER
- BONE
- STONE
- FIBER

## Naming Rules

- Use UPPER_SNAKE_CASE for all ids and icon object names.
- Use PascalCase for modelName values used by world/drop lookups.
- Use UPPER_SNAKE_CASE with \_MODEL suffix for armor modelId keys.
- Keep Korean display naming consistent: use 나무쪼개기 (no space).

## Icon Naming (Client)

UI icon resolver checks these in order:

1. ItemData.iconName
2. itemId
3. alias fallback

Recommended icon object names in ReplicatedStorage/Assets/ItemIcons:

- FEATHER_HELMET
- LEATHER_ARMOR
- FIRM_STONE_AXE
- FIRM_STONE_PICKAXE
- BONE_SPEAR
- PLANK

Optional but recommended for input resources used frequently in workbench UI:

- LOG
- LEATHER
- DODO_FEATHER
- BONE
- STONE
- FIBER

Allowed icon object types:

- Decal (Texture used)
- Texture (Texture used)
- ImageLabel/ImageButton (Image used)
- StringValue (Value used)

## Model Naming (World/Hand)

ItemData fields used:

- modelName: drop/world model lookup key
- modelId: armor accessory key (EquipService armor cache)

Required model mappings:

- PLANK -> modelName = Plank
- FIRM_STONE_AXE -> modelName = FirmStoneAxe
- FIRM_STONE_PICKAXE -> modelName = FirmStonePickaxe
- BONE_SPEAR -> modelName = BONE_SPEAR

Armor accessory key (required):

- FEATHER_HELMET -> modelId = FEATHER_HELMET_MODEL

Existing armor retained for compatibility:

- LEATHER_ARMOR uses SUIT slot visuals in current pipeline
- LEATHER_HAT can remain as legacy asset, but do not use it in the new leather set pairing

## Minimum Asset Checklist

1. Add icon assets with exact names above.
2. Add Plank world model if not present.
3. Register FEATHER_HELMET_MODEL accessory in armor cache pipeline used by EquipService.
4. Validate FacilityUI list/detail/queue icon visibility in BASIC_WORKBENCH.
5. Confirm recipe ids above are not renamed in downstream data or unlock tables.
6. Confirm Korean text uses 나무쪼개기 consistently in UI/data.

## Quick Validation

1. Interact with BASIC_WORKBENCH.
2. Verify top recipe order is fixed to the six added recipes.
3. Start CRAFT_SPLIT_LOG_TO_PLANK and confirm 1 LOG -> 3 PLANK.
4. Close UI, reopen, and collect output.
5. Confirm icons display for all six output items in list/detail/queue.
6. Equip FEATHER_HELMET and confirm head accessory is visible.
