function is_item_elevator(name)
	return string.sub(name, 1, 13) == "item-elevator"
end

function get_elevator_names()
	local tbl = {"fluid-elevator-input", "heat-elevator"}
	local i = 1
	while prototypes.entity["item-elevator-"..i] do
		table.insert(tbl, "item-elevator-"..i)
		i = i + 1
	end
	return tbl
end

function switch_elevator(entity) -- switch between input and output
	if is_item_elevator(entity.name) or (entity.name == "entity-ghost" and is_item_elevator(entity.ghost_name)) then
		if entity.linked_belt_type == "input" then
			entity.linked_belt_type = "output"
		else
			entity.linked_belt_type = "input"
		end
		return
	end
	
	local new_name = "fluid-elevator-input"
	if entity.name == "fluid-elevator-input" then new_name = "fluid-elevator-output" end
	
	-- we need to destroy the old entity first because otherwise the new one won't connect to pipes
	local surface = entity.surface
	local pos = entity.position
	local direction = entity.direction
	local force = entity.force
	local last_user = entity.last_user
	local fluidbox = entity.fluidbox[1]
	local inv = false
	entity.destroy()
	
	local new_endpoint = surface.create_entity{name = new_name, position = pos, direction = direction, force = force, player = last_user}
	new_endpoint.fluidbox[1] = fluidbox
	
	return new_endpoint
end

function is_linked(entity)
	if is_item_elevator(entity.name) then
		return entity.linked_belt_neighbour ~= nil
	elseif entity.name == "heat-elevator" then
		for i,v in ipairs(storage.heat_elevators) do
			if v[1] == entity or v[2] == entity then return true end
		end
	else
		for i,v in ipairs(storage.fluid_elevators) do
			if v[1] == entity or v[2] == entity then return true end
		end
	end
	return false
end

function handle_elevators(tick)
	
	-- fluid elevators
	for i,elevators in ipairs(storage.fluid_elevators) do
		if not(elevators[1].valid and elevators[2].valid) then -- remove link and change output to input
			if elevators[2].valid then switch_elevator(elevators[2]) end
			table.remove(storage.fluid_elevators, i)
		end
	end
	
	-- heat elevators
	if tick % 30 == 0 then
		for i,elevators in ipairs(storage.heat_elevators) do  -- average heat between input and output
			if not(elevators[1].valid and elevators[2].valid) then table.remove(storage.heat_elevators, i)
			else
				
				local t1 = elevators[1].temperature
				local t2 = elevators[2].temperature
				if math.abs(t1 - t2) > 5 then -- difference need to be greater that 5 degree, which is equivalent to 5 heat pipes between them
					local transfer = math.min(math.abs(t1 - t2) - 5, 100) -- max transfer is 100°C (1GW is 500MJ per 0.5s)
					if t1 > t2 then
						elevators[1].temperature = t1 - transfer
						elevators[2].temperature = t2 + transfer
					else
						elevators[1].temperature = t1 + transfer
						elevators[2].temperature = t2 - transfer
					end
				end
			end
		end
	end
end

function show_placement_indicators(player, elevator_name)
	if get_oversurface(player.surface) then
		for _,e in ipairs(get_oversurface(player.surface).find_entities_filtered{name = get_elevator_names()}) do
			if not is_linked(e) then
				storage.placement_indicators[player.index] = storage.placement_indicators[player.index] or {}
				if elevator_name == "item-elevator" then table.insert(storage.placement_indicators[player.index], rendering.draw_sprite{sprite = "placement-indicator-3", surface = player.surface, x_scale = 0.3, y_scale = 0.3, target = e.position, players={player}})
				elseif elevator_name == "fluid-elevator" then table.insert(storage.placement_indicators[player.index], rendering.draw_sprite{sprite = "placement-indicator-4", surface = player.surface, x_scale = 0.3, y_scale = 0.3, target = e.position, players={player}})
				else table.insert(storage.placement_indicators[player.index], rendering.draw_sprite{sprite = "placement-indicator-6", surface = player.surface, x_scale = 0.3, y_scale = 0.3, target = e.position, players={player}}) end
			end
		end
	end
	for _,e in ipairs(get_subsurface(player.surface).find_entities_filtered{name = get_elevator_names()}) do
		if not is_linked(e) then
			storage.placement_indicators[player.index] = storage.placement_indicators[player.index] or {}
			if elevator_name == "item-elevator" then table.insert(storage.placement_indicators[player.index], rendering.draw_sprite{sprite = "placement-indicator-1", surface = player.surface, x_scale = 0.3, y_scale = 0.3, target = e.position, players={player}})
			elseif elevator_name == "fluid-elevator" then table.insert(storage.placement_indicators[player.index], rendering.draw_sprite{sprite = "placement-indicator-2", surface = player.surface, x_scale = 0.3, y_scale = 0.3, target = e.position, players={player}})
			else table.insert(storage.placement_indicators[player.index], rendering.draw_sprite{sprite = "placement-indicator-5", surface = player.surface, x_scale = 0.3, y_scale = 0.3, target = e.position, players={player}}) end
		end
	end
end

