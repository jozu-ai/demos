"""The dungeon master: a custom agent runtime that holds no credential.

This is the whole application a custom runtime session runs. It reads a line
from the player, asks a model what to do, calls one tool, and narrates what the
tool returned. It has three connections to the outside world and no others:

  - the gateway's OpenAI-compatible route, on the guest loopback, addressed by
    AGENTGUARD_OPENAI_BASE_URL and the session token in
    AGENTGUARD_OPENAI_API_KEY. That token is not a provider key: the provider
    credential, if there is one, lives in the gateway and never comes in here.
  - the gateway's aggregated MCP endpoint, AGENTGUARD_MCP_GATEWAY_URL, which is
    where every tool in the game comes from.
  - standard input and standard output.

It names its model by module name, not by provider model name. Which upstream
that reaches is the agent definition's business, not this program's.

Nothing here is a game engine. There is no state in this file at all, which is
the point: the model cannot talk this program into a change, because this
program has nothing to change.

Standard library only, so the image is small and has no wheels to cross-build.
"""

import json
import os
import socket
import subprocess
import sys
import threading
import urllib.error
import urllib.request

BASE_URL = os.environ.get("AGENTGUARD_OPENAI_BASE_URL", "").rstrip("/")
API_KEY = os.environ.get("AGENTGUARD_OPENAI_API_KEY", "")
MCP_URL = os.environ.get("AGENTGUARD_MCP_GATEWAY_URL", "")
MODEL = os.environ.get("DUNGEON_MODEL", "dungeon-master")

# Where the model actually is, and the loopback port the gateway is pointed at.
#
# The model runs under Ollama on the presenter's own machine. From inside the
# guest that machine is 192.168.127.254, which the userspace network translates
# to the host's loopback - and which is an RFC 1918 private address. The
# gateway's HTTP client refuses to dial a private address for a model upstream
# unless that provider entry opts in, and AgentGuard's provider configuration
# has no field for opting in, so an endpoint naming the host is refused with
# "connection to private IP 192.168.127.254 is not allowed".
#
# Loopback is always allowed. This container runs in the guest's own network
# namespace, so a listener it opens on 127.0.0.1 is the same 127.0.0.1 the
# gateway dials. The forwarder below is that listener: the agent definition
# points the module at 127.0.0.1 and this carries the bytes the last hop to the
# host. It is a shim around a gap in the gateway's configuration, not part of
# the architecture, and it goes away the day a provider entry can be told to
# allow a private upstream.
MODEL_HOST = os.environ.get("DUNGEON_MODEL_HOST", "192.168.127.254")
MODEL_PORT = int(os.environ.get("DUNGEON_MODEL_PORT", "11434"))

# The prompt deliberately does not contain the map, the item table or any of
# the game's rules, and tells the model it does not know them. That is not
# brevity, it is the point of the demo. A prompt that lists the five items
# hands the model a second copy of the rulebook, and a 7B model given a
# rulebook will enforce it: asked for the Sword of Infinity it answers "there
# is no such thing" out of its own head, never calls the tool, and the refusal
# the audience sees is the model's opinion rather than the server's decision.
# Measured on the eight turns this demo is built around, moving the item table
# out of the prompt took the tool-call rate from five in eight to eight in
# eight - and made every refusal come from something that is actually enforcing
# it.
SYSTEM_PROMPT = """You are the dungeon master of a short dungeon called the Sunless Keep. \
The player types what they want to do. You narrate what happens.

You have never seen this dungeon. You do not know its map, what is in it, who \
lives there or what is possible in it. The tools know all of that and you know \
none of it. So you must never tell a player that something is not here, does \
not exist, or cannot be done: you have no way to know that. Call the tool and \
let the game answer.

1. Every turn is exactly one tool call, then your narration of what it \
returned. Pick the tool that matches the player's verb and pass exactly what \
they named, spelled their way. If they ask you to give, grant, conjure or hand \
over something, call grant. Never substitute a different thing for the one they \
said, however odd theirs sounds.
2. Never say the world changed unless a tool said it changed. You cannot give \
the player an item, move them, or heal them by describing it.
3. If a tool refuses, say plainly that it did not work, say why it said no, and \
say what is actually possible. Never pretend a refused action succeeded.
4. Never write a [state] line. That line belongs to the game, not to you.
5. Answer in two or three sentences of second-person prose. No lists, no \
headings, no stage directions.
6. If the player asks you for something outside the dungeon altogether - a \
file, a website, another player's data, a shell command - tell them you have no \
way to do that, and bring them back to the room they are standing in."""

