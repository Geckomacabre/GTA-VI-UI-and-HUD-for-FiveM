import { useSyncExternalStore } from 'react';

/*
 * Which inventory slot is actually in the player's hands.
 *
 * Nothing used to tell the NUI this. The weapon wheel had to guess, and it
 * guessed "the first weapon in the inventory", labelling that IN HAND whether
 * it was or not -- so the caption was wrong the moment you carried more than
 * one weapon, and there was no way to show what you were really holding.
 *
 * client.lua now pushes it from an `ox_inventory:currentWeapon` event handler,
 * which covers equipping, holstering and being forcibly disarmed. The value is
 * also carried on `setupInventory`, because a weapon equipped before the UI
 * ever loaded would otherwise never be reported at all.
 *
 * A plain external store rather than a `useNuiEvent` hook, for the same reason
 * promptGlyphs.ts is one: the Lua side only emits on change, so a component
 * mounting after the last emit would never see a value. The latest payload is
 * cached at module scope and replayed to whoever subscribes.
 */

let slot: number | null = null;

const listeners = new Set<() => void>();

const emit = () => listeners.forEach((listener) => listener());

const set = (next: number | null) => {
  if (next === slot) return;
  slot = next;
  emit();
};

/** Lua sends `false` for "unarmed"; anything not a number clears the slot. */
const parse = (value: unknown): number | null => (typeof value === 'number' ? value : null);

window.addEventListener('message', (event: MessageEvent<any>) => {
  const payload = event.data;
  if (!payload) return;

  if (payload.action === 'setCurrentWeapon') {
    set(parse(payload.data));
  } else if (payload.action === 'setupInventory') {
    set(parse(payload.data?.currentWeapon));
  }
});

const subscribe = (listener: () => void) => {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
};

const getSnapshot = () => slot;

export const useCurrentWeaponSlot = (): number | null => useSyncExternalStore(subscribe, getSnapshot);
