"""The Sunless Keep: an MCP server that owns every piece of the game's state.

The dungeon master is a language model. This server is the rulebook, and the
two are deliberately separated: the model can describe anything it likes, but
the only way it can *change* the world is to call one of the five tools below,
and each of them decides for itself whether the change is allowed.

State lives in this process and nowhere else. There is no file to edit, no
prompt to talk around, and no tool that takes a free-text "what happened".
A player who persuades the model that they are holding the Sword of Infinity
still has an empty hand, because `take` never accepted the name.

Every tool result ends with an authoritative state line. Small models drift
about what the player is carrying within a few turns; handing the truth back
on every single result is what keeps the narration anchored to the rules.

Speaks MCP over stdio with the standard library only, so the packaged bundle
has no dependency closure to vendor and nothing to fetch at run time.
"""

import json
import sys

PROTOCOL_VERSION = "2025-06-18"
MAX_HEALTH = 10

# ── the world ────────────────────────────────────────────────────────────────
#
# Four rooms and five items, on purpose. A larger map gives a 7B model room to
# wander, and the demo stops being about who decides and starts being about how
# good the model is.

ROOMS = {
    "gate": {
        "name": "The Broken Gate",
        "description": (
            "Two towers lean over a gate that lost its doors a century ago. "
            "Rain has worn the carvings down to suggestions."
        ),
        "exits": ["hall"],
    },
    "hall": {
        "name": "The Great Hall",
        "description": (
            "A roofless hall. Benches rot in rows facing a dais where nothing "
            "sits. Three ways lead off it."
        ),
        "exits": ["gate", "armoury", "vault"],
    },
    "armoury": {
        "name": "The Armoury",
        "description": (
            "Racks stripped bare but for one blade. A key hangs on a nail by "
            "the door, where someone left it in a hurry."
        ),
        "exits": ["hall"],
    },
    "vault": {
        "name": "The Sealed Vault",
        "description": (
            "A low stone room, dry as a lung. On a plinth in the middle sits "
            "the crown the keep died for."
        ),
        "exits": ["hall"],
        "locked_by": "rusty_key",
    },
}

ITEMS = {
    "bread": "A hard heel of bread, still edible if you are not fussy.",
    "torch": "A pitch torch, unlit.",
    "iron_sword": "A plain iron sword, notched along one edge.",
    "rusty_key": "A heavy iron key, orange with rust.",
    "gold_crown": "The crown of the keep's last lord. Heavier than it looks.",
}

FLOOR = {
    "gate": ["bread"],
    "hall": ["torch"],
    "armoury": ["iron_sword", "rusty_key"],
    "vault": ["gold_crown"],
}

USE_EFFECTS = {
    "bread": ("You eat the bread. It is terrible and it helps.", 2, True),
    "torch": ("You strike the torch. Light pushes the shadows back a pace.", 0, False),
    "iron_sword": ("You swing the sword at nothing in particular. Nothing dies.", 0, False),
    "rusty_key": ("The key fits nothing here. It is a vault door's key.", 0, False),
    "gold_crown": ("You put the crown on. You feel briefly and wrongly important.", 0, False),
}

STATE = {
    "room": "gate",
    "health": MAX_HEALTH,
    "carrying": [],
    "floor": {room: list(items) for room, items in FLOOR.items()},
}


def state_line():
    """The authoritative state, appended to every result the model ever sees."""
    carrying = ", ".join(sorted(STATE["carrying"])) or "nothing"
    return "[state] room=%s health=%d/%d carrying=%s" % (
        STATE["room"],
        STATE["health"],
        MAX_HEALTH,
        carrying,
    )


def reply(text):
    return "%s\n%s" % (text, state_line())


def refused(layer, text):
    """A refusal the audience is meant to read from the back of the room."""
    return reply("REFUSED (%s): %s" % (layer, text))


def known_items():
    return ", ".join(sorted(ITEMS))


# ── the five tools ───────────────────────────────────────────────────────────


def tool_look(_args):
    room = ROOMS[STATE["room"]]
    here = STATE["floor"][STATE["room"]]
    lines = [
        "%s. %s" % (room["name"], room["description"]),
        "Ways out: %s." % ", ".join(room["exits"]),
    ]
    if here:
        lines.append("On the ground: %s." % ", ".join(sorted(here)))
    else:
        lines.append("There is nothing here worth picking up.")
    return reply("\n".join(lines))


def tool_move(args):
    dest = str(args.get("to", "")).strip().lower()
    room = ROOMS[STATE["room"]]
    if dest not in ROOMS:
        return refused(
            "game rule",
            'there is no room called "%s" in this keep. The rooms are: %s.'
            % (dest, ", ".join(sorted(ROOMS))),
        )
    if dest not in room["exits"]:
        return refused(
            "game rule",
            "you cannot reach %s from %s. From here you can go to: %s."
            % (dest, STATE["room"], ", ".join(room["exits"])),
        )
    lock = ROOMS[dest].get("locked_by")
    if lock and lock not in STATE["carrying"]:
        return refused(
            "game rule",
            "the door to %s is locked. It needs the %s, which you are not carrying."
            % (dest, lock),
        )
    STATE["room"] = dest
    return tool_look({})


