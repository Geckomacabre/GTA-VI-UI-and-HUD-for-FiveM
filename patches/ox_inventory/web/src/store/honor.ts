import { useSyncExternalStore } from 'react';

/*
 * The player's current honor standing, for the badge in the wheel's
 * bottom-right corner (see LeftInventory.tsx).
 *
 * qbx_honor owns the actual value (exports('GetHonor', ...) and the
 * 'qbx_honor:client:syncHonor' event) — this resource never computes honor
 * itself. client.lua listens for that same sync event and replays it here via
 * a 'setHonor' NUI message, the same external-store pattern currentWeapon.ts
 * uses and for the same reason: the event only fires on change, so a
 * component mounting after the last one would otherwise never see a value.
 *
 * `null` means "qbx_honor isn't installed, or hasn't reported a value yet" —
 * the badge renders nothing rather than a fabricated 0.
 */

type HonorSnapshot = { honor: number | null; tier: 'angel' | 'devil' | null };

// Cached rather than built fresh in getSnapshot(): useSyncExternalStore compares
// snapshots with Object.is, so a new object literal on every call would look
// like a change on every render and defeat the point of the store.
let snapshot: HonorSnapshot = { honor: null, tier: null };

const listeners = new Set<() => void>();

const emit = () => listeners.forEach((listener) => listener());

window.addEventListener('message', (event: MessageEvent<any>) => {
  const payload = event.data;
  if (!payload || payload.action !== 'setHonor') return;

  const data = payload.data ?? {};
  const value = typeof data.value === 'number' ? data.value : null;
  const nextTier = data.tier === 'angel' || data.tier === 'devil' ? data.tier : null;

  if (value === snapshot.honor && nextTier === snapshot.tier) return;

  snapshot = { honor: value, tier: nextTier };
  emit();
});

const subscribe = (listener: () => void) => {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
};

const getSnapshot = () => snapshot;

export const useHonor = (): HonorSnapshot => useSyncExternalStore(subscribe, getSnapshot);
