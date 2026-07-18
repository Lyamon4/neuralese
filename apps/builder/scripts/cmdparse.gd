extends Node
class_name Commands

class CommandArg:
	var name: String
	var required: bool
	func _init(_name: String, _required: bool = true):
		name = _name
		required = _required


class CommandDef:
	var name: String
	var args: Array[CommandArg]
	var flags: Array
	var handler: Callable
	var description: String
	var strict: bool
	var allowed_keywords: Array
	var allow_empty: bool

	func _init(
		_name: String,
		_handler: Callable,
		_args := [],
		_flags := [],
		_description := "",
		_strict := true,
		_allowed_keywords := [],
		_allow_empty := false
	):
		name = _name
		handler = _handler
		args.clear()
		for i in _args:
			args.append(i)
		flags = _flags
		description = _description
		strict = _strict
		allowed_keywords = _allowed_keywords
		allow_empty = _allow_empty

	func get_usage() -> String:
		var usage = name
		for a in args:
			if a.required:
				usage += " <" + a.name + ">"
			else:
				usage += " [" + a.name + "]"
		for fl in flags:
			usage += " [--" + fl + "]"
		return usage


class CommandParser:
	var registry: Dictionary = {}

	func register(cmd: CommandDef):
		registry[cmd.name] = cmd

	func parse(line: String) -> Dictionary:
		var tokens = _tokenize(line)
		if tokens.is_empty():
			return _err("empty")

		var cmd_name = tokens[0]
		if not registry.has(cmd_name):
			return _err("unknown_cmd", cmd_name)

		var def: CommandDef = registry[cmd_name]

		for t in tokens.slice(1, tokens.size()):
			if registry.has(t) and not (def.allowed_keywords.has(t) or t == "if"):
				return _err("multi_cmd", t)
		return _parse_tokens(tokens, def)

	func _tokenize(line: String) -> Array:
		var tokens: Array = []
		var curr = ""
		var in_quotes = false
		for ch in line:
			if ch == '"':
				in_quotes = not in_quotes
			elif ch == " " and not in_quotes:
				if curr != "":
					tokens.append(curr)
					curr = ""
			else:
				curr += ch
		if curr != "":
			tokens.append(curr)
		return tokens

	func _parse_tokens(tokens: Array, def: CommandDef) -> Dictionary:
		var data = {"command": tokens[0], "args": {}, "flags": []}
		var i = 1
		data["args"]["action"] = "keep"
		data["args"]["condition"] = ""

		if tokens.size() == 1:
			if def.flags.is_empty() and not def.allow_empty:
				return _err("empty_command", def.name, def)
			else:
				return {"command": tokens[0], "args": {}, "flags": []}

		while i < tokens.size():
			var tok = tokens[i]

			if tok.begins_with("--"):
				var flag_name = tok.substr(2)
				if flag_name not in def.flags:
					return _err("unknown_flag", flag_name, def)
				data["flags"].append(flag_name)
				i += 1
				continue

			if def.allowed_keywords.size() > 0 and tok in def.allowed_keywords:
				data["args"]["action"] = tok
				i += 1
				continue
			elif def.allowed_keywords.size() > 0 and tok not in ["if"]:
				return _err("unknown_action", tok, def, def.allowed_keywords)

			if tok == "if":
				var remaining: Array = []
				i += 1
				while i < tokens.size() and not tokens[i].begins_with("--"):
					remaining.append(tokens[i])
					i += 1
				data["args"]["condition"] = " ".join(remaining)
				break

			if def.strict:
				if def.args.size() > 0:
					data["args"][def.args[0].name] = tok
					i += 1
					continue
				else:
					return _err("too_many_args", tok, def)

			i += 1

		return data

	func _err(code: String, extra = null, def: CommandDef = null, allowed = null) -> Dictionary:
		var msg = ""
		match code:
			"empty":
				msg = "No command entered."
			"unknown_cmd":
				msg = "Unknown command: '%s'" % extra
			"multi_cmd":
				msg = "Multiple commands not allowed: '%s'" % extra
			"unknown_flag":
				msg = "Unknown flag '--%s'" % extra
			"too_many_args":
				msg = "Unexpected argument '%s'" % extra
			"missing_args":
				msg = "Missing required arguments: %s" % str(extra)
			"unknown_action":
				msg = "Unknown action: '%s'. Allowed actions: %s" % [extra, str(allowed)]
			"empty_command":
				msg = "Command '%s' requires at least one argument or flag." % extra
			_:
				msg = "Parse error"
		if def:
			msg += "\nUsage:\n   %s\n%s" % [def.get_usage(), def.description]
		elif code == "unknown_cmd":
			msg += "\nAvailable commands: "
			for c in registry.values():
				msg += "%-12s " % [c.name]
		return {"error": msg}