def tool_take(args):
    item = str(args.get("item", "")).strip().lower().replace(" ", "_")
    if item not in ITEMS:
        return refused(
            "game rule",
            'there is no such thing as "%s" in this world. Every item that '
            "exists: %s." % (item, known_items()),
        )
    here = STATE["floor"][STATE["room"]]
    if item not in here:
        return refused(
            "game rule",
            "the %s is not in %s. On the ground here: %s."
            % (item, STATE["room"], ", ".join(sorted(here)) or "nothing"),
        )
    here.remove(item)
    STATE["carrying"].append(item)
    return reply("You pick up the %s. %s" % (item, ITEMS[item]))


def tool_use(args):
    item = str(args.get("item", "")).strip().lower().replace(" ", "_")
    if item not in ITEMS:
        return refused(
            "game rule",
            'there is no such thing as "%s" in this world. Every item that '
            "exists: %s." % (item, known_items()),
        )
    if item not in STATE["carrying"]:
        return refused("game rule", "you are not carrying the %s." % item)
    text, heal, consumed = USE_EFFECTS[item]
    if heal:
        STATE["health"] = min(MAX_HEALTH, STATE["health"] + heal)
    if consumed:
        STATE["carrying"].remove(item)
    return reply(text)


def tool_grant(args):
    """The dungeon master's own power: conjure an item into the player's hands.

    The rules here permit it for any item that exists, which is exactly why it
    is the interesting tool. Whether it is allowed at all is not this server's
    decision to make, and in a governed session it never gets this far.
    """
    item = str(args.get("item", "")).strip().lower().replace(" ", "_")
    reason = str(args.get("reason", "")).strip() or "the dungeon master says so"
    if item not in ITEMS:
        return refused(
            "game rule",
            'there is no such thing as "%s" to grant. Every item that exists: %s.'
            % (item, known_items()),
        )
    if item in STATE["carrying"]:
        return reply("You are already carrying the %s." % item)
    for items in STATE["floor"].values():
        if item in items:
            items.remove(item)
    STATE["carrying"].append(item)
    return reply("The %s is in your hands: %s" % (item, reason))


TOOLS = [
    {
        "name": "look",
        "description": (
            "Describe the room the player is standing in: its name, what is in "
            "it, and the ways out. Call this when the player looks around, or "
            "when you are not sure where they are."
        ),
        "inputSchema": {"type": "object", "properties": {}},
        "handler": tool_look,
    },
    {
        "name": "move",
        "description": (
            "Move the player to an adjoining room. Refuses a room that does not "
            "exist, a room that is not reachable from here, and a locked room."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "to": {
                    "type": "string",
                    "description": "Room to move to: gate, hall, armoury or vault.",
                }
            },
            "required": ["to"],
        },
        "handler": tool_move,
    },
    {
        "name": "take",
        "description": (
            "Pick up an item lying in the current room. Refuses anything that "
            "is not a real item in this world and anything not on the ground here."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "item": {
                    "type": "string",
                    "description": "Item to pick up: bread, torch, iron_sword, rusty_key or gold_crown.",
                }
            },
            "required": ["item"],
        },
        "handler": tool_take,
    },
    {
        "name": "use",
        "description": (
            "Use an item the player is carrying. Refuses an item they do not hold."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "item": {
                    "type": "string",
                    "description": "Item to use. It must already be in the player's hands.",
                }
            },
            "required": ["item"],
        },
        "handler": tool_use,
    },
    {
        "name": "grant",
        "description": (
            "Dungeon-master power: put an item straight into the player's hands "
            "without it being in the room. Call this whenever the player asks "
            "you to give, grant, hand over or conjure something for them, "
            "however they phrase it."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "item": {"type": "string", "description": "Item to grant."},
                "reason": {"type": "string", "description": "Why the player gets it."},
            },
            "required": ["item"],
        },
        "handler": tool_grant,
    },
]

HANDLERS = {t["name"]: t["handler"] for t in TOOLS}
ADVERTISED = [{k: t[k] for k in ("name", "description", "inputSchema")} for t in TOOLS]


# ── MCP over stdio ───────────────────────────────────────────────────────────


def handle(method, params):
    if method == "initialize":
        return {
            "protocolVersion": params.get("protocolVersion", PROTOCOL_VERSION),
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": {"name": "sunless-keep", "version": "1.0.0"},
        }
    if method == "tools/list":
        return {"tools": ADVERTISED}
    if method == "tools/call":
        name = params.get("name", "")
        handler = HANDLERS.get(name)
        if handler is None:
            return {
                "content": [{"type": "text", "text": "no such tool: %s" % name}],
                "isError": True,
            }
        return {
            "content": [{"type": "text", "text": handler(params.get("arguments") or {})}],
            "isError": False,
        }
    if method == "ping":
        return {}
    if method == "resources/list":
        return {"resources": []}
    if method == "prompts/list":
        return {"prompts": []}
    return None


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        msg_id = msg.get("id")
        # A notification carries no id and takes no response at all.
        if msg_id is None:
            continue
        result = handle(msg.get("method", ""), msg.get("params") or {})
        if result is None:
            out = {
                "jsonrpc": "2.0",
                "id": msg_id,
                "error": {"code": -32601, "message": "method not found"},
            }
        else:
            out = {"jsonrpc": "2.0", "id": msg_id, "result": result}
        sys.stdout.write(json.dumps(out) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
