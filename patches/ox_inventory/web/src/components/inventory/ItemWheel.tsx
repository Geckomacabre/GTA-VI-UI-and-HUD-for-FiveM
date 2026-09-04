import React, { useCallback, useEffect, useMemo, useState } from 'react';
import InventorySlot from './InventorySlot';
import { Inventory, Slot, SlotWithItem } from '../../typings';
import { isSlotWithItem } from '../../helpers';
import { Items } from '../../store/items';
import { Locale } from '../../store/locale';
import { ClothingRole, ClothingState, fetchClothingState, onToggleClothing } from '../../dnd/onToggleClothing';

/*
 * GTA6-style item wheel — the ITEMS tab's counterpart to WeaponWheel.tsx.
 *
 * Reuses WEAPON_CELLS' exact geometry (same eight measured positions, same
 * gta6-wheel-slot chrome). Five cells are still plain 'free' inventory slots
 * for ordinary carried items, same as before. Three are fixed clothing
 * toggles (bandana/mask, hat, eyewear) wired to um_clothing, which owns
 * worn-prop state as ped components, not inventory items — so, like
 * WeaponWheel's 'fist' cell, these aren't backed by a real inventory slot at
 * all. The remaining cell (~4-5 o'clock) is a static hanger icon reserved
 * for future use, same idea, no behaviour yet.
 *
 * 'free' cells claim their own slot range starting at 8 so they never
 * collide with WeaponWheel's slots 1-7 (see WHEEL_SLOTS in WeaponWheel.tsx).
 */
type ItemCellRole = 'free' | 'mask' | 'hat' | 'eyewear' | 'hanger';

interface ItemCell {
  role: ItemCellRole;
  position: React.CSSProperties;
}

const ITEM_CELLS: ItemCell[] = [
  { role: 'mask', position: { left: '50.35%', top: '23.35%' } }, // 12 o'clock — bandana/mask
  { role: 'eyewear', position: { left: '35.08%', top: '48.49%' } }, // ~10 o'clock — eyewear
  { role: 'hat', position: { left: '65.5%', top: '48.49%' } }, // 3 o'clock — hat
  { role: 'free', position: { left: '38.33%', top: '63.61%' } }, // ~8 o'clock
  { role: 'hanger', position: { left: '62.45%', top: '63.61%' } }, // ~4-5 o'clock — hanger, unused for now
  { role: 'free', position: { left: '50.33%', top: '73.67%' } }, // 6 o'clock
  { role: 'free', position: { left: '38.33%', top: '33.37%' } }, // mirrors ~8 o'clock across the middle row
  { role: 'free', position: { left: '62.45%', top: '33.37%' } }, // mirrors ~4 o'clock across the middle row
];

let nextItemWheelSlot = 7; // WeaponWheel claims 1-7 — start immediately after it.
const CELL_SLOTS: Array<number | null> = ITEM_CELLS.map((cell) => (cell.role === 'free' ? ++nextItemWheelSlot : null));
export const ITEM_WHEEL_SLOTS = CELL_SLOTS.filter((slot): slot is number => slot !== null);

// nui:// absolute path, same convention .gta6-wheel-fist uses for fist.png.
const CLOTHING_IMAGES: Partial<Record<ItemCellRole, string>> = {
  mask: 'nui://ox_inventory/web/images/mask.png',
  hat: 'nui://ox_inventory/web/images/hat.png',
  eyewear: 'nui://ox_inventory/web/images/eyewear.png',
  hanger: 'nui://ox_inventory/web/images/hanger.png',
};

