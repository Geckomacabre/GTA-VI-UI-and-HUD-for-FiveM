import React from 'react';

/**
 * STUB / VISUAL PLACEHOLDER — not wired to real data.
 *
 * ox_inventory's NUI layer never receives the player's health, armour or
 * stamina — this resource is inventory-only and doesn't track ped stats.
 * These bars are styled to match the GTA6 reference art (heart / lightning /
 * shield icons with thin segmented pill bars) but intentionally render at
 * 0% so nobody mistakes this decoration for a live HUD.
 *
 * To make this real you would need to, e.g.:
 *   1. In client.lua, on an interval while the inventory is open, read
 *      GetEntityHealth(cache.ped), GetPedArmour(cache.ped) and a stamina
 *      value (vanilla FiveM has no native player stamina — this usually
 *      comes from your framework, e.g. esx_status / qbx_core) and
 *      SendNUIMessage({ action = 'setPlayerStatus', data = { health, armor, stamina } }).
 *   2. Add a useNuiEvent('setPlayerStatus', ...) listener (here, or in a
 *      redux slice under store/) and drive the `width` percentages below
 *      from that state instead of the hardcoded 0.
 *
 * No such callback/event exists yet in this codebase — this component is
 * layout/CSS groundwork only.
 */
const PlayerStatusBars: React.FC = () => {
  return (
    <div className="gta6-status-bars" aria-hidden="true" title="placeholder — not wired to real player stats">
      <div className="gta6-status-row gta6-status-health">
        <span className="gta6-status-icon">♥</span>
        <div className="gta6-status-track">
          <div className="gta6-status-fill" style={{ width: '0%' }} />
        </div>
      </div>
      <div className="gta6-status-row gta6-status-stamina">
        <span className="gta6-status-icon">⚡</span>
        <div className="gta6-status-track">
          <div className="gta6-status-fill" style={{ width: '0%' }} />
        </div>
      </div>
      <div className="gta6-status-row gta6-status-armor">
        <span className="gta6-status-icon">🛡</span>
        <div className="gta6-status-track">
          <div className="gta6-status-fill" style={{ width: '0%' }} />
        </div>
      </div>
    </div>
  );
};

export default PlayerStatusBars;
