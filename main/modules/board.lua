-- Pure Lua 7x7 Match-3 board engine (special gems, cascades, shuffle).
local config = require "main.modules.config"

local M = {}
local N = config.GRID
local COLORS = config.COLORS

local function key(r, c)
	return r * 16 + c
end

local function clone_grid(g)
	local out = {}
	for r = 1, N do
		out[r] = {}
		for c = 1, N do
			local cell = g[r][c]
			out[r][c] = cell and {
				color = cell.color,
				special = cell.special,
				hole = cell.hole,
				stone = cell.stone,
				hp = cell.hp,
				ice = cell.ice,
				empowered = cell.empowered,
				curse = cell.curse,
			} or nil
		end
	end
	return out
end

local function is_gem(cell)
	return cell ~= nil and not cell.hole and not cell.stone and cell.color ~= nil
end

local function is_movable(cell)
	return is_gem(cell) and not cell.ice
end

local function random_color(r)
	return COLORS[r:int(1, #COLORS)]
end

-- Find all horizontal & vertical runs >= 3, returning match groups
function M.find_matches(grid)
	local h_runs, v_runs = {}, {}
	for r = 1, N do
		local c = 1
		while c <= N do
			local col = grid[r][c] and grid[r][c].color
			if col and grid[r][c].special ~= "prism" then
				local c2 = c
				while c2 + 1 <= N and grid[r][c2 + 1] and grid[r][c2 + 1].color == col and grid[r][c2 + 1].special ~= "prism" do
					c2 = c2 + 1
				end
				if c2 - c + 1 >= 3 then
					local cells = {}
					for cc = c, c2 do cells[#cells + 1] = { r = r, c = cc } end
					h_runs[#h_runs + 1] = { color = col, dir = "h", cells = cells }
				end
				c = c2 + 1
			else
				c = c + 1
			end
		end
	end
	for c = 1, N do
		local r = 1
		while r <= N do
			local col = grid[r][c] and grid[r][c].color
			if col and grid[r][c].special ~= "prism" then
				local r2 = r
				while r2 + 1 <= N and grid[r2 + 1][c] and grid[r2 + 1][c].color == col and grid[r2 + 1][c].special ~= "prism" do
					r2 = r2 + 1
				end
				if r2 - r + 1 >= 3 then
					local cells = {}
					for rr = r, r2 do cells[#cells + 1] = { r = rr, c = c } end
					v_runs[#v_runs + 1] = { color = col, dir = "v", cells = cells }
				end
				r = r2 + 1
			else
				r = r + 1
			end
		end
	end

	-- Merge intersecting runs of same color into unified groups
	local all = {}
	for _, g in ipairs(h_runs) do all[#all + 1] = g end
	for _, g in ipairs(v_runs) do all[#all + 1] = g end
	if #all == 0 then return {} end

	local used = {}
	local groups = {}
	for i = 1, #all do
		if not used[i] then
			used[i] = true
			local color = all[i].color
			local has_h = all[i].dir == "h"
			local has_v = all[i].dir == "v"
			local map = {}
			local queue = { all[i] }
			for _, p in ipairs(all[i].cells) do map[key(p.r, p.c)] = p end
			local changed = true
			while changed do
				changed = false
				for j = 1, #all do
					if not used[j] and all[j].color == color then
						local overlaps = false
						for _, p in ipairs(all[j].cells) do
							if map[key(p.r, p.c)] then overlaps = true; break end
						end
						if overlaps then
							used[j] = true
							changed = true
							if all[j].dir == "h" then has_h = true else has_v = true end
							for _, p in ipairs(all[j].cells) do map[key(p.r, p.c)] = p end
							queue[#queue + 1] = all[j]
						end
					end
				end
			end
			local cells = {}
			for _, p in pairs(map) do cells[#cells + 1] = p end
			local max_len = 0
			for _, q in ipairs(queue) do if #q.cells > max_len then max_len = #q.cells end end
			local spawn = nil
			if max_len >= 5 then
				spawn = "prism"
			elseif has_h and has_v then
				spawn = "bomb"
			elseif max_len == 4 then
				spawn = has_h and "line_v" or "line_h"
			end
			groups[#groups + 1] = { color = color, cells = cells, spawn = spawn }
		end
	end
	return groups
end

function M.valid_moves(grid)
	local moves = {}
	local dirs = { { 0, 1 }, { 1, 0 } }
	for r = 1, N do
		for c = 1, N do
			for _, d in ipairs(dirs) do
				local nr, nc = r + d[1], c + d[2]
				if nr <= N and nc <= N then
					local a, b = grid[r][c], grid[nr][nc]
					if is_movable(a) and is_movable(b) then
						if a.special == "prism" or b.special == "prism" then
							moves[#moves + 1] = { r1 = r, c1 = c, r2 = nr, c2 = nc }
						elseif a.color ~= b.color then
							grid[r][c], grid[nr][nc] = b, a
							local m = M.find_matches(grid)
							grid[r][c], grid[nr][nc] = a, b
							if #m > 0 then
								moves[#moves + 1] = { r1 = r, c1 = c, r2 = nr, c2 = nc }
							end
						end
					end
				end
			end
		end
	end
	return moves
end

function M.freeze_random(b, rng_inst, count)
	local existing = 0
	local cands = {}
	for r = 1, N do
		for c = 1, N do
			local g = b.grid[r][c]
			if is_gem(g) then
				if g.ice then
					existing = existing + 1
				elseif not g.special and not g.curse then
					cands[#cands + 1] = { r = r, c = c }
				end
			end
		end
	end
	if existing >= 4 or #cands == 0 then return {} end
	(rng_inst or b.rng):shuffle(cands)
	local frozen = {}
	local n = math.min(count or 1, 4 - existing, #cands)
	for _, p in ipairs(cands) do
		if #frozen >= n then break end
		local g = b.grid[p.r][p.c]
		g.ice = true
		if #M.valid_moves(b.grid) >= 2 then
			frozen[#frozen + 1] = { r = p.r, c = p.c }
		else
			g.ice = nil
		end
	end
	return frozen
end

function M.spawn_curse(b, rng_inst)
	local existing = 0
	local cands = {}
	for r = 1, N do
		for c = 1, N do
			local g = b.grid[r][c]
			if is_gem(g) then
				if g.curse then
					existing = existing + 1
				elseif not g.special and not g.ice and not g.empowered then
					cands[#cands + 1] = { r = r, c = c }
				end
			end
		end
	end
	if existing >= 2 or #cands == 0 then return nil end
	local p = (rng_inst or b.rng):pick(cands)
	b.grid[p.r][p.c].curse = 3
	return { r = p.r, c = p.c, turns = 3 }
end

function M.tick_curses(b)
	local exploded, remaining = {}, {}
	for r = 1, N do
		for c = 1, N do
			local g = b.grid[r][c]
			if is_gem(g) and g.curse then
				g.curse = g.curse - 1
				if g.curse <= 0 then
					g.curse = nil
					exploded[#exploded + 1] = { r = r, c = c }
				else
					remaining[#remaining + 1] = { r = r, c = c, turns = g.curse }
				end
			end
		end
	end
	return { exploded = exploded, remaining = remaining }
end

function M.new(rng_inst, cfg)
	local b = { grid = {}, rng = rng_inst, cfg = cfg }
	for r = 1, N do
		b.grid[r] = {}
	end
	if cfg and cfg.holes then
		for _, p in ipairs(cfg.holes) do
			if b.grid[p[1]] then b.grid[p[1]][p[2]] = { hole = true } end
		end
	end
	if cfg and cfg.stones then
		for _, p in ipairs(cfg.stones) do
			if b.grid[p[1]] and not b.grid[p[1]][p[2]] then
				b.grid[p[1]][p[2]] = { stone = true, hp = p[3] or 1 }
			end
		end
	end
	for r = 1, N do
		for c = 1, N do
			if not b.grid[r][c] then
				local col
				for _ = 1, 20 do
					col = random_color(rng_inst)
					local h2 = c >= 3 and b.grid[r][c - 1] and b.grid[r][c - 2] and b.grid[r][c - 1].color == col and b.grid[r][c - 2].color == col
					local v2 = r >= 3 and b.grid[r - 1][c] and b.grid[r - 2][c] and b.grid[r - 1][c].color == col and b.grid[r - 2][c].color == col
					if not h2 and not v2 then break end
				end
				b.grid[r][c] = { color = col }
			end
		end
	end
	if #M.valid_moves(b.grid) == 0 then M.shuffle(b) end

	if cfg then
		if (cfg.empowered or 0) > 0 then
			local cands = {}
			for r = 1, N do for c = 1, N do if is_gem(b.grid[r][c]) then cands[#cands + 1] = b.grid[r][c] end end end
			rng_inst:shuffle(cands)
			for i = 1, math.min(cfg.empowered, #cands) do cands[i].empowered = true end
		end
		if (cfg.curses or 0) > 0 then
			for _ = 1, cfg.curses do M.spawn_curse(b, rng_inst) end
		end
		if (cfg.ice or 0) > 0 then
			M.freeze_random(b, rng_inst, cfg.ice)
		end
	end
	return b
end

function M.shuffle(b)
	for attempt = 1, 24 do
		local pool = {}
		local slots = {}
		for r = 1, N do
			for c = 1, N do
				if is_gem(b.grid[r][c]) then
					pool[#pool + 1] = b.grid[r][c]
					slots[#slots + 1] = { r = r, c = c }
				end
			end
		end
		if attempt >= 16 then
			for _, g in ipairs(pool) do g.ice = nil end
		end
		b.rng:shuffle(pool)
		for idx, p in ipairs(slots) do
			b.grid[p.r][p.c] = pool[idx]
		end
		if #M.find_matches(b.grid) == 0 and #M.valid_moves(b.grid) > 0 then return true end
	end
	-- Guarantee at least one legal swap among movable gem cells
	for r = 1, N do
		for c = 1, N - 2 do
			local r2 = r < N and r + 1 or r - 1
			if is_gem(b.grid[r][c]) and is_gem(b.grid[r][c + 1]) and is_gem(b.grid[r][c + 2]) and is_gem(b.grid[r2][c + 2]) then
				local col = COLORS[1]
				b.grid[r][c].color, b.grid[r][c].ice = col, nil
				b.grid[r][c + 1].color, b.grid[r][c + 1].ice = col, nil
				b.grid[r][c + 2].color, b.grid[r][c + 2].ice = COLORS[2], nil
				b.grid[r2][c + 2].color, b.grid[r2][c + 2].ice = col, nil
				if #M.find_matches(b.grid) == 0 and #M.valid_moves(b.grid) > 0 then return true end
			end
		end
	end
	return true
end

local function expand_specials(grid, initial_map)
	local queue = {}
	for k, v in pairs(initial_map) do queue[#queue + 1] = v end
	local i = 1
	while i <= #queue do
		local cell = queue[i]
		i = i + 1
		local g = grid[cell.r][cell.c]
		if g and g.special then
			local sp = g.special
			if sp == "line_h" then
				for cc = 1, N do
					local k = key(cell.r, cc)
					if not initial_map[k] and grid[cell.r][cc] and not grid[cell.r][cc].hole then
						initial_map[k] = { r = cell.r, c = cc }
						queue[#queue + 1] = initial_map[k]
					end
				end
			elseif sp == "line_v" then
				for rr = 1, N do
					local k = key(rr, cell.c)
					if not initial_map[k] and grid[rr][cell.c] and not grid[rr][cell.c].hole then
						initial_map[k] = { r = rr, c = cell.c }
						queue[#queue + 1] = initial_map[k]
					end
				end
			elseif sp == "bomb" then
				for dr = -1, 1 do
					for dc = -1, 1 do
						local rr, cc = cell.r + dr, cell.c + dc
						if rr >= 1 and rr <= N and cc >= 1 and cc <= N then
							local k = key(rr, cc)
							if not initial_map[k] and grid[rr][cc] and not grid[rr][cc].hole then
								initial_map[k] = { r = rr, c = cc }
								queue[#queue + 1] = initial_map[k]
							end
						end
					end
				end
			end
		end
	end
	return queue
end

local function apply_gravity_and_refill(b)
	local falls = {}
	local spawns = {}
	for c = 1, N do
		local read_r = 1
		for write_r = 1, N do
			local dst = b.grid[write_r][c]
			if not dst then
				if read_r <= write_r then read_r = write_r + 1 end
				while read_r <= N and not is_gem(b.grid[read_r][c]) do
					read_r = read_r + 1
				end
				if read_r <= N then
					b.grid[write_r][c] = b.grid[read_r][c]
					b.grid[read_r][c] = nil
					falls[#falls + 1] = { from_r = read_r, to_r = write_r, c = c }
				end
			end
		end
		for r = 1, N do
			if not b.grid[r][c] then
				local gem = { color = random_color(b.rng) }
				if b.cfg and b.cfg.allow_empowered and b.rng:float() < 0.045 then
					gem.empowered = true
				end
				b.grid[r][c] = gem
				spawns[#spawns + 1] = { r = r, c = c, color = gem.color, empowered = gem.empowered }
			end
		end
	end
	return falls, spawns
end

function M.can_swap(b, r1, c1, r2, c2)
	if math.abs(r1 - r2) + math.abs(c1 - c2) ~= 1 then return false end
	local a, g2 = b.grid[r1] and b.grid[r1][c1], b.grid[r2] and b.grid[r2][c2]
	if not is_movable(a) or not is_movable(g2) then return false end
	if a.special == "prism" or g2.special == "prism" then return true end
	if a.color == g2.color then return false end
	b.grid[r1][c1], b.grid[r2][c2] = g2, a
	local m = M.find_matches(b.grid)
	b.grid[r1][c1], b.grid[r2][c2] = a, g2
	return #m > 0
end

local function run_cascades(b, initial_clear_map, pivot1, pivot2)
	local steps = {}
	local cascade_idx = 0
	local pending_map = initial_clear_map

	while true do
		cascade_idx = cascade_idx + 1
		local clear_list = {}
		local spawned_specs = {}

		if pending_map then
			clear_list = expand_specials(b.grid, pending_map)
			pending_map = nil
		else
			local groups = M.find_matches(b.grid)
			if #groups == 0 then break end
			local map = {}
			for _, grp in ipairs(groups) do
				local spawn_cell = nil
				if grp.spawn and cascade_idx == 1 then
					for _, p in ipairs(grp.cells) do
						if (pivot1 and p.r == pivot1.r and p.c == pivot1.c)
							or (pivot2 and p.r == pivot2.r and p.c == pivot2.c) then
							spawn_cell = p
							break
						end
					end
				end
				if grp.spawn and not spawn_cell then spawn_cell = grp.cells[1] end
				for _, p in ipairs(grp.cells) do
					if spawn_cell and p.r == spawn_cell.r and p.c == spawn_cell.c then
						spawned_specs[#spawned_specs + 1] = {
							r = p.r, c = p.c,
							color = grp.spawn == "prism" and "prism" or grp.color,
							special = grp.spawn,
						}
					else
						map[key(p.r, p.c)] = p
					end
				end
			end
			clear_list = expand_specials(b.grid, map)
		end

		if #clear_list == 0 and #spawned_specs == 0 then break end

		local cleared_info = {}
		local counts = { red = 0, yellow = 0, purple = 0, green = 0, blue = 0 }
		local direct_stone = {}
		local stones_hit, stones_broken, melted, curse_cells, empowered_cells = {}, {}, {}, {}, {}
		local curses_cleared = 0
		for _, p in ipairs(clear_list) do
			local g = b.grid[p.r][p.c]
			if g then
				if g.stone then
					direct_stone[key(p.r, p.c)] = true
					g.hp = (g.hp or 1) - 1
					if g.hp <= 0 then
						b.grid[p.r][p.c] = nil
						stones_broken[#stones_broken + 1] = { r = p.r, c = p.c }
					else
						stones_hit[#stones_hit + 1] = { r = p.r, c = p.c, hp = g.hp }
					end
				elseif is_gem(g) then
					if counts[g.color] then
						counts[g.color] = counts[g.color] + (g.empowered and 2 or 1)
					end
					if g.empowered then
						empowered_cells[#empowered_cells + 1] = { r = p.r, c = p.c, color = g.color }
					end
					if g.curse then
						curses_cleared = curses_cleared + 1
						curse_cells[#curse_cells + 1] = { r = p.r, c = p.c }
					end
					if g.ice then
						melted[#melted + 1] = { r = p.r, c = p.c }
					end
					cleared_info[#cleared_info + 1] = {
						r = p.r, c = p.c, color = g.color, special = g.special,
						empowered = g.empowered, curse = g.curse, ice = g.ice,
					}
					b.grid[p.r][p.c] = nil
				end
			end
		end
		for _, sp in ipairs(spawned_specs) do
			local prev = b.grid[sp.r][sp.c]
			if counts[sp.color] then
				counts[sp.color] = counts[sp.color] + ((prev and prev.empowered) and 2 or 1)
			end
			if prev and prev.empowered then
				empowered_cells[#empowered_cells + 1] = { r = sp.r, c = sp.c, color = sp.color }
			end
			if prev and prev.curse then
				curses_cleared = curses_cleared + 1
				curse_cells[#curse_cells + 1] = { r = sp.r, c = sp.c }
			end
			if prev and prev.ice then
				melted[#melted + 1] = { r = sp.r, c = sp.c }
			end
			b.grid[sp.r][sp.c] = { color = sp.color, special = sp.special }
		end

		-- Adjacent match/special hits crack stones and thaw nearby ice
		local adj_seen = {}
		local dirs = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
		local function check_adj(r0, c0)
			for _, d in ipairs(dirs) do
				local nr, nc = r0 + d[1], c0 + d[2]
				if nr >= 1 and nr <= N and nc >= 1 and nc <= N then
					local k = key(nr, nc)
					if not adj_seen[k] then
						adj_seen[k] = true
						local ng = b.grid[nr][nc]
						if ng and ng.stone and not direct_stone[k] then
							ng.hp = (ng.hp or 1) - 1
							if ng.hp <= 0 then
								b.grid[nr][nc] = nil
								stones_broken[#stones_broken + 1] = { r = nr, c = nc }
							else
								stones_hit[#stones_hit + 1] = { r = nr, c = nc, hp = ng.hp }
							end
						elseif ng and ng.ice then
							ng.ice = nil
							melted[#melted + 1] = { r = nr, c = nc }
						end
					end
				end
			end
		end
		for _, p in ipairs(cleared_info) do check_adj(p.r, p.c) end
		for _, sp in ipairs(spawned_specs) do check_adj(sp.r, sp.c) end

		local falls, spawns = apply_gravity_and_refill(b)
		steps[#steps + 1] = {
			cascade = cascade_idx,
			cleared = cleared_info,
			counts = counts,
			specials = spawned_specs,
			falls = falls,
			spawns = spawns,
			stones_hit = stones_hit,
			stones_broken = stones_broken,
			melted = melted,
			curses_cleared = curses_cleared,
			curse_cells = curse_cells,
			empowered_cells = empowered_cells,
		}
	end

	local shuffled = false
	if #M.valid_moves(b.grid) == 0 then
		M.shuffle(b)
		shuffled = true
	end
	return steps, shuffled
end

function M.resolve_swap(b, r1, c1, r2, c2)
	if not M.can_swap(b, r1, c1, r2, c2) then return nil end
	local a, g2 = b.grid[r1][c1], b.grid[r2][c2]
	b.grid[r1][c1], b.grid[r2][c2] = g2, a

	local prism_map = nil
	if a.special == "prism" or g2.special == "prism" then
		prism_map = {}
		prism_map[key(r1, c1)] = { r = r1, c = c1 }
		prism_map[key(r2, c2)] = { r = r2, c = c2 }
		local target_col = (a.special == "prism" and g2.color) or a.color
		if target_col == "prism" then
			-- Two prisms: clear entire board (excluding holes)
			for r = 1, N do for c = 1, N do if b.grid[r][c] and not b.grid[r][c].hole then prism_map[key(r, c)] = { r = r, c = c } end end end
		else
			for r = 1, N do
				for c = 1, N do
					if b.grid[r][c] and b.grid[r][c].color == target_col then
						prism_map[key(r, c)] = { r = r, c = c }
					end
				end
			end
		end
	end

	return run_cascades(b, prism_map, { r = r1, c = c1 }, { r = r2, c = c2 })
end

function M.use_hammer(b, r, c)
	local g = b.grid[r] and b.grid[r][c]
	if not g or g.hole then return nil end
	if g.stone then g.hp = 1 end
	local map = { [key(r, c)] = { r = r, c = c } }
	return run_cascades(b, map)
end

-- Shallow copy of grid for AI simulation
function M.clone_grid_only(b)
	return { grid = clone_grid(b.grid), rng = b.rng }
end

return M
