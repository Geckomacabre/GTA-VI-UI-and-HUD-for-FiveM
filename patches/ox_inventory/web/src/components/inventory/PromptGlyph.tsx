import React from 'react';
import { PromptDevice } from '../../store/promptGlyphs';

/*
 * Renders one instructional-button prompt.
 *
 * The label itself is resolved on the Lua side with
 * `GetControlInstructionalButton(0, hash, true):sub(3)` (the same call
 * ox_lib's keybind:getCurrentKey() uses), so it is always the player's *live*
 * bind, not a hardcoded key.
 *
 * That native already returns the controller token when a pad is active, but
 * those tokens are ligatures for GTA's own button font, which does not exist
 * inside a CFX NUI browser frame. PAD_GLYPHS below maps the tokens we can
 * recognise onto plain renderable characters.
 *
 * Anything we cannot recognise is NOT rendered verbatim: if the label contains
 * any character outside printable ASCII it is almost certainly one of those
 * private-use font ligatures, which would render as a tofu box (□ / ?) in the
 * NUI. Those fall back to a neutral "there is a button here" bullet instead.
 * Run `/glyphdump` in-game (see client.lua) to capture the real token bytes so
 * they can be added to PAD_GLYPHS properly.
 */

type PadTone = 'a' | 'b' | 'x' | 'y' | undefined;

interface PadGlyph {
  glyph: string;
  tone?: PadTone;
  /** True when the label was unrenderable and replaced by the neutral fallback. */
  unknown?: boolean;
}

// Keys are normalised (uppercased, non-alphanumerics collapsed to '_'). The
// table is only consulted while `device === 'pad'`, so single-letter keys here
// can never shadow a keyboard key of the same name.
const PAD_GLYPHS: Record<string, PadGlyph> = {
  // Face buttons — Xbox naming and the PlayStation equivalents that some
  // token sets use instead.
  A: { glyph: 'A', tone: 'a' },
  B: { glyph: 'B', tone: 'b' },
  X: { glyph: 'X', tone: 'x' },
  Y: { glyph: 'Y', tone: 'y' },
  BUTTON_A: { glyph: 'A', tone: 'a' },
  BUTTON_B: { glyph: 'B', tone: 'b' },
  BUTTON_X: { glyph: 'X', tone: 'x' },
  BUTTON_Y: { glyph: 'Y', tone: 'y' },
  PAD_A: { glyph: 'A', tone: 'a' },
  PAD_B: { glyph: 'B', tone: 'b' },
  PAD_X: { glyph: 'X', tone: 'x' },
  PAD_Y: { glyph: 'Y', tone: 'y' },
  CROSS: { glyph: '✕', tone: 'a' },
  CIRCLE: { glyph: '◯', tone: 'b' },
  SQUARE: { glyph: '□', tone: 'x' },
  TRIANGLE: { glyph: '△', tone: 'y' },

  // D-pad.
  DPAD_UP: { glyph: '↑' },
  DPAD_DOWN: { glyph: '↓' },
  DPAD_LEFT: { glyph: '←' },
  DPAD_RIGHT: { glyph: '→' },
  DPADUP: { glyph: '↑' },
  DPADDOWN: { glyph: '↓' },
  DPADLEFT: { glyph: '←' },
  DPADRIGHT: { glyph: '→' },
  UP: { glyph: '↑' },
  DOWN: { glyph: '↓' },
  LEFT: { glyph: '←' },
  RIGHT: { glyph: '→' },

  // Shoulders / triggers.
  LB: { glyph: 'LB' },
  RB: { glyph: 'RB' },
  LT: { glyph: 'LT' },
  RT: { glyph: 'RT' },
  L1: { glyph: 'L1' },
  R1: { glyph: 'R1' },
  L2: { glyph: 'L2' },
  R2: { glyph: 'R2' },
  L3: { glyph: 'L3' },
  R3: { glyph: 'R3' },
  LEFT_SHOULDER: { glyph: 'LB' },
  RIGHT_SHOULDER: { glyph: 'RB' },
  LEFT_TRIGGER: { glyph: 'LT' },
  RIGHT_TRIGGER: { glyph: 'RT' },
  LEFT_STICK: { glyph: 'L3' },
  RIGHT_STICK: { glyph: 'R3' },

  // Centre buttons.
  START: { glyph: '≡' },
  SELECT: { glyph: '❐' },
  BACK: { glyph: '❐' },
};

const normalise = (label: string) => label.trim().toUpperCase().replace(/[^A-Z0-9]+/g, '_').replace(/^_|_$/g, '');

/**
 * Neutral placeholder used when a label cannot be rendered as text. It still
 * reads as "a button goes here" without printing garbage.
 */
const UNKNOWN_GLYPH: PadGlyph = { glyph: '•', unknown: true };

/** Printable ASCII only — U+0020 (space) through U+007E (~). */
const isRenderableAscii = (value: string) => /^[\x20-\x7E]+$/.test(value);

export const resolveGlyph = (label: string, device: PromptDevice): PadGlyph | null => {
  // Nothing bound at all: the caller renders nothing rather than a placeholder.
  if (!label || !label.trim()) return null;

  if (device === 'pad') {
    const mapped = PAD_GLYPHS[normalise(label)];
    if (mapped) return mapped;
  }

  // Unmapped. Only render it verbatim if it is plain printable ASCII
  // ("CTRL", "MOUSE1", "G", …); anything else is font-ligature garbage.
  return isRenderableAscii(label.trim()) ? { glyph: label.trim() } : UNKNOWN_GLYPH;
};

interface Props {
  label: string;
  device: PromptDevice;
  /** `lg` / `sm` map to the two measured circle diameters under the quickslots. */
  size?: 'lg' | 'sm';
  className?: string;
}

const PromptGlyph: React.FC<Props> = ({ label, device, size = 'lg', className }) => {
  const resolved = resolveGlyph(label, device);

  // Nothing bound (e.g. a keyboard-only bind while a pad is active) — render
  // nothing at all rather than an empty circle pretending to be a prompt.
  if (!resolved) return null;

  // A single character sits in a circle; anything longer ("CTRL", "LB",
  // "MOUSE1") would overflow it, so it gets a keycap instead.
  const isSingle = [...resolved.glyph].length === 1;

  return (
    <span
      className={[
        'gta6-prompt-glyph',
        `gta6-prompt-glyph-${size}`,
        isSingle ? 'gta6-prompt-glyph-circle' : 'gta6-prompt-glyph-cap',
        resolved.tone ? `gta6-prompt-glyph-pad-${resolved.tone}` : '',
        resolved.unknown ? 'gta6-prompt-glyph-unknown' : '',
        className || '',
      ]
        .filter(Boolean)
        .join(' ')}
    >
      {resolved.glyph}
    </span>
  );
};

export default PromptGlyph;