function elevator_on_cursor_stack_changed(player)
	if player.cursor_stack and player.cursor_stack.valid_for_read then
		if player.cursor_stack.name == "fluid-elevator" then show_placement_indicators(player, "fluid-elevator")
		elseif is_item_elevator(player.cursor_stack.name) then show_placement_indicators(player, "item-elevator")
		elseif player.cursor_stack.name == "heat-elevator" then show_placement_indicators(player, "heat-elevator")
		elseif player.is_cursor_blueprint() and (player.cursor_record or player.cursor_stack).get_blueprint_entities() then
			local item = false
			local fluid = false
			local heat = false
			for _,e in ipairs((player.cursor_record or player.cursor_stack).get_blueprint_entities()) do
				if e.name == "fluid-elevator-input" then fluid = true
				elseif is_item_elevator(e.name) then item = true
				elseif e.name == "heat-elevator" then heat = true end
			end
			if fluid then show_placement_indicators(player, "fluid-elevator") end
			if item then show_placement_indicators(player, "item-elevator") end
			if heat then show_placement_indicators(player, "heat-elevator") end
		end
	end
end

function elevator_rotated(entity, previous_direction)
	if entity.name == "fluid-elevator-input" or entity.name == "fluid-elevator-output" then
		for i,v in ipairs(storage.fluid_elevators) do
			if v[1] == entity or v[2] == entity then
				entity.direction = previous_direction
				storage.fluid_elevators[i] = {switch_elevator(v[2]), switch_elevator(v[1])}
				storage.fluid_elevators[i][1].fluidbox.add_linked_connection(1, storage.fluid_elevators[i][2], 1)
			end
		end
	elseif (is_item_elevator(entity.name) or (entity.name == "entity-ghost" and is_item_elevator(entity.ghost_name))) and entity.linked_belt_neighbour then
		local neighbour = entity.linked_belt_neighbour
		entity.disconnect_linked_belts()
		switch_elevator(entity)
		switch_elevator(neighbour)
		entity.connect_linked_belts(neighbour)
		entity.rotate{reverse = true}
	end
end

function elevator_built(entity, tags)
	local iter = {get_oversurface(entity.surface), get_subsurface(entity.surface)}
	for i=1,2,1 do
		if iter[i] then
			local e = iter[i].find_entities_filtered{name = get_elevator_names(), position = entity.position}[1]
			if e and not is_linked(e) then
				if entity.name == "fluid-elevator-input" then
					local inp = e
					local out = entity
					if tags and tags.type == 1 then -- the built one has to be input, so switch the other one
						inp = entity
						out = switch_elevator(e)
					else
						out = switch_elevator(entity)
					end
					table.insert(storage.fluid_elevators, {inp, out})
					inp.fluidbox.add_linked_connection(1, out, 1)
				elseif entity.name == "heat-elevator" then
					local top,bottom = entity,e
					if i == 1 then
						top = e
						bottom = entity
					end
					table.insert(storage.heat_elevators, {top, bottom})
				else
					if not entity.linked_belt_neighbour then
						if e.linked_belt_type == "input" then entity.linked_belt_type = "output" end
						entity.connect_linked_belts(e)
					end
				end
				break
			end
		end
	end
end

function elevator_selected(player, entity)
	storage.selection_indicators[player.index] = storage.selection_indicators[player.index] or {}
	local offs = 0 -- line offset, when 0 then don't show indicators
	local orien = 0 -- arrow orientation (0 is arrow pointing north)
	if is_item_elevator(entity.name) and entity.linked_belt_neighbour and is_item_elevator(entity.linked_belt_neighbour.name) then
		if entity.linked_belt_neighbour.surface == get_subsurface(entity.surface) then -- selected entity is top
			offs = -0.3
			if entity.linked_belt_type == "input" then orien = 0.5 end
		else offs = 0.3
			if entity.linked_belt_type == "output" then orien = 0.5 end
		end
	elseif entity.name == "fluid-elevator-input" or entity.name == "fluid-elevator-output" then
		for i,v in ipairs(storage.fluid_elevators) do
			if v[1] == entity then
				if get_subsurface(v[1].surface) == v[2].surface then -- selected entity is input and on top surface
					offs = -0.3
					orien = 0.5
				else -- selected entity is input and on bottom surface
					offs = 0.3
				end
			elseif v[2] == entity then
				if get_subsurface(v[2].surface) == v[1].surface then -- selected entity is output and on top surface
					offs = -0.3
				else -- selected entity is output and on bottom surface
					offs = 0.3
					orien = 0.5
				end
			end
		end
	elseif entity.name == "heat-elevator" then
		for i,v in ipairs(storage.heat_elevators) do
			if v[1] == entity then -- selected entity is on top surface
				table.insert(storage.selection_indicators[player.index], rendering.draw_sprite{sprite = "utility/indication_arrow", surface = entity.surface, target = entity, orientation = 0.5, players={player}})
			elseif v[2] == entity then
				table.insert(storage.selection_indicators[player.index], rendering.draw_sprite{sprite = "utility/indication_arrow", surface = entity.surface, target = entity, orientation = 0, players={player}})
			end
		end
	end
	if offs ~= 0 then
		table.insert(storage.selection_indicators[player.index], rendering.draw_sprite{sprite = "utility/indication_line", surface = entity.surface, target = {entity = entity, offset = {0, offs}}, players = {player}})
		table.insert(storage.selection_indicators[player.index], rendering.draw_sprite{sprite = "utility/indication_arrow", surface = entity.surface, target = entity, orientation = orien, players = {player}})
	end
end
