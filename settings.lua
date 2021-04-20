
--- Determines handling of punched helicopter.
--
-- If `false`, helicopter is destroyed. Otherwise, it is added to inventory.
--   - Default: false
helicopter.pick_up = minetest.settings:get_bool("helicopter.pick_up", false)