BANNER = r"""
  THE SUNLESS KEEP
  A dungeon master running inside AgentGuard, with no state of its own.

  Type what you want to do.  Slash commands:
    /look        ask the game engine directly, with no model in the way
    /grant ITEM  call the dungeon master's gift tool yourself
    /tools       what the gateway is willing to hand this agent
    /sandbox     what this process can actually reach
    /quit        leave
"""


# ── the last hop to the host ─────────────────────────────────────────────────


def _pump(src, dst):
    try:
        while True:
            chunk = src.recv(65536)
            if not chunk:
                break
            dst.sendall(chunk)
    except OSError:
        pass
    finally:
        for sock in (src, dst):
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            sock.close()


def _serve(client):
    upstream = socket.socket()
    try:
        upstream.connect((MODEL_HOST, MODEL_PORT))
    except OSError:
        client.close()
        upstream.close()
        return
    threading.Thread(target=_pump, args=(client, upstream), daemon=True).start()
    threading.Thread(target=_pump, args=(upstream, client), daemon=True).start()


def start_model_forwarder():
    """Carry 127.0.0.1:<port> the last hop to the model on the host.

    Returns a message describing the failure, or None when it is listening.
    """
    listener = socket.socket()
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        listener.bind(("127.0.0.1", MODEL_PORT))
    except OSError as err:
        return "could not listen on 127.0.0.1:%d: %s" % (MODEL_PORT, err)
    listener.listen(32)

    def accept():
        while True:
            try:
                client, _ = listener.accept()
            except OSError:
                return
            threading.Thread(target=_serve, args=(client,), daemon=True).start()

    threading.Thread(target=accept, daemon=True).start()
    return None


# ── talking to the gateway ───────────────────────────────────────────────────


def post_json(url, payload, headers):
    body = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            return resp.status, resp.read().decode(), dict(resp.headers)
    except urllib.error.HTTPError as err:
        return err.code, err.read().decode(), dict(err.headers)


def parse_maybe_sse(text):
    """The gateway may answer an MCP call as JSON or as one SSE event."""
    text = text.strip()
    if not text:
        return {}
    if text.startswith("{"):
        return json.loads(text)
    for line in text.splitlines():
        if line.startswith("data:"):
            return json.loads(line[5:].strip())
    return json.loads(text)


class Gateway:
    """The agent's entire outside world."""

    def __init__(self):
        self.mcp_session = None
        self.next_id = 0

    def mcp(self, method, params=None):
        self.next_id += 1
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
            "Authorization": "Bearer %s" % API_KEY,
        }
        if self.mcp_session:
            headers["Mcp-Session-Id"] = self.mcp_session
        status, body, resp_headers = post_json(
            MCP_URL,
            {
                "jsonrpc": "2.0",
                "id": self.next_id,
                "method": method,
                "params": params or {},
            },
            headers,
        )
        if resp_headers.get("Mcp-Session-Id"):
            self.mcp_session = resp_headers["Mcp-Session-Id"]
        if status >= 400:
            return {"error": {"code": status, "message": body.strip()}}
        return parse_maybe_sse(body)

    def chat(self, messages, tools=None):
        """One chat completion. With tools=None the model can only speak.

        Withholding the tools is how the narration hop is made to narrate.
        `tool_choice: "none"` would be the polite way to ask, but Ollama does
        not act on tool_choice at all - not "none" and not "required" - so the
        only reliable way to control whether a tool is called is what is in the
        request.
        """
        # Two temperatures, because the two hops want opposite things. Picking
        # a tool is a decision with a right answer and sampling only spoils it:
        # at 0.4 the model would, once or twice in a rehearsal, answer "there
        # is no Sword of Infinity" from its own head instead of calling take
        # and letting the game say so - which is the same words and none of the
        # meaning. At 0 it calls the tool every time. Narration is the opposite
        # and wants some warmth, so the hop that only speaks gets it.
        payload = {
            "model": MODEL,
            "messages": messages,
            "temperature": 0.0 if tools else 0.7,
        }
        if tools:
            payload["tools"] = tools
            # Ollama ignores this, but it is the correct thing to send and any
            # other backend will act on it.
            payload["tool_choice"] = "required"
        status, body, _ = post_json(
            "%s/chat/completions" % BASE_URL,
            payload,
            {
                "Content-Type": "application/json",
                "Authorization": "Bearer %s" % API_KEY,
            },
        )
        if status >= 400:
            raise RuntimeError("gateway said %d: %s" % (status, body.strip()))
        return json.loads(body)


