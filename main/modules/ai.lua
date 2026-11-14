-- Enemy AI: evaluates legal board moves (swaps in Match-3 or taps in Toon Blast) without peeking future spawns (pure Lua).
local config = require "main.modules.config"
local board = require "main.modules.board"

local M = {}

local function score_blast(b, m, enemy, difficulty)
	local score = 0
	local hp_ratio = enemy.hp / math.max(1, enemy.max_hp)

	if m.special then
		local sp = m.special
		local dirs = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
		local has_adj_spec = false
		for _, d in ipairs(dirs) do
			local nr, nc = m.r + d[1], m.c + d[2]
			if nr >= 1 and nr <= 7 and nc >= 1 and nc <= 7 then
				local ng = b.grid[nr] and b.grid[nr][nc]
				if ng and ng.special then has_adj_spec = true; break end
			end
		end

		if has_adj_spec then
			score = score + (difficulty >= 2 and 110 or 60)
		else
			if sp == "prism" then
				score = score + 70
			elseif sp == "bomb" then
				score = score + 48
			else
				score = score + 36
			end
		end
		return score
	end

	local n = m.size or (m.cells and #m.cells) or 2
	local col = m.color
	local dirs = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }

	if m.cells then
		for _, p in ipairs(m.cells) do
			local c = b.grid[p.r] and b.grid[p.r][p.c]
			if c and c.curse then score = score + 18 end
			if c and c.empowered then score = score + 10 end
			for _, d in ipairs(dirs) do
				local nr, nc = p.r + d[1], p.c + d[2]
				local ng = b.grid[nr] and b.grid[nr][nc]
				if ng and ng.ice then score = score + 6 end
				if ng and ng.stone then score = score + 4 end
			end
		end
	end

	if col == "purple" then
		score = score + n * 16
	elseif col == "yellow" then
		score = score + n * 11
	elseif col == "red" then
		score = score + n * 7
	elseif col == "green" then
		local heal_w = hp_ratio < 0.45 and 24 or (hp_ratio < 0.75 and 12 or 3)
		score = score + n * heal_w
	elseif col == "blue" then
		local sh_w = enemy.shield < enemy.max_shield * 0.35 and 14 or 5
		score = score + n * sh_w
	end

	-- Bonus for creating specials from large clusters
	if n >= 9 then
		score = score + 32
	elseif n >= 7 then
		score = score + 22
	elseif n >= 5 then
		score = score + 14
	end

	if difficulty >= 2 and enemy.squads then
		for _, sq in pairs(enemy.squads) do
			if sq.runes and sq.rune_filled then
				if (not sq.rune_filled[1] and sq.runes[1] == col) or (not sq.rune_filled[2] and sq.runes[2] == col) then
					local ready_now = (sq.rune_filled[1] or sq.rune_filled[2])
					score = score + (ready_now and 26 or 12)
				end
			end
		end
	end

	return score
end

local function score_swap(b, m, enemy, difficulty)
	local sim = board.clone_grid_only(b)
	local a, g2 = sim.grid[m.r1][m.c1], sim.grid[m.r2][m.c2]
	if a.special == "prism" or g2.special == "prism" then
		return difficulty >= 2 and 120 or 30
	end
	sim.grid[m.r1][m.c1], sim.grid[m.r2][m.c2] = g2, a
	local groups = board.find_matches(sim.grid)
	if #groups == 0 then return -1 end

	local score = 0
	local hp_ratio = enemy.hp / math.max(1, enemy.max_hp)
	local dirs = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
	for _, grp in ipairs(groups) do
		local n = #grp.cells
		for _, p in ipairs(grp.cells) do
			local c = sim.grid[p.r][p.c]
			if c and c.curse then score = score + 18 end
			if c and c.empowered then score = score + 10 end
			for _, d in ipairs(dirs) do
				local nr, nc = p.r + d[1], p.c + d[2]
				local ng = sim.grid[nr] and sim.grid[nr][nc]
				if ng and ng.ice then score = score + 6 end
				if ng and ng.stone then score = score + 4 end
			end
		end
		if grp.color == "purple" then
			score = score + n * 16
		elseif grp.color == "yellow" then
			score = score + n * 11
		elseif grp.color == "red" then
			score = score + n * 7
		elseif grp.color == "green" then
			local heal_w = hp_ratio < 0.45 and 22 or (hp_ratio < 0.75 and 11 or 2)
			score = score + n * heal_w
		elseif grp.color == "blue" then
			local sh_w = enemy.shield < enemy.max_shield * 0.35 and 13 or 5
			score = score + n * sh_w
		end
		if grp.spawn and difficulty >= 2 then
			score = score + 18
		end
		if difficulty >= 2 and enemy.squads then
			for _, sq in pairs(enemy.squads) do
				if sq.runes and sq.rune_filled then
					if (not sq.rune_filled[1] and sq.runes[1] == grp.color) or (not sq.rune_filled[2] and sq.runes[2] == grp.color) then
						local ready_now = (sq.rune_filled[1] or sq.rune_filled[2])
						score = score + (ready_now and 24 or 10)
					end
				end
			end
		end
	end
	return score
end

function M.pick_move(b, enemy, difficulty, rng_inst)
	local moves = board.valid_moves(b.grid)
	if #moves == 0 then return nil end
	if difficulty <= 1 and rng_inst:float() < 0.55 then
		return rng_inst:pick(moves)
	end
	local is_blast = config.is_blast_mode()
	local best, best_s = moves[1], -999
	for _, m in ipairs(moves) do
		local s
		if is_blast then
			s = score_blast(b, m, enemy, difficulty) + rng_inst:float() * (difficulty == 2 and 8 or 2)
		else
			s = score_swap(b, m, enemy, difficulty) + rng_inst:float() * (difficulty == 2 and 8 or 2)
		end
		if s > best_s then
			best_s = s
			best = m
		end
	end
	return best
end

return M
