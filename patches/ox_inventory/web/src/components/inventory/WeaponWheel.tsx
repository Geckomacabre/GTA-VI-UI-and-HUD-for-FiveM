import React, { useCallback, useMemo, useState } from 'react';
import InventorySlot from './InventorySlot';
import { Inventory, Slot, SlotWithItem } from '../../typings';
import { isSlotWithItem, getItemUrl } from '../../helpers';
import { Items } from '../../store/items';
import { Locale } from '../../store/locale';
import { useCurrentWeaponSlot } from '../../store/currentWeapon';
import { onUse } from '../../dnd/onUse';
import { onDisarm } from '../../dnd/onDisarm';
import { isMeleeItem, isHandheldItem } from '../../store/wheelCategories';

/*
 * GTA6-style weapon wheel.
 *
 * Geometry note: every position below is an absolute percentage of the
 * viewport, measured off the user's 2000x1124 reference frames. Sizes and
 * font sizes live in gta6-theme.scss and are expressed in `vh` (converted
 * from the measured width-percentages at the reference aspect ratio) so slot
 * boxes and text keep their shape on ultrawide/4:3 displays while the overall
 * composition stays where it was measured.
 *
 * Functionally this is still just InventorySlot in a different place: each
 * wheel cell wraps a real <InventorySlot>, so react-dnd drag/drop, the
 * right-click context menu, ctrl+click drop, alt+click use and the hover
 * tooltip all keep working untouched. The teal glow, ammo strip and badges are
 * pointer-events:none overlays painted on top of the slot.
 *
 * Cell roles:
 *  - 'free'     any item, including weapons — the original behaviour.
 *  - 'melee'    only accepts items in wheelCategories.isMeleeItem (~8 o'clock).
 *  - 'handheld' only accepts items in wheelCategories.isHandheldItem (~4 o'clock,
 *               flashlight/binoculars/similar tools).
 *  - 'fist'     not backed by an inventory slot at all — a fixed button that
 *               always shows the fist icon and holsters whatever is equipped
 *               (middle-right / 3 o'clock).
 * The "top" position isn't a ring cell — it's the separate equipped-weapon
 * readout below, which already always mirrors what's actually in your hand.
 */
type WheelRole = 'free' | 'melee' | 'handheld' | 'fist';

interface WheelCell {
  role: WheelRole;
  position: React.CSSProperties;
}

// Deliberately *not* evenly spaced on a circle — five of these are the
// measured centres from the reference art (cx 50.33%, cy 47.33%, rx 15.26%,
// ry 26.34%, solved from those five). The two flagged below are NOT
// independently measured off reference art — they were previously guessed
// coordinates that landed well outside that ellipse (dx ~2x rx), which is
// why they rendered nowhere near the ring. Replaced with points computed ON
// the same fitted ellipse, at +-45 deg from top/12 o'clock (the top itself is
// deliberately empty — see the "top" note below) — check them against a real
// screen before trusting them pixel-for-pixel, same as before.
const WHEEL_CELLS: WheelCell[] = [
  { role: 'free', position: { left: '35.08%', top: '48.49%' } }, // ~10 o'clock
  { role: 'fist', position: { left: '65.5%', top: '48.49%' } }, // 3 o'clock — always fist
  { role: 'melee', position: { left: '38.33%', top: '63.61%' } }, // ~8 o'clock
  { role: 'handheld', position: { left: '62.45%', top: '63.61%' } }, // ~4 o'clock
  { role: 'free', position: { left: '50.33%', top: '73.67%' } }, // 6 o'clock
  { role: 'free', position: { left: '39.54%', top: '28.7%' } }, // ~10:30 — computed on-ellipse
  { role: 'free', position: { left: '61.12%', top: '28.7%' } }, // ~1:30 — computed on-ellipse
];

// Maps each non-fist cell, in order, onto inventory slots 1-6. The fist cell
// has no entry (`null`) because it isn't backed by an inventory slot.
let nextWheelSlot = 0;
const CELL_SLOTS: Array<number | null> = WHEEL_CELLS.map((cell) =>
  cell.role === 'fist' ? null : ++nextWheelSlot
);

export const WHEEL_SLOTS = CELL_SLOTS.filter((slot): slot is number => slot !== null);

const getLabel = (slot: SlotWithItem) => slot.metadata?.label || Items[slot.name]?.label || slot.name;

/**
 * The small circular badge in a slot's top-right corner.
 *
 * ox_inventory has no "sub-category" concept, so this is mapped to the closest
 * thing the item data actually carries: a weapon that has attachments fitted
 * (`metadata.components`, an array of component item names — see
 * modules/inventory/server.lua) or that is loaded with special ammo
 * (`metadata.specialAmmo`). Both mean "this slot holds something extra beyond
 * the bare item", which is what the badge reads as in the reference. It is
 * therefore only drawn where that is genuinely true, never on arbitrary slots.
 */
