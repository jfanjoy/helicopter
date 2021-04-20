
--- Determines handling of punched helicopter.
--
--  If `false`, helicopter is destroyed. Otherwise, it is added to inventory.
--    - Default: false
helicopter.pick_up = minetest.settings:get_bool("helicopter.pick_up", false)

--- Determines default control of helicopter.
--
--  Use facing direction to turn instead of a/d keys by default.
--    - Default: false
helicopter.turn_player_look = minetest.settings:get_bool("mount_turn_player_look", false)
