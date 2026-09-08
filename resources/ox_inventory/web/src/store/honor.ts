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

type HonorSnapshot = {
  honor: number | null;
  tier: 'angel' | 'devil' | null;
  // vice_hud's own face art, served from that resource (nui://vice_hud/...),
  // so the wheel shows the same image its honor panel does rather than a
  // lookalike. null for a neutral standing, which has no face in vice_hud
  // either.
  icon: string | null;
  // Base64 mugshot, refreshed each time the wheel opens.
  mugshot: string | null;
  // Latches true at qbx_honor's unrepairable floor and never clears -- see
  // metadata.honorBroken in qbx_honor/config.lua's "Unrepairable floor"
  // section. The badge renders this as permanently spent, not merely low.
  broken: boolean;
};

// Cached rather than built fresh in getSnapshot(): useSyncExternalStore compares
// snapshots with Object.is, so a new object literal on every call would look
// like a change on every render and defeat the point of the store.
let snapshot: HonorSnapshot = { honor: null, tier: null, icon: null, mugshot: null, broken: false };

const listeners = new Set<() => void>();

const emit = () => listeners.forEach((listener) => listener());

window.addEventListener('message', (event: MessageEvent<any>) => {
  const payload = event.data;
  if (!payload || payload.action !== 'setHonor') return;

  const data = payload.data ?? {};
  const value = typeof data.value === 'number' ? data.value : null;
  const nextTier = data.tier === 'angel' || data.tier === 'devil' ? data.tier : null;
  const nextIcon = typeof data.icon === 'string' && data.icon ? data.icon : null;
  const nextMugshot = typeof data.mugshot === 'string' && data.mugshot ? data.mugshot : null;
  const nextBroken = data.broken === true;

  if (
    value === snapshot.honor &&
    nextTier === snapshot.tier &&
    nextIcon === snapshot.icon &&
    nextMugshot === snapshot.mugshot &&
    nextBroken === snapshot.broken
  ) {
    return;
  }

  snapshot = { honor: value, tier: nextTier, icon: nextIcon, mugshot: nextMugshot, broken: nextBroken };
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
