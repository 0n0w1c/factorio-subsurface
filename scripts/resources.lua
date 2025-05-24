resources = {}
for proto, _ in pairs(prototypes.get_entity_filtered({{filter = "type", type = "resource"}, {mode = "and", filter = "autoplace"}})) do
	table.insert(resources, proto)
end

function calculate_resources(surface, pos_arr)
	local properties = {"subsurface_random"}
	for proto, _ in pairs((surface.map_gen_settings.autoplace_settings.entity or {settings = {}}).settings or {}) do
		if (prototypes.entity[proto] or {}).type == "resource" then
			table.insert(properties, "entity:" .. proto .. ":richness")
			table.insert(properties, "entity:" .. proto .. ":probability")
			if prototypes.named_noise_expression[proto .. "-probability"] then table.insert(properties, proto .. "-probability") end
		end
	end
	
	local stored_results = {}
	local result = {}

	for i, pos in ipairs(pos_arr) do
		local chunk_id = spiral({math.floor(pos[1] / 32), math.floor(pos[2] / 32)})
		local pos_i = get_position_index_in_chunk(pos)
		if not stored_results[chunk_id] then stored_results[chunk_id] = surface.calculate_tile_properties(properties, get_chunk_positions(pos)) end
		for _, proto in ipairs(resources) do
			if (stored_results[chunk_id]["entity:"..proto..":richness"] or {[pos_i] = 0})[pos_i] > 0
			and (stored_results[chunk_id][proto.."-probability"] or stored_results[chunk_id]["subsurface_random"])[pos_i] <= stored_results[chunk_id]["entity:"..proto..":probability"][pos_i] then
				if not result[i] then result[i] = {proto, math.ceil(stored_results[chunk_id]["entity:"..proto..":richness"][pos_i])} end
			end
		end
	end
	return result
end

function place_resources(surface, pos_arr)
	local resources = calculate_resources(surface, pos_arr)
	for i, v in pairs(resources) do
		local proto = v[1]
		local pos = pos_arr[i]
		local amount = v[2]
		local collision_box_vector = {x = prototypes.entity[proto].tile_width, y = prototypes.entity[proto].tile_height}
		if surface.count_tiles_filtered{name = "out-of-map", area = math2d.bounding_box.create_from_centre({pos[1] + 0.5 * (collision_box_vector.x % 2), pos[2] + 0.5 * (collision_box_vector.y % 2)}, collision_box_vector.x, collision_box_vector.y)} > 0 then
			clear_subsurface(surface, pos, math2d.vector.length(collision_box_vector) / 2)
		end
		if not surface.entity_prototype_collides(proto, {pos[1] + 0.5 * (collision_box_vector.x % 2), pos[2] + 0.5 * (collision_box_vector.y % 2)}, false) then -- check for other collision than out-of-map tiles (already placed resources)
			if storage.revealed_resources[chunk_id] and storage.revealed_resources[chunk_id][pos_i] and storage.revealed_resources[chunk_id][pos_i][proto] then
				amount = storage.revealed_resources[chunk_id][pos_i][proto]
			end
			if amount > 0 then surface.create_entity{name = proto, position = pos, force = game.forces.neutral, enable_cliff_removal = false, amount = amount} end
		end
	end
end

function size_formula(level)
	return 2 - 2 / (1 + 2 ^ (-0.8 * level))
end
function richness_formula(level)
	return (math.log(level + 1) / math.log(2)) + 0.1
end

local meta = {
	__index = function(self, key) return {size = 0, frequency = 0, richness = 0} end,
	__newindex = function(self, key, value)
		if prototypes.autoplace_control[key] then rawset(self, key, value) end
	end,
}

-- This is for top surfaces. It directly manipulates the map_gen_settings table
-- It is either called upon game start, mod installation or newly created surfaces which aren't subsurfaces
function manipulate_autoplace_controls(surface)
	if settings.global["disable-autoplace-manipulation"].value then return end
	local mgs = surface.map_gen_settings
	if not mgs or not mgs.autoplace_controls then return end
	setmetatable(mgs.autoplace_controls, meta)
	
	-- first, adjust autoplace controls
	for control_name, data in pairs(mgs.autoplace_controls) do
		if prototypes.autoplace_control[control_name].category == "resource" then
			mgs.autoplace_controls[control_name].size = data.size * size_formula(0)
			mgs.autoplace_controls[control_name].richness = data.richness * richness_formula(0)
		end
	end
	
	-- second, adjust all existing resources (only if the mod was added to an existing game)
	for _, res in ipairs(surface.find_entities_filtered{type = "resource"}) do
		res.amount = math.ceil(res.amount * richness_formula(0))
	end
	
	surface.map_gen_settings = mgs
end

function copy_resource_data(mgs, from_surface, depth)
	if settings.global["disable-autoplace-manipulation"].value then return end

	for control_name, data in pairs(from_surface.map_gen_settings.autoplace_controls or {}) do
		if prototypes.autoplace_control[control_name].category == "resource" then
			mgs.autoplace_controls[control_name] = {
				frequency = data.frequency,
				size = data.size * size_formula(depth) / size_formula(0),
				richness = data.richness * richness_formula(depth) / richness_formula(0)
			}
		end
	end
	
	for name, _ in pairs((from_surface.map_gen_settings.autoplace_settings.entity or {settings = {}}).settings) do
		if (prototypes.entity[name] or {}).type == "resource" then
			mgs.autoplace_settings.entity.settings[name] = {}
			if from_surface.map_gen_settings.property_expression_names["entity:"..name..":richness"] then
				mgs.property_expression_names["entity:"..name..":richness"] = from_surface.map_gen_settings.property_expression_names["entity:"..name..":richness"]
			end
			if from_surface.map_gen_settings.property_expression_names["entity:"..name..":probability"] then
				mgs.property_expression_names["entity:"..name..":probability"] = from_surface.map_gen_settings.property_expression_names["entity:"..name..":probability"]
			end
		end
	end
	mgs.autoplace_settings.entity.settings["stone"] = nil
	mgs.property_expression_names["entity:stone:richness"] = nil
	mgs.property_expression_names["entity:stone:probability"] = nil
end

-- When top surfaces are created (this is not called for nauvis)
script.on_event(defines.events.on_surface_created, function(event)
	if not is_subsurface(event.surface_index) then
		manipulate_autoplace_controls(game.get_surface(event.surface_index))
	end
end)

function prospect_resources(prospector)
	local surface = prospector.surface
	local pos_arr = get_area_positions(get_area(prospector.position, 34))
	local resources = calculate_resources(surface, pos_arr)
	for i, v in pairs(resources) do
		local x = pos_arr[i][1]
		local y = pos_arr[i][2]
		if surface.get_tile(x, y).valid and surface.get_tile(x, y).name == "out-of-map"and (x - prospector.position.x)^2 + (y - prospector.position.y)^2 < 32^2 then
			local proto = v[1]
			rendering.draw_sprite{sprite = "entity/" .. proto, target = pos_arr[i], tint = {0.5, 0.5, 0.5, 0.1}, surface = surface, time_to_live = 1200, forces = prospector.force}
		end
	end
end