const hasBadge = (slot: SlotWithItem): boolean => {
  const components = slot.metadata?.components;
  return (Array.isArray(components) && components.length > 0) || !!slot.metadata?.specialAmmo;
};

/**
 * Second caption line. Everything here comes from real item data:
 *  - the equipped slot reads "IN HAND"
 *  - a firearm reads the label of the ammo it takes (data/weapons.lua ->
 *    ammoName -> Items[ammoName].label)
 *  - a WEAPON_* item with no ammoName is a melee/thrown weapon
 *  - anything else falls back to its stack count
 * Nothing is invented when the data isn't there.
 */
const getCategory = (slot: SlotWithItem | undefined, isEquipped: boolean): string => {
  if (!slot) return '';
  if (isEquipped) return Locale.ui_in_hand || 'IN HAND';

  const data = Items[slot.name];

  if (data?.ammoName) return Items[data.ammoName]?.label || data.ammoName;
  if (slot.name.toUpperCase().startsWith('WEAPON_')) return Locale.ui_melee || 'MELEE';

  return `${slot.count}x`;
};

const ACCEPTS_BY_ROLE: Partial<Record<WheelRole, (name: string) => boolean>> = {
  melee: isMeleeItem,
  handheld: isHandheldItem,
};

interface Props {
  inventory: Inventory;
}

