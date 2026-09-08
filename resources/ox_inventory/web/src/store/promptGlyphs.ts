import { useSyncExternalStore } from 'react';

// Live keybind labels for the on-screen prompt glyphs, pushed from
// client.lua's `setPromptGlyphs` NUI message (see resolvePromptGlyphs()).
//
// This is a plain external store rather than a `useNuiEvent` hook because the
// Lua side only emits when something actually *changes* (device swap or a
// rebind). A component that mounts after the last emit would otherwise never
// see a value, so the latest payload is cached here at module scope and
// replayed to whoever subscribes.

export type PromptDevice = 'kbm' | 'pad';

export interface PromptGlyphState {
  device: PromptDevice;
  quickslot1: string;
  quickslot2: string;
  drop: string;
}

// Defaults mirror ox_inventory's own keybind defaults in client.lua
// (`quickslot1`/`quickslot2` default to "1"/"2", `dropslot` defaults to "G").
// They are only ever shown before the first message arrives; the Lua side
// overwrites them with the player's real, current binds.
let state: PromptGlyphState = {
  device: 'kbm',
  quickslot1: '1',
  quickslot2: '2',
  drop: 'G',
};

const listeners = new Set<() => void>();

const emit = () => listeners.forEach((listener) => listener());

window.addEventListener('message', (event: MessageEvent<any>) => {
  const payload = event.data;
  if (!payload || payload.action !== 'setPromptGlyphs' || !payload.data) return;

  const data = payload.data as Partial<PromptGlyphState>;
  const next: PromptGlyphState = {
    device: data.device === 'pad' ? 'pad' : 'kbm',
    quickslot1: data.quickslot1 ?? '',
    quickslot2: data.quickslot2 ?? '',
    drop: data.drop ?? '',
  };

  if (
    next.device === state.device &&
    next.quickslot1 === state.quickslot1 &&
    next.quickslot2 === state.quickslot2 &&
    next.drop === state.drop
  )
    return;

  state = next;
  emit();
});

const subscribe = (listener: () => void) => {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
};

const getSnapshot = () => state;

export const usePromptGlyphs = (): PromptGlyphState => useSyncExternalStore(subscribe, getSnapshot);
