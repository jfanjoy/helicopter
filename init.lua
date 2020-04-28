--
-- constants
--

local friction_air_quadratic = 0.01
local friction_air_constant = 0.2
local friction_land_quadratic = 1
local friction_land_constant = 2
local friction_water_quadratic = 0.1
local friction_water_constant = 1

--dofile(minetest.get_modpath(minetest.get_current_modname()) .. DIR_DELIM .. "heli_hud.lua")
dofile(minetest.get_modpath("helicopter") .. DIR_DELIM .. "heli_hud.lua")
dofile(minetest.get_modpath("helicopter") .. DIR_DELIM .. "heli_control.lua")
dofile(minetest.get_modpath("helicopter") .. DIR_DELIM .. "fuel_management.lua")

--
-- helpers and co.
--

if not minetest.global_exists("matrix3") then
	dofile(minetest.get_modpath("helicopter") .. DIR_DELIM .. "matrix.lua")
end

local creative_exists = minetest.global_exists("creative")

local function check_is_under_water(obj)
	local pos_up = obj:get_pos()
	pos_up.y = pos_up.y + 0.1
	local node_up = minetest.get_node(pos_up).name
	local nodedef = minetest.registered_nodes[node_up]
	local liquid_up = nodedef.liquidtype ~= "none"
	return liquid_up
end

local function get_hipotenuse_value(point1, point2)
    return math.sqrt((point1.x - point2.x) ^ 2 + (point1.y - point2.y) ^ 2 + (point1.z - point2.z) ^ 2)
end

--
-- entity
--

