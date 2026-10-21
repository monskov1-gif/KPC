class_name ChallengeRewardService
extends RefCounted
## Фиксация результатов испытаний и выдача наград без дублирования.
## Первое прохождение и награды за ранги выдаются один раз; повторный проход — награда repeat.

signal result_recorded(challenge_id: String, report: Dictionary)

var config: WardrobeConfig
var grants: ItemGrantService
var crafting: CraftingService
var _results: Dictionary = {}   # challenge_id -> {best_score, best_rank, cleared, claimed_ranks, attempts}


func _init(p_config: WardrobeConfig, p_grants: ItemGrantService, p_crafting: CraftingService) -> void:
	config = p_config
	grants = p_grants
	crafting = p_crafting


func result(challenge_id: String) -> Dictionary:
	return _results.get(challenge_id, {}).duplicate(true)


## Возвращает {rewards: [выданные награды], new_best, first_clear}.
func submit(challenge: Dictionary, report: Dictionary) -> Dictionary:
	var id: String = challenge.id
	var rec: Dictionary = _results.get(id, {"best_score": 0, "best_rank": "", "cleared": false,
		"claimed_ranks": [], "attempts": 0})
	var rank: String = report.rank
	var rank_i := config.rank_index(rank)
	var table: Dictionary = challenge.get("reward_table", {})
	var to_grant: Array = []
	var first_clear := false

	var min_clear := config.rank_index(str(challenge.get("min_clear_rank", config.rank_order[0])))
	var was_cleared: bool = rec.cleared
	if not was_cleared and rank_i >= min_clear:
		first_clear = true
		to_grant.append_array(table.get("first_clear", []))

	var rank_rewards: Dictionary = table.get("rank_rewards", {})
	var newly_claimed: Array = []
	for r in config.rank_order:
		if config.rank_index(r) <= rank_i and rank_rewards.has(r) and not (rec.claimed_ranks as Array).has(r):
			to_grant.append_array(rank_rewards[r])
			newly_claimed.append(r)

	if was_cleared and newly_claimed.is_empty() and challenge.get("repeatable", false) and rank_i >= min_clear:
		to_grant.append_array(table.get("repeat", []))

	# Фиксация результата и выдача выполняются вместе: сначала обновляем запись, затем выдаём.
	var new_best: bool = int(report.final_score) > int(rec.best_score) or rec.attempts == 0
	rec.attempts = int(rec.attempts) + 1
	if new_best:
		rec.best_score = int(report.final_score)
	if config.rank_index(rank) > config.rank_index(str(rec.best_rank)):
		rec.best_rank = rank
	if first_clear:
		rec.cleared = true
	(rec.claimed_ranks as Array).append_array(newly_claimed)
	_results[id] = rec

	var granted: Array = []
	for reward in to_grant:
		granted.append(_grant(reward))
	result_recorded.emit(id, report)
	return {"rewards": granted, "new_best": new_best, "first_clear": first_clear}


func _grant(reward: Dictionary) -> Dictionary:
	match str(reward.get("type", "")):
		"item":
			return {"reward": reward, "result": grants.grant_item(str(reward.id), "challenge")}
		"resource":
			var err := grants.resources.apply_deltas({str(reward.id): int(reward.get("amount", 1))})
			return {"reward": reward, "result": {"status": "added" if err == "" else "error", "error_key": err}}
		"recipe":
			var added := crafting.unlock(str(reward.id))
			return {"reward": reward, "result": {"status": "added" if added else "duplicate_ignored"}}
	return {"reward": reward, "result": {"status": "error", "error_key": "reward.unknown_type"}}


func to_dict() -> Dictionary:
	return _results.duplicate(true)


func load_dict(d: Dictionary) -> void:
	_results = d.duplicate(true)
