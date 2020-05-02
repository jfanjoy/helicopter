--global constants

gravity = tonumber(minetest.settings:get("movement_gravity")) or 9.8
tilting_speed = 1
tilting_max = 0.35
power_max = 15
power_min = 0.2 -- if negative, the helicopter can actively fly downwards
wanted_vert_speed = 10

vector_up = vector.new(0, 1, 0)
vector_forward = vector.new(0, 0, 1)

function vector_length_sq(v)
	return v.x * v.x + v.y * v.y + v.z * v.z
end

function get_pointer_angle(energy)
    local angle = energy * 18
    angle = angle - 90
    angle = angle * -1
	return angle
end

if not minetest.global_exists("matrix3") then
	dofile(minetest.get_modpath("helicopter") .. DIR_DELIM .. "matrix.lua")
end

function check_node_below(obj)
	local pos_below = obj:get_pos()
	pos_below.y = pos_below.y - 0.1
	local node_below = minetest.get_node(pos_below).name
	local nodedef = minetest.registered_nodes[node_below]
	local touching_ground = not nodedef or -- unknown nodes are solid
			nodedef.walkable or false
	local liquid_below = not touching_ground and nodedef.liquidtype ~= "none"
	return touching_ground, liquid_below
end

function heli_control(self, dtime, touching_ground, liquid_below, vel_before)
	local driver = minetest.get_player_by_name(self.driver_name)
	if not driver then
		-- there is no driver (eg. because driver left)
		self.driver_name = nil
		if self.sound_handle then
			minetest.sound_stop(self.sound_handle)
			self.sound_handle = nil
		end
		self.object:set_animation_frame_speed(0)
		-- gravity
		self.object:set_acceleration(vector.multiply(vector_up, -gravity))
		return
	end
    
	local ctrl = driver:get_player_control()
	local rot = self.object:get_rotation()

	local vert_vel_goal = 0
	if not liquid_below then
		if ctrl.jump then
			vert_vel_goal = vert_vel_goal + wanted_vert_speed
		end
		if ctrl.sneak then
			vert_vel_goal = vert_vel_goal - wanted_vert_speed
		end
	else
		vert_vel_goal = wanted_vert_speed
	end

	-- rotation
	if not touching_ground then
		local tilting_goal = vector.new()
		if ctrl.up then
			tilting_goal.z = tilting_goal.z + 1
		end
		if ctrl.down then
			tilting_goal.z = tilting_goal.z - 1
		end
		if ctrl.right then
			tilting_goal.x = tilting_goal.x + 1
		end
		if ctrl.left then
			tilting_goal.x = tilting_goal.x - 1
		end
		tilting_goal = vector.multiply(vector.normalize(tilting_goal), tilting_max)

		-- tilting
		if vector_length_sq(vector.subtract(tilting_goal, self.tilting)) > (dtime * tilting_speed)^2 then
			self.tilting = vector.add(self.tilting,
					vector.multiply(vector.direction(self.tilting, tilting_goal), dtime * tilting_speed))
		else
			self.tilting = tilting_goal
		end
		if vector_length_sq(self.tilting) > tilting_max^2 then
			self.tilting = vector.multiply(vector.normalize(self.tilting), tilting_max)
		end
		local new_up = vector.new(self.tilting)
		new_up.y = 1
		new_up = vector.normalize(new_up) -- this is what vector_up should be after the rotation
		local new_right = vector.cross(new_up, vector_forward)
		local new_forward = vector.cross(new_right, new_up)
		local rot_mat = matrix3.new(
			new_right.x, new_up.x, new_forward.x,
			new_right.y, new_up.y, new_forward.y,
			new_right.z, new_up.z, new_forward.z
		)
		rot = matrix3.to_pitch_yaw_roll(rot_mat)

		rot.y = driver:get_look_horizontal()

	else
		rot.x = 0
		rot.z = 0
		self.tilting.x = 0
		self.tilting.z = 0
	end

	self.object:set_rotation(rot)

	-- calculate how strong the heli should accelerate towards rotated up
	local power = vert_vel_goal - vel_before.y + gravity * dtime
	power = math.min(math.max(power, power_min * dtime), power_max * dtime)

    -- calculate energy consumption --
    ----------------------------------
    if self.energy > 0 and touching_ground == false then
        local position = self.object:get_pos()
        local altitude_consumption_variable = 0

        -- if gaining altitude, it consumes more power
        local y_pos_reference = position.y - 200 --after altitude 200 the power need will increase
        if y_pos_reference > 0 then altitude_consumption_variable = ((y_pos_reference/1000)^2) end

        local consumed_power = (power/1800) + altitude_consumption_variable
        self.energy = self.energy - consumed_power;

        local energy_indicator_angle = get_pointer_angle(self.energy)
        if self.pointer:get_luaentity() then
            self.pointer:set_attach(self.object,'',{x=0,y=11.26,z=9.37},{x=0,y=0,z=energy_indicator_angle})
        else
            --in case it have lost the entity by some conflict
            self.pointer=minetest.add_entity({x=0,y=11.26,z=9.37},'helicopter:pointer')
            self.pointer:set_attach(self.object,'',{x=0,y=11.26,z=9.37},{x=0,y=0,z=energy_indicator_angle})
        end
    end
    if self.energy <= 0 then
        power = 0.2
		if touching_ground or liquid_below then
            --criar uma fucao pra isso pois ela repete na linha 268
			-- sound and animation
			minetest.sound_stop(self.sound_handle)
			self.object:set_animation_frame_speed(0)
			-- gravity
			self.object:set_acceleration(vector.multiply(vector_up, -gravity))
		end
    end
    ----------------------------
    -- end energy consumption --


	local rotated_up = matrix3.multiply(matrix3.from_pitch_yaw_roll(rot), vector_up)
	local added_vel = vector.multiply(rotated_up, power)
	added_vel = vector.add(added_vel, vector.multiply(vector_up, -gravity * dtime))
	return vector.add(vel_before, added_vel)
end

