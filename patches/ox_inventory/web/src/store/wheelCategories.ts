/*
 * Curated item-name lists for the fixed-category wheel slots (WeaponWheel.tsx)
 * and the medical-only quick-use strip (LeftInventory.tsx).
 *
 * ox_inventory item data carries no "category" field, so there is nothing to
 * derive this from — these are hand-picked from data/weapons.lua and
 * data/items.lua. Edit the lists directly when the item set changes (e.g. add
 * a real "binoculars" item to HANDHELD_ITEMS once one exists).
 *
 * WEAPON_FLASHLIGHT is grouped as melee by the game's own weapon groups, but
 * reads as a handheld tool here, not a weapon or a melee item — hence a
 * curated list instead of trusting GetWeapontypeGroup.
 */

const MELEE_ITEMS = new Set([
  'weapon_bat',
  'weapon_battleaxe',
  'weapon_bottle',
  'weapon_candycane',
  'weapon_crowbar',
  'weapon_dagger',
  'weapon_golfclub',
  'weapon_hammer',
  'weapon_hatchet',
  'weapon_knife',
  'weapon_knuckle',
  'weapon_machete',
  'weapon_nightstick',
  'weapon_poolcue',
  'weapon_stone_hatchet',
  'weapon_switchblade',
  'weapon_wrench',
  'weapon_ball',
  'weapon_snowball',
]);

// No binoculars item exists in data/items.lua yet — add its name here once one does.
const HANDHELD_ITEMS = new Set(['weapon_flashlight', 'weapon_metaldetector']);

const MEDICAL_ITEMS = new Set([
  'bandage',
  'medikit',
  'medbag',
  'tweezers',
  'suturekit',
  'icepack',
  'burncream',
  'defib',
  'sedative',
  'morphine30',
  'morphine15',
  'perc30',
  'perc10',
  'perc5',
  'vic10',
  'vic5',
]);

export const isMeleeItem = (name: string): boolean => MELEE_ITEMS.has(name);
export const isHandheldItem = (name: string): boolean => HANDHELD_ITEMS.has(name);
export const isMedicalItem = (name: string): boolean => MEDICAL_ITEMS.has(name);