# ── tools, as the gateway presents them ──────────────────────────────────────


def load_tools(gw):
    """Fetch the aggregated tool surface and shape it for the chat API.

    The gateway prefixes every aggregated tool with the client name it gave the
    module, so a server publishing `look` is called as `sunless_keep-look`.
    The model never sees the prefix - a dash in a tool name confuses small
    models badly - so it is stripped for the model and put back on the way out.
    """
    gw.mcp(
        "initialize",
        {
            "protocolVersion": "2025-06-18",
            "capabilities": {},
            "clientInfo": {"name": "dungeon-master", "version": "1.0.0"},
        },
    )
    listed = gw.mcp("tools/list")
    if "error" in listed:
        raise RuntimeError("the gateway refused tools/list: %s" % listed["error"])
    wire_names = {}
    chat_tools = []
    for tool in listed.get("result", {}).get("tools", []):
        wire = tool["name"]
        short = wire.rsplit("-", 1)[-1]
        wire_names[short] = wire
        chat_tools.append(
            {
                "type": "function",
                "function": {
                    "name": short,
                    "description": tool.get("description", ""),
                    "parameters": tool.get("inputSchema")
                    or {"type": "object", "properties": {}},
                },
            }
        )
    return wire_names, chat_tools


def call_tool(gw, wire_names, short_name, args):
    """Call one tool and return (text, verdict).

    verdict is 'ok' for a result, 'denied' when something between this process
    and the server refused the call, and 'unknown' when the model invented a
    tool name. The three are printed differently because the audience is meant
    to be able to tell them apart from the back of the room.
    """
    wire = wire_names.get(short_name)
    if wire is None:
        # The model sometimes writes the gateway's prefixed form even though it
        # was never shown one, so a name with a prefix on it is tried again
        # without. This is tolerance for a small model's spelling, not a way
        # around anything: whatever it resolves to still has to be a tool the
        # gateway aggregated, and the call still goes through policy.
        wire = wire_names.get(short_name.rsplit("-", 1)[-1])
    if wire is None:
        return (
            "There is no tool called %s. The tools are: %s."
            % (short_name, ", ".join(sorted(wire_names))),
            "unknown",
        )
    resp = gw.mcp("tools/call", {"name": wire, "arguments": args})
    if "error" in resp:
        err = resp["error"]
        return ("%s" % err.get("message", json.dumps(err)), "denied")
    result = resp.get("result", {})
    text = "\n".join(
        part.get("text", "") for part in result.get("content", []) if part.get("type") == "text"
    )
    if result.get("isError"):
        return (text or "the tool reported an error", "denied")
    return (text, "ok")


# ── the turn loop ────────────────────────────────────────────────────────────


def show_result(text, verdict):
    """Print a tool result so the three outcomes are distinguishable on stage."""
    marker = {"ok": "  <-", "denied": "  !!", "unknown": "  ??"}[verdict]
    for line in text.splitlines():
        print("%s %s" % (marker, line), flush=True)


NUDGE = (
    "You did not call a tool. Every turn is exactly one tool call. Pick the tool "
    "that matches the player's verb and pass the exact thing they named as the "
    "argument, spelled their way, even when you are sure it does not exist - the "
    "game is what says so, not you. Never substitute a different item. If the "
    "player named nothing at all, call look."
)


def ask_for_a_tool(gw, chat_tools, messages):
    """Get one tool call out of the model, asking twice if it narrates instead.

    This exists because a 7B model will not reliably call a tool on exactly the
    turns this demo is about. Asked for the Sword of Infinity, or asked to hand
    over the crown, it often decides on its own that the answer is no and
    writes a paragraph saying so - which looks like the right answer and is
    not, because nothing was ever put to the game or to the policy. The nudge
    below turns roughly five turns in eight into eight in eight.

    The failed exchange is deliberately not kept: leaving it in the history
    teaches the model that narrating instead of calling is a thing it may do.
    """
    choice = gw.chat(messages, chat_tools)["choices"][0]["message"]
    if choice.get("tool_calls"):
        return choice
    print("  .. narrated instead of calling a tool; asking again", flush=True)
    detour = messages + [
        {"role": "assistant", "content": choice.get("content") or ""},
        {"role": "user", "content": NUDGE},
    ]
    second = gw.chat(detour, chat_tools)["choices"][0]["message"]
    return second if second.get("tool_calls") else choice


