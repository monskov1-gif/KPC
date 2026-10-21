class_name Compatibility
extends RefCounted
## Правило совместимости предмета с персонажем — только из данных.

enum Status { COMPATIBLE, ADAPTED, INCOMPATIBLE }

const REASON_EXCLUDED := "compat.excluded"
const REASON_NOT_WHITELISTED := "compat.not_whitelisted"
const REASON_BODY_TYPE := "compat.body_type"


## Возвращает {status, reason_key}.
static func check(item: ClothingItem, character_id: String, characters: CharacterCatalog) -> Dictionary:
	if item.excluded_character_ids.has(character_id):
		return {"status": Status.INCOMPATIBLE, "reason_key": REASON_EXCLUDED}
	if not item.compatible_character_ids.is_empty() and not item.compatible_character_ids.has(character_id):
		return {"status": Status.INCOMPATIBLE, "reason_key": REASON_NOT_WHITELISTED}
	if item.compatible_body_types.has(characters.body_type(character_id)):
		return {"status": Status.COMPATIBLE, "reason_key": ""}
	if item.model_variants.has(character_id):
		return {"status": Status.ADAPTED, "reason_key": ""}
	return {"status": Status.INCOMPATIBLE, "reason_key": REASON_BODY_TYPE}


static func can_wear(item: ClothingItem, character_id: String, characters: CharacterCatalog) -> bool:
	return check(item, character_id, characters).status != Status.INCOMPATIBLE
