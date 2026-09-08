import { fetchNui } from '../utils/fetchNui';

/** Clicking the wheel's fixed fist cell holsters whatever is currently equipped. */
export const onDisarm = () => {
  fetchNui('disarmWeapon');
};