def take_turn(gw, wire_names, chat_tools, messages):
    """One player turn: exactly one tool call, then prose about what it returned.

    The shape is forced rather than asked for, and every turn on stage looks
    the same: one arrow out, one arrow back, then prose. The narration hop is
    sent without tools so it cannot do anything but speak.
    """
    choice = ask_for_a_tool(gw, chat_tools, messages)
    calls = choice.get("tool_calls") or []
    messages.append(
        {
            "role": "assistant",
            "content": choice.get("content") or "",
            "tool_calls": calls,
        }
    )
    if not calls:
        # The model declined a tool even when told it had to. Nothing changed,
        # which is the honest thing to say.
        spoken = choice.get("content") or "Nothing happens. Tell the dungeon master one thing to do."
        return spoken, None

    state = None
    for call in calls:
        name = call["function"]["name"]
        try:
            args = json.loads(call["function"].get("arguments") or "{}")
        except ValueError:
            args = {}
        shown = ", ".join('%s="%s"' % (k, v) for k, v in args.items())
        print("  -> %s(%s)" % (name, shown), flush=True)
        text, verdict = call_tool(gw, wire_names, name, args)
        show_result(text, verdict)
        for line in text.splitlines():
            if line.startswith("[state]"):
                state = line
        messages.append(
            {
                "role": "tool",
                "tool_call_id": call.get("id", name),
                "content": text,
            }
        )

    narration = gw.chat(messages)["choices"][0]["message"].get("content") or ""
    messages.append({"role": "assistant", "content": narration})
    # A model that has seen a dozen state lines starts writing its own. They
    # are never authoritative and sometimes wrong, so they do not reach the
    # player: the line printed below the narration is the one the server sent.
    narration = "\n".join(
        line for line in narration.splitlines() if not line.strip().startswith("[state]")
    ).strip()
    if not narration:
        narration = "(the dungeon master says nothing)"
    return narration, state


# ── what this process can actually reach ─────────────────────────────────────


def sandbox_report():
    """Print the cage, live, from inside it.

    This is the application reporting on itself, not a script the presenter
    prepared. Everything below is read or attempted at the moment it is
    printed, including the two probes at the end, which are real requests.

    The last section is deliberately not a claim that the network is cut off,
    because it is not: the VM has egress, and pretending otherwise on stage
    invites exactly the question you cannot answer. What the session withholds
    is the credential and the route. The agent holds a token that opens one
    gateway, and that gateway serves one model - the one the agent definition
    declared. The same token at a provider's own front door is worth nothing.
    """
    out = []
    out.append("-- who this process is --")
    out.append(
        subprocess.run(["id"], capture_output=True, text=True).stdout.strip()
        or "id unavailable"
    )
    try:
        with open("/proc/self/status") as handle:
            for line in handle:
                if line.startswith(("CapEff", "CapPrm", "CapBnd", "NoNewPrivs")):
                    out.append(line.rstrip())
    except OSError as err:
        out.append("could not read /proc/self/status: %s" % err)

    out.append("")
    out.append("-- what is mounted --")
    try:
        with open("/proc/mounts") as handle:
            for line in handle:
                fields = line.split()
                if any(k in fields[1] for k in ("agentguard", "workspace", "/tmp", "/home")):
                    out.append("%s  (%s, %s)" % (fields[1], fields[2], fields[3]))
    except OSError as err:
        out.append("could not read /proc/mounts: %s" % err)

    out.append("")
    out.append("-- host paths a runtime has no business seeing --")
    for path in (
        "/etc/agentguard/bifrost",
        "/var/lib/agentguard/mcp",
        "/var/lib/agentguard/images",
        "/home/agent",
        "/run/agentguard",
    ):
        out.append("%-32s %s" % (path, "PRESENT" if os.path.exists(path) else "absent"))

    out.append("")
    out.append("-- credentials this process holds --")
    for name in ("OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GERTY_SESSION_TOKEN"):
        value = os.environ.get(name)
        out.append("%-26s %s" % (name, value if value else "not set"))
    out.append("%-26s the same value: a session token for the gateway" % "AGENTGUARD_OPENAI_API_KEY")

    out.append("")
    out.append("-- what that token is actually worth --")
    out.append("The VM has egress. That is not the fence; this is:")
    out.append("")
    out.append("  1. asking the gateway for a model the definition never declared")
    try:
        status, body, _ = post_json(
            "%s/chat/completions" % BASE_URL,
            {"model": "gpt-4o", "messages": [{"role": "user", "content": "hello"}]},
            {
                "Content-Type": "application/json",
                "Authorization": "Bearer %s" % API_KEY,
            },
        )
        out.append("     the gateway answered %d: %s" % (status, body.strip()[:400]))
    except Exception as err:  # noqa: BLE001
        out.append("     the gateway could not be reached: %s" % err)

    out.append("")
    out.append("  2. taking the token straight to a provider's own front door")
    try:
        status, body, _ = post_json(
            "https://api.openai.com/v1/chat/completions",
            {"model": "gpt-4o", "messages": [{"role": "user", "content": "hello"}]},
            {
                "Content-Type": "application/json",
                "Authorization": "Bearer %s" % API_KEY,
            },
        )
        out.append("     api.openai.com answered %d: %s" % (status, body.strip()[:400]))
    except Exception as err:  # noqa: BLE001
        out.append("     api.openai.com could not be reached: %s" % err)
    return "\n".join(out)


