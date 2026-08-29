import React, { useMemo } from 'react';
import InventorySlot from './InventorySlot';
import InventoryTabs from './InventoryTabs';
import WeaponWheel, { WHEEL_SLOTS } from './WeaponWheel';
import ItemWheel, { ITEM_WHEEL_SLOTS } from './ItemWheel';
import { useActiveTab, setActiveTab } from '../../store/activeTab';
import PlayerStatusBars from './PlayerStatusBars';
import PromptGlyph from './PromptGlyph';
import { useAppSelector } from '../../store';
import { selectLeftInventory } from '../../store/inventory';
import { isSlotWithItem } from '../../helpers';
import { usePromptGlyphs } from '../../store/promptGlyphs';
import { SlotWithItem } from '../../typings';
import { isMedicalItem } from '../../store/wheelCategories';
import { useHonor } from '../../store/honor';

const MAX_QUICKSLOTS = 2;

const LeftInventory: React.FC = () => {
  const leftInventory = useAppSelector(selectLeftInventory);
  // Held outside React so client.lua can choose the tab: holding TAB opens the
  // wheel, F2 opens the grid. See store/activeTab.ts.
  const activeTab = useActiveTab();
  const glyphs = usePromptGlyphs();
  const { honor, tier } = useHonor();

  const onWeapons = activeTab === 'weapons';

  /*
   * The two tabs are two different wheels, never both at once, and never the
   * plain square grid:
   *   WEAPONS -> WeaponWheel (slots 1-7, fist cell not slot-backed)
   *   ITEMS   -> ItemWheel (slots 8-15)
   *
   * These two wheels are meant to be all a player can carry on their person
   * — the full square inventory only exists for a backpack's own stash
   * (wasabi_backpack opens that as a separate inventory; see
   * modules/gta6pockets/server.lua for the slot-count/weight cap this
   * enforces server-side). LeftInventory therefore never renders
   * InventoryGrid at all any more.
   */

  // Both wheels' slots are excluded from the quick-use strip so the two never
  // fight over the same items.
  const wheelSlotIds = useMemo(() => new Set([...WHEEL_SLOTS, ...ITEM_WHEEL_SLOTS]), []);

  // Medical-only quick-slots (bottom-left) — see wheelCategories.ts for the
  // curated item list this is restricted to. It used to accept any `usable`
  // item (food, drinks, drugs, bandages alike), which meant a burger could
  // bump a bandage out of the strip; medical is the one category this corner
  // is for.
  /*
   * Read-only, auto-populated readout, matching the reference: these are NOT
   * drop targets you drag a bandage onto to "assign" it. Whatever medical
   * items are already in the inventory just show up here on their own, up to
   * MAX_QUICKSLOTS, in whatever slot order they're found. No empty-slot
   * padding either — with nothing to show, the strip just shows fewer cells,
   * same as the reference doesn't draw an empty holster for a gun you don't
   * have. InventorySlot itself is still the real slot underneath (so
   * hovering/alt-click-use/dragging it back OUT still all work), it just no
   * longer accepts drops.
   */
  const quickItems = useMemo(
    () =>
      leftInventory.items
        .filter((item): item is SlotWithItem => isSlotWithItem(item) && isMedicalItem(item.name))
        .filter((item) => !wheelSlotIds.has(item.slot))
        .slice(0, MAX_QUICKSLOTS),
    [leftInventory.items, wheelSlotIds]
  );

  return (
    // Full-viewport overlay, not a floating card: everything inside is
    // absolutely positioned against the viewport at the measured percentages.
    // pointer-events are re-enabled per child so the right-hand inventory
    // stays clickable through the empty areas.
    <div className="gta6-left-panel">
      {/* PlayerStatusBars is intentionally NOT rendered. ox_inventory's NUI
          never receives health/armour/stamina, so it could only ever draw three
          empty bars, which reads as broken. vice_hud already paints real ones
          on the play HUD. Re-enable this only once client.lua actually pushes
          those values in. */}

      <InventoryTabs active={activeTab} onChange={setActiveTab} />

      {onWeapons ? <WeaponWheel inventory={leftInventory} /> : <ItemWheel inventory={leftInventory} />}

      <div className="gta6-quickslots">
        {quickItems.map((item) => (
          <div className="gta6-quickslot" key={`quickslot-${leftInventory.id}-${item.slot}`}>
            <InventorySlot
              item={item}
              inventoryId={leftInventory.id}
              inventoryType={leftInventory.type}
              inventoryGroups={leftInventory.groups}
            />
            <div className="gta6-quickslot-footer">
              <span className="gta6-quickslot-count">{item.count}</span>
              <span className="gta6-quickslot-pip" />
            </div>
          </div>
        ))}
      </div>

      {/*
        Honor standing (bottom-right), fed by qbx_honor via client.lua's
        'setHonor' NUI message — see store/honor.ts. Renders nothing until
        qbx_honor actually reports a value, rather than showing a fake 0.
      */}
      {honor !== null && (
        <div className={'gta6-honor' + (tier ? ` gta6-honor-${tier}` : '')}>
          <span className="gta6-honor-value">{honor}</span>
        </div>
      )}

      {/* Live keybind prompts — labels come from client.lua's setPromptGlyphs. */}
      <div className="gta6-prompt gta6-prompt-primary">
        <PromptGlyph label={glyphs.quickslot1} device={glyphs.device} size="lg" />
      </div>
      <div className="gta6-prompt gta6-prompt-secondary">
        <PromptGlyph label={glyphs.quickslot2} device={glyphs.device} size="sm" />
      </div>

      <div className="gta6-drop-rule" />
      <div className="gta6-drop-hint">
        <span>Drop</span>
        <PromptGlyph label={glyphs.drop} device={glyphs.device} size="sm" />
      </div>
    </div>
  );
};

export default LeftInventory;