const WeaponWheel: React.FC<Props> = ({ inventory }) => {
  const currentWeaponSlot = useCurrentWeaponSlot();

  // Real wheel slots only (fist excluded), looked up by slot NUMBER rather
  // than by array position: an inventory array is not guaranteed to be dense
  // or ordered, and indexing it blindly is how a wheel ends up showing the
  // wrong item under the right key.
  const bySlot = useMemo(() => {
    const map = new Map<number, Slot>();
    for (const item of inventory.items) map.set(item.slot, item);
    return map;
  }, [inventory.items]);

  /*
   * The genuinely equipped weapon, not a stand-in.
   *
   * This used to be `occupied[0]` — the first weapon in the inventory — and
   * the card below labelled it IN HAND unconditionally, so it lied as soon as
   * you owned two guns. client.lua now reports the real slot (see
   * store/currentWeapon.ts) and this reads that.
   *
   * It is looked up across the WHOLE inventory, not just the wheel: you can be
   * holding something equipped from the grid or from slot 20, and the card
   * should still show what is actually in your hands.
   */
  const equipped = useMemo(() => {
    if (currentWeaponSlot == null) return undefined;
    const found = inventory.items.find((item) => item.slot === currentWeaponSlot);
    return found && isSlotWithItem(found) ? found : undefined;
  }, [inventory.items, currentWeaponSlot]);

  const [hovered, setHovered] = useState<number | null>(null);

  const onEnter = useCallback((index: number) => () => setHovered(index), []);
  const onLeave = useCallback(() => setHovered(null), []);

  /*
   * Click a cell to equip it (or, for the fist cell, to holster whatever's
   * equipped).
   *
   * `onUse` is fetchNui('useItem', slot) -> useSlot() in Lua: the same call
   * the 1-5(-7) hotkeys and alt+click already make, so this inherits every
   * check and animation they get rather than being a second, divergent equip
   * path. This is also what makes it possible to equip a wheel slot that has
   * no keybind at all — clicking has never depended on one.
   *
   * ctrl and alt are left alone deliberately — InventorySlot's own handler
   * already binds those to drop and use, and firing here as well would run
   * both on one click (ctrl+click would drop the item AND try to equip it).
   */
  const onCellClick = useCallback(
    (role: WheelRole, item: Slot | undefined) => (event: React.MouseEvent<HTMLDivElement>) => {
      if (event.ctrlKey || event.altKey) return;
      if (role === 'fist') {
        onDisarm();
        return;
      }
      if (!item || !isSlotWithItem(item)) return;
      onUse(item);
    },
    []
  );

  // Reserve ammo for the equipped weapon — summed from the player's actual
  // ammo stacks, never fabricated. `undefined` when the item isn't a firearm.
  const reserveAmmo = useMemo(() => {
    const ammoName = equipped && Items[equipped.name]?.ammoName;
    if (!ammoName) return undefined;

    let total = 0;

    for (const slot of inventory.items) {
      if (isSlotWithItem(slot) && slot.name === ammoName) total += slot.count;
    }

    return total;
  }, [equipped, inventory.items]);

  const magazineAmmo = equipped?.metadata?.ammo;

  // Wheel cells can be empty (they double as drop targets), so the caption only
  // reads a hovered cell when it actually holds something — hovering an empty
  // cell falls back to the equipped weapon rather than blanking out. Hovering
  // the fist cell always reads UNARMED, since it never holds an item.
  const hoveredCell = hovered !== null ? WHEEL_CELLS[hovered] : undefined;
  const hoveredSlotNumber = hovered !== null ? CELL_SLOTS[hovered] : null;
  const hoveredItem = hoveredSlotNumber !== null ? bySlot.get(hoveredSlotNumber) : undefined;
  const hoveringFist = hoveredCell?.role === 'fist';

  const captionSlot = !hoveringFist && hoveredItem && isSlotWithItem(hoveredItem) ? hoveredItem : equipped;
  const captionIsEquipped = !hoveringFist && !!captionSlot && !!equipped && captionSlot.slot === equipped.slot;
  const captionIsUnarmed = hoveringFist || (!captionSlot && currentWeaponSlot == null);

  // Takes a plain `Slot`, not `SlotWithItem`: an EMPTY slot still has to render
  // as a real InventorySlot so react-dnd registers it as a drop target. This is
  // the same thing InventoryGrid does for its empty cells.
  const renderSlot = (item: Slot, accepts?: (name: string) => boolean) => (
    <InventorySlot
      item={item}
      inventoryId={inventory.id}
      inventoryType={inventory.type}
      inventoryGroups={inventory.groups}
      accepts={accepts}
    />
  );

  return (
    <>
      <div className="gta6-wheel-dot" />

      {/*
        The equipped card is a READ-ONLY readout of what is in your hands, not a
        wheel cell. It used to render an InventorySlot for whatever happened to
        be first in the inventory, which made it both a drop target and a lie.
        Ring cells below are where things are put; this shows the result of
        picking one. It doubles as the wheel's "top = weapon" position: nothing
        but a weapon ever produces a meaningful ammo readout here, and melee/
        handheld items each have their own dedicated ring cell instead.
      */}
      <div className="gta6-equipped-slot">
        {equipped && (
          <div
            className="inventory-slot gta6-equipped-readout"
            style={{ backgroundImage: `url(${getItemUrl(equipped)})` }}
          />
        )}
        <div className="gta6-equipped-glow" />
        {equipped && (magazineAmmo !== undefined || reserveAmmo !== undefined) && (
          <div className="gta6-equipped-ammo">
            {magazineAmmo !== undefined && <span className="gta6-ammo-mag">{magazineAmmo}</span>}
            {reserveAmmo !== undefined && <span className="gta6-ammo-reserve">{reserveAmmo}</span>}
          </div>
        )}
        {equipped && hasBadge(equipped) && <span className="gta6-slot-badge" />}
      </div>

      {WHEEL_CELLS.map((cell, index) => {
        const slotNumber = CELL_SLOTS[index];
        const item = slotNumber !== null ? bySlot.get(slotNumber) : undefined;
        const isEquipped = cell.role !== 'fist' && !!item && !!equipped && item.slot === equipped.slot;
        const isFistEquipped = cell.role === 'fist' && currentWeaponSlot == null;

        return (
          <div
            key={`gta6-wheel-${inventory.id}-${cell.role}-${slotNumber ?? 'fist'}`}
            className={
              'gta6-wheel-slot' +
              ` gta6-wheel-slot-${cell.role}` +
              (hovered === index ? ' gta6-wheel-slot-selected' : '') +
              (isEquipped || isFistEquipped ? ' gta6-wheel-slot-equipped' : '')
            }
            style={cell.position}
            onMouseEnter={onEnter(index)}
            onMouseLeave={onLeave}
            onClick={onCellClick(cell.role, item)}
          >
            {cell.role === 'fist' ? (
              <div className="gta6-wheel-fist" />
            ) : (
              <>
                {item && renderSlot(item, ACCEPTS_BY_ROLE[cell.role])}
                {item && isSlotWithItem(item) && hasBadge(item) && <span className="gta6-slot-badge" />}
              </>
            )}
          </div>
        );
      })}

      {/* Text only — there is deliberately no slot box behind the caption. */}
      <div className="gta6-wheel-caption">
        <span className="gta6-wheel-caption-name">
          {captionIsUnarmed ? Locale.ui_unarmed || 'UNARMED' : captionSlot ? getLabel(captionSlot) : ''}
        </span>
        <span className="gta6-wheel-caption-sub">
          {captionIsUnarmed ? '' : getCategory(captionSlot, captionIsEquipped)}
        </span>
      </div>
    </>
  );
};

export default WeaponWheel;