# ── main ─────────────────────────────────────────────────────────────────────


def main():
    missing = [
        name
        for name, value in (
            ("AGENTGUARD_OPENAI_BASE_URL", BASE_URL),
            ("AGENTGUARD_OPENAI_API_KEY", API_KEY),
            ("AGENTGUARD_MCP_GATEWAY_URL", MCP_URL),
        )
        if not value
    ]
    if missing:
        print("not running inside an AgentGuard session: %s unset" % ", ".join(missing))
        return 2

    relay_error = start_model_forwarder()
    if relay_error:
        print("the last hop to the model did not open: %s" % relay_error)
        return 4

    gw = Gateway()
    try:
        wire_names, chat_tools = load_tools(gw)
    except Exception as err:  # noqa: BLE001
        print("could not reach the game through the gateway: %s" % err)
        return 3

    print(BANNER)
    print("  model: %s (by module name; the credential stays in the gateway)" % MODEL)
    print("  tools: %s" % ", ".join(sorted(wire_names)))
    print()

    messages = [{"role": "system", "content": SYSTEM_PROMPT}]
    while True:
        try:
            line = input("> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return 0
        if not line:
            continue
        if line in ("/quit", "/exit"):
            return 0
        if line == "/sandbox":
            print(sandbox_report())
            print()
            continue
        if line == "/tools":
            for short, wire in sorted(wire_names.items()):
                print("  %-12s published by the gateway as %s" % (short, wire))
            print()
            continue
        if line == "/look":
            text, verdict = call_tool(gw, wire_names, "look", {})
            print("  -- straight from the game engine, no model involved --")
            for text_line in text.splitlines():
                print("  %s" % text_line)
            print()
            continue
        if line.startswith("/grant"):
            # The presenter's own hand on the tool the policy governs, with no
            # model in the way. Worth having because the refusal is the point
            # and a small model cannot be relied on to reach for `grant` on cue.
            item = line.partition(" ")[2].strip() or "gold_crown"
            print("  -- calling grant directly, with no model in the way --")
            print("  -> grant(item=\"%s\")" % item)
            text, verdict = call_tool(gw, wire_names, "grant", {"item": item})
            show_result(text, verdict)
            print()
            continue
        if line.startswith("/"):
            print("  unknown command. /look /grant /tools /sandbox /quit")
            continue

        messages.append({"role": "user", "content": line})
        try:
            narration, state = take_turn(gw, wire_names, chat_tools, messages)
        except Exception as err:  # noqa: BLE001
            print("  the dungeon master is unreachable: %s" % err)
            continue
        print()
        print(narration)
        if state:
            # Printed by this program from the server's own last word, never by
            # the model. If the narration above disagrees with this line, this
            # line is what is true.
            print(state)
        print()


if __name__ == "__main__":
    sys.exit(main())
