import React, { useCallback, useMemo, useState } from 'react';
import InventorySlot from './InventorySlot';
import { Inventory, Slot, SlotWithItem } from '../../typings';
import { isSlotWithItem, getItemUrl } from '../../helpers';
import { Items } from '../../store/items';
import { Locale } from '../../store/locale';
import { useCurrentWeaponSlot } from '../../store/currentWeapon';
import { onUse } from '../../dnd/onUse';

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
 */

// Deliberately *not* evenly spaced on a circle — these are the measured
// centres from the reference art.
const WHEEL_POSITIONS: Array<React.CSSProperties> = [
  { left: '35.08%', top: '48.49%' },
  { left: '65.5%', top: '48.49%' },
  { left: '38.33%', top: '63.61%' },
  { left: '62.45%', top: '63.61%' },
  { left: '50.33%', top: '73.67%' },
];

/*
 * The wheel is PINNED to inventory slots 1-5, in order.
 *
 * It used to list whatever weapons you happened to own, in inventory order,
 * which meant a given gun moved around the ring as you picked things up and
 * dropped them. A wheel is only faster than a menu because your hand learns
 * where things are, so that undermined the whole point — and it meant the ring
 * and the 1-5 hotkeys could disagree about what "slot 3" was.
 *
 * Pinning them makes the two the same thing: cell N *is* hotbar slot N, the
 * number keys and the wheel always agree, and choosing what is on the wheel is
 * just dragging items into the first five slots.
 */
export const WHEEL_SLOTS = [1, 2, 3, 4, 5];
export const MAX_WHEEL_SLOTS = WHEEL_POSITIONS.length;

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

interface Props {
  inventory: Inventory;
}

const WeaponWheel: React.FC<Props> = ({ inventory }) => {
  const currentWeaponSlot = useCurrentWeaponSlot();

  // Slots 1-5 exactly, looked up by slot NUMBER rather than by array position:
  // an inventory array is not guaranteed to be dense or ordered, and indexing
  // it blindly is how a wheel ends up showing the wrong item under the right
  // key.
  const wheelItems = useMemo(() => {
    const bySlot = new Map<number, Slot>();
    for (const item of inventory.items) bySlot.set(item.slot, item);
    return WHEEL_SLOTS.map((slot) => bySlot.get(slot));
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
   * Click a cell to equip it.
   *
   * `onUse` is fetchNui('useItem', slot) -> useSlot() in Lua: the same call
   * the 1-5 hotkeys and alt+click already make, so this inherits every check
   * and animation they get rather than being a second, divergent equip path.
   *
   * ctrl and alt are left alone deliberately — InventorySlot's own handler
   * already binds those to drop and use, and firing here as well would run
   * both on one click (ctrl+click would drop the item AND try to equip it).
   */
  const onCellClick = useCallback(
    (item: Slot | undefined) => (event: React.MouseEvent<HTMLDivElement>) => {
      if (event.ctrlKey || event.altKey) return;
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
  // cell falls back to the equipped weapon rather than blanking out.
  const hoveredSlot = hovered !== null ? wheelItems[hovered] : undefined;
  const captionSlot = hoveredSlot && isSlotWithItem(hoveredSlot) ? hoveredSlot : equipped;
  const captionIsEquipped = !!captionSlot && !!equipped && captionSlot.slot === equipped.slot;

  // Takes a plain `Slot`, not `SlotWithItem`: an EMPTY slot still has to render
  // as a real InventorySlot so react-dnd registers it as a drop target. This is
  // the same thing InventoryGrid does for its empty cells.
  const renderSlot = (item: Slot) => (
    <InventorySlot
      item={item}
      inventoryId={inventory.id}
      inventoryType={inventory.type}
      inventoryGroups={inventory.groups}
    />
  );

  return (
    <>
      <div className="gta6-wheel-dot" />

      {/*
        The equipped card is a READ-ONLY readout of what is in your hands, not a
        sixth wheel slot. It used to render an InventorySlot for whatever
        happened to be first in the inventory, which made it both a drop target
        and a lie. Slots 1-5 below are where things are put; this shows the
        result of picking one.
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

      {WHEEL_POSITIONS.map((position, index) => {
        const item = wheelItems[index];
        const isEquipped = !!item && !!equipped && item.slot === equipped.slot;

        return (
          <div
            key={`gta6-wheel-${inventory.id}-${WHEEL_SLOTS[index]}`}
            className={
              'gta6-wheel-slot' +
              (hovered === index ? ' gta6-wheel-slot-selected' : '') +
              (isEquipped ? ' gta6-wheel-slot-equipped' : '')
            }
            style={position}
            onMouseEnter={onEnter(index)}
            onMouseLeave={onLeave}
            onClick={onCellClick(item)}
          >
            {item && renderSlot(item)}
            {item && isSlotWithItem(item) && hasBadge(item) && <span className="gta6-slot-badge" />}
          </div>
        );
      })}

      {/* Text only — there is deliberately no slot box behind the caption. */}
      <div className="gta6-wheel-caption">
        <span className="gta6-wheel-caption-name">
          {captionSlot ? getLabel(captionSlot) : Locale.ui_unarmed || 'UNARMED'}
        </span>
        <span className="gta6-wheel-caption-sub">{getCategory(captionSlot, captionIsEquipped)}</span>
      </div>
    </>
  );
};

export default WeaponWheel;
