function place_resources(surface, pos_arr)
	local resources = {}
	local res = {}
	for k,v in pairs(surface.map_gen_settings.autoplace_controls) do
		resources["entity:"..k..":richness"] = k
		table.insert(res, "entity:"..k..":richness")
	end
	
	local calcresult = surface.calculate_tile_properties(res, pos_arr)
	for r,arr in pairs(calcresult) do
		for i,v in ipairs(arr) do
			if v > 0 then
				if #surface.find_entities_filtered{type="resource", position={pos_arr[i][1]+0.5, pos_arr[i][2]+0.5}} == 0 then surface.create_entity{name=resources[r], position=pos_arr[i], force=game.forces.neutral, amount=math.ceil(v)} end
			end
		end
	end
end

-- this is for top surfaces (depth 0). It directly manipulates the surface's map_gen_settings
function manipulate_autoplace_controls(surface)
	local mgs = surface.map_gen_settings
	mgs.default_enable_all_autoplace_controls = false
	
	if surface.name == "nauvis" then
		mgs.autoplace_controls["uranium-ore"] = nil
		mgs.autoplace_controls["stone"].richness = mgs.autoplace_controls["stone"].richness * 0.7
	end
	
	surface.map_gen_settings = mgs
end

-- this is for subsurfaces, it returns a freshly new autoplace_controls array
-- ensure that all resources really exist!
function make_autoplace_controls(topname, depth)
	if topname == "nauvis" then
		return {
			["iron-ore"] = 		{frequency = 1.5*depth, 	size = 1.5*depth, 	richness = 2*depth},
			["copper-ore"] = 	{frequency = 1.5*depth, 	size = 1.5*depth, 	richness = 2*depth},
			["uranium-ore"] = 	{frequency = 1, 			size = 1, 			richness = 1},
			["crude-oil"] = 	{frequency = 1.5*depth, 	size = 1.5*depth, 	richness = 2*depth},
			["coal"] = 			{frequency = 0.8^depth, 	size = 0.5^depth, 	richness = 0.8^depth},
		}
	else return {}
	end
end

-- When top surfaces are created (but not for nauvis!)
script.on_event(defines.events.on_surface_created, function(event)
	if not is_subsurface(event.surface_index) then
		manipulate_autoplace_controls(game.get_surface(event.surface_index))
	end
end)

function prospect_resources(prospector)
	local subsurface = get_subsurface(prospector.surface)
	
	local resources = {}
	local res = {}
	for k,v in pairs(subsurface.map_gen_settings.autoplace_controls) do
		resources["entity:"..k..":richness"] = k
		table.insert(res, "entity:"..k..":richness")
	end
	
	local pos = prospector.position
	local pos_arr = {}
	for x, y in iarea(get_area(pos, 200)) do
		if (x-pos.x)^2 + (y-pos.y)^2 < 40000 then table.insert(pos_arr, {x, y}) end
	end
	
	local calcresult = subsurface.calculate_tile_properties(res, pos_arr)
	for r,arr in pairs(calcresult) do
		for i,v in ipairs(arr) do
			if v > 0 then
				rendering.draw_circle{color={0.5, 0.5, 0.5, 0.1}, target=pos_arr[i], radius=0.3, surface=prospector.surface, time_to_live=36000, forces={prospector.force}, draw_on_ground=true}
			end
		end
	end
end
