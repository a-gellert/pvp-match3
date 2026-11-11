-- Enemy AI: evaluates legal board swaps without peeking future spawns (pure Lua).
local board = require "main.modules.board"

local M = {}

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
	for _, grp in ipairs(groups) do
		local n = #grp.cells
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
	local best, best_s = moves[1], -999
	for _, m in ipairs(moves) do
		local s = score_swap(b, m, enemy, difficulty) + rng_inst:float() * (difficulty == 2 and 8 or 2)
		if s > best_s then
			best_s = s
			best = m
		end
	end
	return best
end

return M