const isClothingRole = (role: ItemCellRole): role is ClothingRole => role === 'mask' || role === 'hat' || role === 'eyewear';

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

  // Lives in um_clothing (ped props/components), not in inventory.items, so
  // it can't be derived from `inventory` like every other cell here — it has
  // to be fetched and kept in local state instead.
  const [clothing, setClothing] = useState<ClothingState>({});

  useEffect(() => {
    fetchClothingState().then((state) => state && setClothing(state));
  }, []);

  const onEnter = useCallback((index: number) => () => setHovered(index), []);
  const onLeave = useCallback(() => setHovered(null), []);

  const onClothingClick = useCallback(
    (role: ClothingRole) => (event: React.MouseEvent<HTMLDivElement>) => {
      if (event.ctrlKey || event.altKey) return;
      onToggleClothing(role).then((state) => state && setClothing(state));
    },
    []
  );

  const renderSlot = (item: Slot) => (
    <InventorySlot
      item={item}
      inventoryId={inventory.id}
      inventoryType={inventory.type}
      inventoryGroups={inventory.groups}
    />
  );

  const hoveredCell = hovered !== null ? ITEM_CELLS[hovered] : undefined;
  const hoveredSlotNumber = hovered !== null ? CELL_SLOTS[hovered] : null;
  const hoveredItem = hoveredSlotNumber !== null ? bySlot.get(hoveredSlotNumber) : undefined;
  const captionSlot = hoveredItem && isSlotWithItem(hoveredItem) ? hoveredItem : undefined;
  const hoveredClothingRole = hoveredCell && isClothingRole(hoveredCell.role) ? hoveredCell.role : undefined;

  const CLOTHING_LABELS: Partial<Record<ClothingRole, string>> = {
    mask: Locale.ui_mask || 'MASK',
    hat: Locale.ui_hat || 'HEADWEAR',
    eyewear: Locale.ui_eyewear || 'EYEWEAR',
  };

  return (
    <>
      <div className="gta6-wheel-dot" />

      {ITEM_CELLS.map((cell, index) => {
        const slotNumber = CELL_SLOTS[index];
        const item = slotNumber !== null ? bySlot.get(slotNumber) : undefined;
        const image = CLOTHING_IMAGES[cell.role];
        const clothingRole = isClothingRole(cell.role) ? cell.role : undefined;
        const isOn = !!clothingRole && !!clothing[clothingRole];

        return (
          <div
            key={`gta6-item-wheel-${inventory.id}-${cell.role}-${slotNumber ?? index}`}
            className={
              'gta6-wheel-slot gta6-wheel-slot-free' +
              (hovered === index ? ' gta6-wheel-slot-selected' : '') +
              (isOn ? ' gta6-wheel-slot-equipped' : '')
            }
            style={cell.position}
            onMouseEnter={onEnter(index)}
            onMouseLeave={onLeave}
            onClick={clothingRole ? onClothingClick(clothingRole) : undefined}
          >
            {image ? (
              <>
                <div className="gta6-wheel-clothing" style={{ backgroundImage: `url('${image}')` }} />
                {clothingRole && (
                  <div className="gta6-clothing-state">{isOn ? Locale.ui_on || 'ON' : Locale.ui_off || 'OFF'}</div>
                )}
              </>
            ) : (
              <>
                {item && renderSlot(item)}
                {item && isSlotWithItem(item) && hasBadge(item) && <span className="gta6-slot-badge" />}
              </>
            )}
          </div>
        );
      })}

      {/* Text only — same caption strip as WeaponWheel, no slot box behind it. */}
      <div className="gta6-wheel-caption">
        <span className="gta6-wheel-caption-name">
          {hoveredClothingRole ? CLOTHING_LABELS[hoveredClothingRole] : captionSlot ? getLabel(captionSlot) : ''}
        </span>
        <span className="gta6-wheel-caption-sub">
          {hoveredClothingRole
            ? clothing[hoveredClothingRole]
              ? Locale.ui_on || 'ON'
              : Locale.ui_off || 'OFF'
            : captionSlot
            ? `${captionSlot.count}x`
            : Locale.ui_empty || ''}
        </span>
      </div>
    </>
  );
};

export default ItemWheel;
