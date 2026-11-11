class_name ModHooks
extends RefCounted
## Resolves the mods a campaign declares into the `RuleHooks` table of a run: the ONE builder, called once by `GameState.begin_run`. The campaign names mod packs by pack id (`Campaign.mods`); each must be a pack of the chain in
## use whose manifest has `rules` and whose mod runs (`ModHost.rule_mod`), and what its manifest lists (`ModSpec.rule_answers`, `rule_instructions`, `rule_sub`) is claimed in the table, the first mod of the list keeping a number or a
## type another also lists. A declared mod that is not there, was refused, has no rule hooks or lost a number to another is recorded in `RuleHooks.unresolved` with the reason (the table has no hook of it) and warned about once (`RuleHooks.trouble`, `[rules]`: the campaign, the mod, the reason, what plays instead), never an error: the
## campaign plays on, with the original's behaviour wherever a hook is missing. A mod of the chain that no campaign declares is never reached: the table holds only what was resolved here. A campaign that declares none, free play and
## every tool get the empty table without asking the mods anything.
##
## It also makes the table's ONE way to a mod, a Callable over `ModLoader.call_mod` (read-only state, the mod's instruction limit, an error or a timeout as a fault, the answer copied). The table holds the mods' nodes it
## resolved: a mod unloaded later is a fault (`call_mod` says it is gone), never a stale call.
##
## Teaches: resolving what a data file names into the object the rules use, once per run, by one builder, and keeping every object the rules must not touch (the nodes, the autoload) on this side of one Callable.


## The table for the run of `campaign` (null: no campaign), resolved from the chain in use.
static func resolve(campaign: Campaign) -> RuleHooks:
	var hooks := RuleHooks.none()
	if campaign == null or campaign.mods.is_empty():
		return hooks
	hooks.campaign_id = campaign.id
	var nodes := {}
	for id in campaign.mods:
		if hooks.declared.has(id):
			continue
		hooks.declared.append(id)
		var notes := _claim(hooks, id, nodes)
		if not notes.is_empty():
			hooks.unresolved[id] = "; ".join(notes)
			hooks.trouble.tell(unresolved_line(campaign.id, id, hooks.unresolved[id], nodes.has(id)))
	hooks.set_caller(func(mod_id: StringName, function: String, state: Dictionary) -> Dictionary: return ModLoader.call_mod(nodes.get(mod_id), function, [state]))
	return hooks


## The warning for a declared mod that did not resolve (`why`: `unresolved[id]`): the campaign, the mod, the reason and what plays instead. `partly`: the mod runs, but lost a number or a type to another mod.
static func unresolved_line(campaign_id: StringName, id: StringName, why: String, partly: bool) -> String:
	var instead := "what the mod would have done at that hook is the original's behaviour (an instruction does nothing, a problem is judged by its own data, the sub has no ability)" if partly \
			else "none of its rule hooks run, so every hook it would have answered has the original's behaviour (a Mod_Instruction faults its creature or does nothing, a problem is judged by its own data, the sub has no ability)"
	return "[rules] campaign '%s' declares the mod '%s', which %s: %s; %s" % [campaign_id, id, "does not run in full" if partly else "does not run", why, instead]


## Claims what the mod `id` lists in `hooks` and puts its node in `nodes`; returns why it could not (all of it, or a number or type that another mod has).
static func _claim(hooks: RuleHooks, id: StringName, nodes: Dictionary) -> Array[String]:
	var notes: Array[String] = []
	var pack := Packs.pack(id)
	if pack == null:
		notes.append("no pack '%s' is in the chain in use" % id)
		return notes
	if pack.mod == null or not pack.mod.has_rules:
		notes.append("pack '%s' is no mod with rule hooks (its manifest has no \"mod\" with \"rules\")" % id)
		return notes
	var node := ModHost.rule_mod(id)
	if node == null:
		var why := ModHost.failure(id)
		notes.append("the mod '%s' is not running%s" % [id, (": " + why) if not why.is_empty() else ""])
		return notes
	nodes[id] = node
	for type_id in pack.mod.rule_answers:
		if not hooks.claim_judge(type_id, id):
			notes.append("problem type %d is judged by another mod" % type_id)
	for number in pack.mod.rule_instructions:
		if not hooks.claim_instruction(number, id):
			notes.append("instruction %d is defined by another mod" % number)
	if pack.mod.rule_sub and not hooks.claim_sub(id):
		notes.append("the sub ability is another mod's")
	return notes

