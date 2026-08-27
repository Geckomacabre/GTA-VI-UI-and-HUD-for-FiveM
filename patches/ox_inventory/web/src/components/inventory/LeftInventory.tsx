import React, { useMemo } from 'react';
import InventoryGrid from './InventoryGrid';
import InventorySlot from './InventorySlot';
import InventoryTabs from './InventoryTabs';
import WeaponWheel, { WHEEL_SLOTS } from './WeaponWheel';
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
   * The two tabs are two different presentations, never both at once:
   *   WEAPONS -> the wheel, nothing else
   *   ITEMS   -> the ordinary grid
   *
   * The grid deliberately shows the WHOLE inventory now, weapons included. It
   * used to hide them, which made it impossible to put a gun on the wheel:
   * the wheel is inventory slots 1-6, and the only way to fill those is to
   * drag something into them from the grid. Hiding weapons there meant the one
   * thing the wheel is for was the one thing you could not drag onto it.
   */

  // The wheel owns slots 1-6 (see WHEEL_SLOTS in WeaponWheel.tsx — the fist
  // cell isn't backed by a slot at all), so the quick-use slots have to live
  // past them or the two would fight over the same items.
  const wheelSlotIds = useMemo(() => new Set(WHEEL_SLOTS), []);

  // Medical-only quick-slots (bottom-left) — see wheelCategories.ts for the
  // curated item list this is restricted to. It used to accept any `usable`
  // item (food, drinks, drugs, bandages alike), which meant a burger could
  // bump a bandage out of the strip; medical is the one category this corner
  // is for.
  /*
   * The quick-use slots ALWAYS render, filled or not — the reference shows two
   * slots with the empty one reading "0" rather than disappearing. Medical
   * items fill them first; any remaining slots are padded with real EMPTY
   * inventory slots so they stay valid drop targets.
   */
  const quickItems = useMemo(() => {
    const usable = leftInventory.items
      .filter((item): item is SlotWithItem => isSlotWithItem(item) && isMedicalItem(item.name))
      .filter((item) => !wheelSlotIds.has(item.slot))
      .slice(0, MAX_QUICKSLOTS);

    if (usable.length >= MAX_QUICKSLOTS) return usable;

    const taken = new Set(usable.map((i) => i.slot));
    const empties = leftInventory.items.filter(
      (item) => !isSlotWithItem(item) && !wheelSlotIds.has(item.slot) && !taken.has(item.slot)
    );

    return [...usable, ...empties].slice(0, MAX_QUICKSLOTS);
  }, [leftInventory.items, wheelSlotIds]);

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

      {onWeapons ? (
        <WeaponWheel inventory={leftInventory} />
      ) : (
        <div className="gta6-items-grid">
          <InventoryGrid inventory={leftInventory} />
        </div>
      )}

      <div className="gta6-quickslots">
        {quickItems.map((item) => (
          <div className="gta6-quickslot" key={`quickslot-${leftInventory.id}-${item.slot}`}>
            <InventorySlot
              item={item}
              inventoryId={leftInventory.id}
              inventoryType={leftInventory.type}
              inventoryGroups={leftInventory.groups}
              accepts={isMedicalItem}
            />
            <div className="gta6-quickslot-footer">
              <span className="gta6-quickslot-count">{isSlotWithItem(item) ? item.count : 0}</span>
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
