import { onDrop } from '../dnd/onDrop';
import { onUse } from '../dnd/onUse';
import { store } from './index';
import { isSlotWithItem } from '../helpers';
import { Inventory, InventoryType } from '../typings';

/*
 * Tracks which inventory slot the mouse is currently over.
 *
 * `ctrl+click` drops the slot you clicked, so it has slot context for free.
 * The `dropitem` keybind registered in client.lua does not — a keypress has no
 * target — so the slot under the cursor is recorded here as the slot the
 * keypress acts on.
 *
 * This piggybacks on the mouseenter/mouseleave handlers InventorySlot already
 * uses to drive the item tooltip. Those handlers are only rendered for slots
 * that actually contain an item, so an entry here always started life as a
 * filled slot; the contents are re-checked against live store state at drop
 * time anyway, since only the slot number is retained.
 *
 * NOTE: this is mouse hover. On a controller there is no NUI cursor, so
 * nothing is ever hovered and the keypress is a no-op there.
 */

interface HoveredSlot {
  slot: number;
  inventoryType: Inventory['type'];
}

let hovered: HoveredSlot | null = null;

export const setHoveredSlot = (slot: number, inventoryType: Inventory['type']) => {
  hovered = { slot, inventoryType };
};

/** Clears only if the leaving slot is still the recorded one (enter/leave can interleave). */
export const clearHoveredSlot = (slot: number, inventoryType: Inventory['type']) => {
  if (hovered && hovered.slot === slot && hovered.inventoryType === inventoryType) hovered = null;
};

export const getHoveredSlot = (): HoveredSlot | null => hovered;

/**
 * Drops whatever the cursor is over. Mirrors the ctrl+click branch of
 * InventorySlot's handleClick exactly, including its guards.
 */
export const dropHoveredSlot = () => {
  const target = hovered;
  if (!target) return;

  if (target.inventoryType === 'shop' || target.inventoryType === 'crafting') return;

  const state = store.getState().inventory;
  // Same source resolution getTargetInventory() uses.
  const inventory = target.inventoryType === InventoryType.PLAYER ? state.leftInventory : state.rightInventory;

  const item = inventory.items[target.slot - 1];
  if (!item || !isSlotWithItem(item)) return;

  onDrop({ item, inventory: target.inventoryType });
};

/**
 * Equips (or uses) whatever the cursor is over.
 *
 * This is what makes hold-TAB-and-release work: the wheel cells are ordinary
 * InventorySlots, so hovering one already records it here, and releasing the
 * key just commits it. `onUse` is the same call alt+click and the 1-5 hotkeys
 * make -- fetchNui('useItem', slot) -> useSlot() -- so equipping through the
 * wheel goes down the identical path and inherits every check it does.
 *
 * Releasing with nothing hovered equips nothing, which is the wheel's
 * equivalent of letting go over the middle.
 */
export const equipHoveredSlot = () => {
  const target = hovered;
  if (!target) return;

  // Only the player's own inventory can be used from. A hovered stash or shop
  // slot is not something releasing the key should act on.
  if (target.inventoryType !== InventoryType.PLAYER) return;

  const state = store.getState().inventory;
  const item = state.leftInventory.items[target.slot - 1];
  if (!item || !isSlotWithItem(item)) return;

  onUse(item);
};

// client.lua's `dropitem` keybind fires this over NUI.
window.addEventListener('message', (event: MessageEvent<any>) => {
  if (event.data?.action !== 'dropHoveredSlot') return;
  dropHoveredSlot();
});

// Fired when the weapon-wheel key is RELEASED (see the `inv` keybind).
window.addEventListener('message', (event: MessageEvent<any>) => {
  if (event.data?.action !== 'equipHoveredSlot') return;
  equipHoveredSlot();
});
