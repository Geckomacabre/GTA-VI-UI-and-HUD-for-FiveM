import { useSyncExternalStore } from 'react';

/*
 * Which tab the left panel is showing: the weapon wheel or the item grid.
 *
 * This lives outside React because two very different things set it -- the
 * player clicking the segmented switcher, and client.lua saying which tab to
 * open on (hold TAB opens the wheel, F2 opens the items grid). Keeping it in
 * LeftInventory's own useState meant the Lua side had no way to reach it.
 *
 * Same external-store shape as promptGlyphs.ts and currentWeapon.ts, and for
 * the same reason: the value has to survive between mounts so the panel opens
 * on the tab it was told to, not on whatever it defaulted to.
 */

export type InventoryTab = 'weapons' | 'items';

let tab: InventoryTab = 'weapons';

const listeners = new Set<() => void>();

const emit = () => listeners.forEach((listener) => listener());

export const setActiveTab = (next: InventoryTab) => {
  if (next === tab) return;
  tab = next;
  emit();
};

window.addEventListener('message', (event: MessageEvent<any>) => {
  const payload = event.data;
  if (!payload || payload.action !== 'setupInventory') return;

  // Absent means "leave the tab alone". Every opener that is not one of the
  // two keybinds -- a stash, a shop, ox_target -- has no opinion about the
  // left panel, and forcing them onto a tab would yank it out from under the
  // player mid-interaction.
  const next = payload.data?.tab;
  if (next === 'weapons' || next === 'items') setActiveTab(next);
});

const subscribe = (listener: () => void) => {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
};

const getSnapshot = () => tab;

export const useActiveTab = (): InventoryTab => useSyncExternalStore(subscribe, getSnapshot);