minetest.register_entity("helicopter:heli", {
	initial_properties = {
		physical = true,
		collide_with_objects = true,
		collisionbox = {-1,0,-1, 1,0.3,1},
		selectionbox = {-1,0,-1, 1,0.3,1},
		visual = "mesh",
		mesh = "helicopter_heli.b3d",
        textures = {"interior_black.png", "metal.png", "strips.png", "painting.png", "black.png", "aluminum.png", "heli_glass.png", "heli_glass.png", "interior.png", "panel.png", "colective.png", "painting.png", "rotors.png", "interior_black.png",},
	},

	driver_name = nil,
	sound_handle = nil,
	tilting = vector.new(),
    energy = 0.001,
    owner = "",
    static_save = true,
    infotext = "A nice helicopter",
    last_vel = vector.new(),
    damage = 0,

    get_staticdata = function(self) -- unloaded/unloads ... is now saved
        if self.driver_name == nil then 
            if self.sound_handle ~= nil then
		        minetest.sound_stop(self.sound_handle)
		        self.sound_handle = nil
            end
        end
        return minetest.serialize({
            stored_energy = self.energy,
            stored_owner = self.owner,
        })
    end,

	on_activate = function(self, staticdata, dtime_s)
        if staticdata ~= "" and staticdata ~= nil then
            local data = minetest.deserialize(staticdata) or {}
            self.energy = data.stored_energy
            self.owner = data.stored_owner
            --minetest.debug("loaded: ", self.energy)
        end

        local pos = self.object:get_pos()
	    local pointer=minetest.add_entity(pos,'helicopter:pointer')
        local energy_indicator_angle = get_pointer_angle(self.energy)
	    pointer:set_attach(self.object,'',{x=0,y=11.26,z=9.37},{x=0,y=0,z=energy_indicator_angle})
	    self.pointer = pointer

		-- set the animation once and later only change the speed
		self.object:set_animation({x = 0, y = 11}, 0, 0, true)

		self.object:set_armor_groups({immortal=1})

		self.object:set_acceleration(vector.multiply(vector_up, -gravity))
	end,

	on_step = function(self, dtime)
		local touching_ground, liquid_below

		local vel = self.object:get_velocity()

		if self.driver_name then
			touching_ground, liquid_below = check_node_below(self.object)
			vel = heli_control(self, dtime, touching_ground, liquid_below, vel) or vel
		end

		if vel.x == 0 and vel.y == 0 and vel.z == 0 then
			return
		end

		if touching_ground == nil then
			touching_ground, liquid_below = check_node_below(self.object)
		end

		-- quadratic and constant deceleration
		local speedsq = vector_length_sq(vel)
		local fq, fc
		if touching_ground then
			fq, fc = friction_land_quadratic, friction_land_constant
		elseif liquid_below then
			fq, fc = friction_water_quadratic, friction_water_constant
		else
			fq, fc = friction_air_quadratic, friction_air_constant
		end
		vel = vector.apply(vel, function(a)
			local s = math.sign(a)
			a = math.abs(a)
			a = math.max(0, a - fq * dtime * speedsq - fc * dtime)
			return a * s
		end)

        --[[
            collision detection
            using velocity vector as virtually a point on space, we compare
            if last velocity has a great distance difference (virtually 5) from current velocity
            using some trigonometry (get_hipotenuse_value). If yes, we have an abrupt collision
        ]]--
        if self.driver_name then
            local impact = get_hipotenuse_value(vel, self.last_vel)
            if impact > 5 then
                --self.damage = self.damage + impact --sum the impact value directly to damage meter
                local curr_pos = self.object:get_pos()
                minetest.sound_play("collision", {
                    to_player = self.driver_name,
	                --pos = curr_pos,
	                --max_hear_distance = 5,
	                gain = 1.0,
                    fade = 0.0,
                    pitch = 1.0,
                })
                --[[if self.damage > 100 then --if acumulated damage is greater than 100, adieu
                    if self.pointer then self.pointer:remove() end
		            self.object:remove()    
                end]]--
            end
        end
        self.last_vel = vel --saves velocity for collision comparation
        -- end collision detection

		self.object:set_velocity(vel)
	end,

	on_punch = function(self, puncher)
		if not puncher or not puncher:is_player() then
			return
		end
		local name = puncher:get_player_name()
        if self.owner and self.owner ~= name and self.owner ~= "" then return end
        if self.owner == nil then
            self.owner = name
        end
        	
        if self.driver_name and self.driver_name ~= name then
			-- do not allow other players to remove the object while there is a driver
			return
		end

        local touching_ground, liquid_below = check_node_below(self.object)
        
        if self.driver_name and self.driver_name == name and touching_ground then
            --refuel
            load_fuel(self, puncher:get_player_name())
        end

        if self.driver_name == nil and self.owner == name then
            --remove only when the pilot is not attached to the helicopter
		    if self.sound_handle then
			    minetest.sound_stop(self.sound_handle)
			    self.sound_handle = nil
		    end
		    if self.driver_name then
			    -- detach the driver first (puncher must be driver)
			    puncher:set_detach()
			    puncher:set_eye_offset({x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
			    player_api.player_attached[name] = nil
			    -- player should stand again
			    player_api.set_animation(puncher, "stand")
			    self.driver_name = nil
		    end

            if self.pointer then self.pointer:remove() end
		    self.object:remove()

		    minetest.handle_node_drops(self.object:get_pos(), {"helicopter:heli"}, puncher)
            --[[local inv = puncher:get_inventory()
            if inv then
	            for _, item in ipairs({"helicopter:heli"}) do
                    local itemstack = inv:add_item("main", item)
                    local imeta = itemstack:get_meta()
                    imeta:set_int("damage", self.damage)
                    imeta:set_int("energy", self.energy)
	            end
            end]]--

        end
        
	end,

	on_rightclick = function(self, clicker)
		if not clicker or not clicker:is_player() then
			return
		end

		local name = clicker:get_player_name()
        if self.owner and self.owner ~= name and self.owner ~= "" then return end
        if self.owner == "" then
            self.owner = name
        end

		if name == self.driver_name then
			-- driver clicked the object => driver gets off the vehicle
			self.driver_name = nil
			-- sound and animation
			minetest.sound_stop(self.sound_handle)
			self.sound_handle = nil
			self.object:set_animation_frame_speed(0)
			-- detach the player
			clicker:set_detach()
			clicker:set_eye_offset({x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
			player_api.player_attached[name] = nil
			-- player should stand again
			player_api.set_animation(clicker, "stand")
			-- gravity
			self.object:set_acceleration(vector.multiply(vector_up, -gravity))

            --remove hud
            remove_heli_hud(clicker)
        
		elseif not self.driver_name then
            local is_under_water = check_is_under_water(self.object)
            if is_under_water then return end

	        -- no driver => clicker is new driver
	        self.driver_name = name
	        -- sound and animation
	        self.sound_handle = minetest.sound_play({name = "helicopter_motor"},
			        {object = self.object, gain = 2.0, max_hear_distance = 32, loop = true,})
	        self.object:set_animation_frame_speed(30)
	        -- attach the driver
	        clicker:set_attach(self.object, "", {x = 0, y = 10.5, z = 2}, {x = 0, y = 0, z = 0})
	        clicker:set_eye_offset({x = 0, y = 7, z = 3}, {x = 0, y = 8, z = -5})
	        player_api.player_attached[name] = true
	        -- make the driver sit
	        minetest.after(0.2, function()
		        local player = minetest.get_player_by_name(name)
		        if player then
			        player_api.set_animation(player, "sit")
		        end
	        end)
	        -- disable gravity
	        self.object:set_acceleration(vector.new())

		end
	end,
})

--
-- items
--

-- blades
minetest.register_craftitem("helicopter:blades",{
	description = "Helicopter Blades",
	inventory_image = "helicopter_blades_inv.png",
})
-- cabin
minetest.register_craftitem("helicopter:cabin",{
	description = "Cabin for Helicopter",
	inventory_image = "helicopter_cabin_inv.png",
})
-- heli
minetest.register_craftitem("helicopter:heli", {
	description = "Helicopter",
	inventory_image = "helicopter_heli_inv.png",

	on_place = function(itemstack, placer, pointed_thing)
		if pointed_thing.type ~= "node" then
			return
		end
		if minetest.get_node(pointed_thing.above).name ~= "air" then
			return
		end
       
        local obj = minetest.add_entity(pointed_thing.above, "helicopter:heli")
        --[[local ent = obj:get_luaentity()
        local imeta = itemstack:get_meta()
        local owner = placer:get_player_name()
        ent.owner = owner
        ent.energy = imeta:get_int("energy")
        ent.damage = imeta:get_int("damage")]]--

		if not (creative_exists and placer and
				creative.is_enabled_for(placer:get_player_name())) then
			itemstack:take_item()
		end
		return itemstack
	end,
})

--
-- crafting
--

if minetest.get_modpath("default") then
	minetest.register_craft({
		output = "helicopter:blades",
		recipe = {
			{"",                    "default:steel_ingot", ""},
			{"default:steel_ingot", "default:diamond",         "default:steel_ingot"},
			{"",                    "default:steel_ingot", ""},
		}
	})
	minetest.register_craft({
		output = "helicopter:cabin",
		recipe = {
			{"default:copperblock ", "default:diamondblock", ""},
			{"default:steelblock", "default:mese_block", "default:glass"},
			{"default:steelblock", "xpanes:bar_flat", "xpanes:bar_flat"},
		}
	})
	minetest.register_craft({
		output = "helicopter:heli",
		recipe = {
			{"",                  "helicopter:blades"},
			{"helicopter:blades", "helicopter:cabin"},
		}
	})
end


