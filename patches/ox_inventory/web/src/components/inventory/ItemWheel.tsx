import React, { useCallback, useMemo, useState } from 'react';
import InventorySlot from './InventorySlot';
import { Inventory, Slot, SlotWithItem } from '../../typings';
import { isSlotWithItem } from '../../helpers';
import { Items } from '../../store/items';
import { Locale } from '../../store/locale';

/*
 * GTA6-style item wheel — the ITEMS tab's counterpart to WeaponWheel.tsx.
 *
 * Reuses WEAPON_CELLS' exact geometry (same eight measured positions, same
 * gta6-wheel-slot chrome) but every cell is a plain 'free' role — no fist
 * button, no weapon/melee/handheld restriction, since this tab is for
 * ordinary carried items, not guns.
 *
 * It claims its own slot range (8-15) so it never collides with
 * WeaponWheel's slots 1-7 (see WHEEL_SLOTS in WeaponWheel.tsx) — the two
 * wheels are simultaneously "live" inventory space, just shown one tab at a
 * time.
 */
const ITEM_CELL_POSITIONS: React.CSSProperties[] = [
  { left: '50.35%', top: '23.35%' }, // 12 o'clock
  { left: '35.08%', top: '48.49%' }, // ~10 o'clock
  { left: '65.5%', top: '48.49%' }, // 3 o'clock
  { left: '38.33%', top: '63.61%' }, // ~8 o'clock
  { left: '62.45%', top: '63.61%' }, // ~4 o'clock
  { left: '50.33%', top: '73.67%' }, // 6 o'clock
  { left: '38.33%', top: '33.37%' }, // mirrors ~8 o'clock across the middle row
  { left: '62.45%', top: '33.37%' }, // mirrors ~4 o'clock across the middle row
];

let nextItemWheelSlot = 7; // WeaponWheel claims 1-7 — start immediately after it.
export const ITEM_WHEEL_SLOTS: number[] = ITEM_CELL_POSITIONS.map(() => ++nextItemWheelSlot);

const getLabel = (slot: SlotWithItem) => slot.metadata?.label || Items[slot.name]?.label || slot.name;

const hasBadge = (slot: SlotWithItem): boolean => {
  const components = slot.metadata?.components;
  return (Array.isArray(components) && components.length > 0) || !!slot.metadata?.specialAmmo;
};

interface Props {
  inventory: Inventory;
}

const ItemWheel: React.FC<Props> = ({ inventory }) => {
  const bySlot = useMemo(() => {
    const map = new Map<number, Slot>();
    for (const item of inventory.items) map.set(item.slot, item);
    return map;
  }, [inventory.items]);

  const [hovered, setHovered] = useState<number | null>(null);

  const onEnter = useCallback((index: number) => () => setHovered(index), []);
  const onLeave = useCallback(() => setHovered(null), []);

  const renderSlot = (item: Slot) => (
    <InventorySlot
      item={item}
      inventoryId={inventory.id}
      inventoryType={inventory.type}
      inventoryGroups={inventory.groups}
    />
  );

  const hoveredSlotNumber = hovered !== null ? ITEM_WHEEL_SLOTS[hovered] : null;
  const hoveredItem = hoveredSlotNumber !== null ? bySlot.get(hoveredSlotNumber) : undefined;
  const captionSlot = hoveredItem && isSlotWithItem(hoveredItem) ? hoveredItem : undefined;

  return (
    <>
      <div className="gta6-wheel-dot" />

      {ITEM_CELL_POSITIONS.map((position, index) => {
        const slotNumber = ITEM_WHEEL_SLOTS[index];
        const item = bySlot.get(slotNumber);

        return (
          <div
            key={`gta6-item-wheel-${inventory.id}-${slotNumber}`}
            className={'gta6-wheel-slot gta6-wheel-slot-free' + (hovered === index ? ' gta6-wheel-slot-selected' : '')}
            style={position}
            onMouseEnter={onEnter(index)}
            onMouseLeave={onLeave}
          >
            {item && renderSlot(item)}
            {item && isSlotWithItem(item) && hasBadge(item) && <span className="gta6-slot-badge" />}
          </div>
        );
      })}

      {/* Text only — same caption strip as WeaponWheel, no slot box behind it. */}
      <div className="gta6-wheel-caption">
        <span className="gta6-wheel-caption-name">{captionSlot ? getLabel(captionSlot) : ''}</span>
        <span className="gta6-wheel-caption-sub">
          {captionSlot ? `${captionSlot.count}x` : Locale.ui_empty || ''}
        </span>
      </div>
    </>
  );
};

export default ItemWheel;
