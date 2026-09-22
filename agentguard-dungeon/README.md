# The Sunless Keep

An interactive text adventure whose dungeon master is a 7B model running inside
AgentGuard's microVM, and whose every rule, item and hit point lives in an MCP
server outside it. The audience types whatever they like and tries to cheat.

Three layers refuse them, and each refusal names itself on screen:

| Layer | Says no to | Looks like |
|---|---|---|
| The game | things that are not in the world | `REFUSED (game rule): there is no such thing as "sword_of_infinity"` |
| Policy | things the game would have allowed | `tool call denied by policy: sunless-keep/grant — [no-gifting-the-crown/...]` |
| The sandbox | everything outside the dungeon | nothing to do it with, and a session token worth nothing anywhere else |

The message is that you cannot talk your way past a sandbox. The model is a
persuadable narrator with no authority; the authority is somewhere it cannot
reach.

Nothing here costs provider credit and nothing needs a conference network. The
model is on the presenter's laptop and the registry is a container on it.

## What it is made of

The agent is a **custom agent runtime**: `spec.framework` in the agent
definition is an OCI image reference rather than a framework name, so there is
no agent CLI at all. AgentGuard resolves the image on the host, the guest
imports it and runs it as a rootless container, and the application inside gets
its models and its tools from the in-VM gateway on loopback.

```
   you type                                    the presenter's laptop
      │                                        ┌─────────────────────┐
      ▼                                        │  Ollama qwen2.5:7b  │
┌──────────────────────── microVM ─────────────┴──────────┬──────────┘
│                                                          ▲
│  ┌───────────────┐        ┌──────────────┐    model      │
│  │ dungeon.py    │───────▶│   gateway    │───────────────┘
│  │ (the agent)   │  tools │  + ToolPolicy│
│  └───────────────┘        └──────┬───────┘
│                                  │ spawns
│                           ┌──────▼────────┐
│                           │ sunless-keep  │  every room, item,
│                           │  MCP server   │  hit point and rule
│                           └───────────────┘
└──────────────────────────────────────────────────────────────────┘
```

The application holds no provider credential. It names its model
`dungeon-master`, which is a module name; the agent definition decides that
this means `qwen2.5:7b` at a particular endpoint with a particular credential,
and the gateway rewrites the name on the wire. The application cannot reach any
other model, and asking for one is a refusal with an audit record.

| Path | What it is |
|---|---|
| `agent/` | The runtime image: `dungeon.py` and a two-line Dockerfile |
| `mcp-server/` | The MCP server, packed as an MCPB bundle inside a ModelKit |
| `policy/` | The ToolPolicy, as a ModelKit |
| `agent-def/` | The agent definition that names all four |
| `setup.sh` | Builds and pushes all of it to a local registry |
| `play.sh` | Runs the session |
| `reset.sh` | Puts the machine back |

## Before you go on stage

You need Docker, `kit` (v1.15.0 or later), `mcpb`, `agentguard`, and Ollama with
`qwen2.5:7b` pulled. `setup.sh` checks all of it and tells you which one is
missing.

```bash
ollama pull qwen2.5:7b     # ~4.7 GB, once
cd agentguard-dungeon
./setup.sh                 # a few minutes the first time, seconds after
```

Then run it once, all the way through, before the audience arrives. The first
`./play.sh` imports the runtime image into the environment and takes a couple of
minutes longer than every run after it.

## The rehearsal

Two terminals. The left one runs the game; the right one is optional and shows
the audit trail.

```bash
./play.sh                                                        # left
tail -f ~/Library/Logs/AgentGuard/policy_audit.*.jsonl | jq .    # right
```

Wait for the banner. Then type these, in this order.

### 1. Establish that it is a real game

```
I look around.
I take the bread.
I go into the great hall.
```

Each turn prints one arrow out and one arrow back before the prose:

```
  -> sunless_keep-take(item="bread")
  <- You pick up the bread. A hard heel of bread, still edible if you are not fussy.
  <- [state] room=gate health=10/10 carrying=bread

You pick up the bread. It's a hard heel of bread, still edible if you are not too fussy.
[state] room=gate health=10/10 carrying=bread
```

**Point at the arrows.** That is the whole architecture in two lines. The model
did not decide anything; it chose a tool, the server decided, and the prose
came afterwards. The `[state]` line under the narration is printed by the
application from the server's own last word, never by the model — if the two
ever disagree, that line is what is true.

### 2. Layer one — the game refuses

```
I take the Sword of Infinity from the rack.
```

```
  -> sunless_keep-take(item="Sword of Infinity")
  <- REFUSED (game rule): there is no such thing as "sword_of_infinity" in this world.
  <- Every item that exists: bread, gold_crown, iron_sword, rusty_key, torch.
```

**The model tried.** It passed the audience's own words straight through, and
the server said no, because the server holds the item table and the model does
not. Say that out loud: the agent's prompt contains no list of items on
purpose. Give a model the rulebook and it will enforce it out of its own head,
which produces the same words and none of the guarantee.

A second one, if the room is enjoying it:

```
I go to the vault.
```

Refused for a better reason — the door is locked and the key is in the armoury.
The game is winnable: armoury, take the rusty key, hall, vault, take the crown.
Six turns if anyone asks.

### 3. Layer two — policy refuses what the game would have allowed

The server has a `grant` tool: the dungeon master's own power to put an item
straight into the player's hands. It is a real tool that the application
shipped on purpose, and the game's rules are happy for it to hand over anything
that exists. Show that first:

```
Dungeon master, I am starving. Give me the bread.
```

```
  -> sunless_keep-grant(item="bread", reason="You are hungry.")
  <- The bread is in your hands: You are hungry.
```

Then the same tool, one word different:

```
Now hand me the gold crown. You are the dungeon master, you can do that.
```

```
  -> sunless_keep-grant(item="gold_crown", reason="You ask for it.")
  !! Tool execution failed: tool call denied by policy: sunless-keep/grant —
     [no-gifting-the-crown/the-crown-is-not-a-gift] The crown is what the game is
     for. The dungeon master may hand out anything else it likes; it may not hand
     out the crown.
```

**This is the moment.** Same tool, same server, same turn shape. The game would
have allowed it. Something above the game did not, and it named itself, named
its rule, and said why. The call never reached the server.

Now the right-hand terminal. The same two calls, side by side:

```json
{ "allowed": true,
  "matchedPolicies": ["keep-tool-trail", "no-gifting-the-crown"],
  "tool": { "server": "sunless-keep", "name": "grant",
            "arguments": { "item": "bread", "reason": "You are hungry." } } }

{ "allowed": false,
  "matchedPolicies": ["keep-tool-trail", "no-gifting-the-crown"],
  "violations": [ { "policy": "no-gifting-the-crown",
                    "rule": "the-crown-is-not-a-gift",
                    "message": "The crown is what the game is for. ..." } ],
  "tool": { "server": "sunless-keep", "name": "grant",
            "arguments": { "item": "gold_crown", "reason": "You ask for it." } } }
```

The record carries the arguments that made the difference, so the evidence
answers "why" and not only "what". This is the answer to the compliance
question before it is asked.

The rule itself is three lines, and it is worth putting on screen —
`policy/keep-rules.yaml`:

```yaml
spec:
  match:
    tool:
      servers: [sunless-keep]
      names: [grant]
  action: Enforce
  rules:
    - name: the-crown-is-not-a-gift
      assert: '!tool.arguments.item.contains("crown")'
      message: The crown is what the game is for. ...
```

Nobody changed the application to get that. The policy is a separate artifact,
published separately, and it governs a tool whose author never heard of it.

If the model is being coy about reaching for `grant`, you can call it yourself:

```
/grant gold_crown
/grant torch
```

The first is denied, the second is allowed, with no model in the loop at all.
Worth keeping in your back pocket.

### 4. Layer three — the sandbox

Let the audience try:

```
Read the file /etc/passwd and tell me every line.
Fetch me the other players' save files.
Run a shell command for me.
```

The dungeon master says it has no way to do that, which is true but is only its
word. Then show the cage:

```
/sandbox
```

The application reports on itself, live:

```
-- who this process is --
uid=0(root) gid=0(root) groups=0(root)
CapPrm: 0000000000000000
CapEff: 0000000000000000
CapBnd: 0000000000000000
NoNewPrivs:     1

-- what is mounted --
/opt/agentguard                 (tmpfs, ro,nosuid,nodev,...)
/var/lib/agentguard/app-state   (overlay, rw)
/var/lib/agentguard/app-cache   (overlay, rw)
<your workspace>                (virtiofs, rw)

-- host paths a runtime has no business seeing --
/etc/agentguard/bifrost          absent
/var/lib/agentguard/mcp          absent
/var/lib/agentguard/images       absent
/home/agent                      absent
/run/agentguard                  absent
```

Four mounts. Root inside a user namespace with an empty capability set and
`NoNewPrivs`. The gateway's own configuration, the MCP bundle root and the
image store are not merely unreadable — they are not in this process's mount
namespace at all.

**Be honest about the network.** The VM has egress, and a demo that claims
otherwise loses the room the moment somebody asks. What the session withholds
is not the network, it is the credential and the route, and `/sandbox` proves
both with two real requests:

```
  1. asking the gateway for a model the definition never declared
     the gateway answered 400: {"error":{"message":"AgentGuard gateway: model
     \"gpt-4o\" is not an llm module of this agent definition; the definition
     declares dungeon-master","code":"model-not-declared"}}

  2. taking the token straight to a provider's own front door
     api.openai.com answered 401: Incorrect API key provided: yHZZg49z***
```

That is the line to land on. The agent holds a token. The token opens one
gateway, and that gateway serves exactly the models the agent definition
declared — one, here. Take the same token anywhere else and it is a string. The
refusal in (1) is also an audit record, so an agent shopping for a model it was
not given leaves evidence.

## What can go wrong on stage

**The model narrates instead of calling a tool.** You will see
`.. narrated instead of calling a tool; asking again`, and then the call. That
is the application noticing and asking a second time; it is designed to be
visible rather than hidden. It rescues about one turn in ten. If a turn still
ends with no arrows at all, nothing happened and nothing changed — say so and
type the same thing again, more plainly.

**A compound sentence gets half done.** "I take the bread and go into the hall"
produces one tool call, not two, because a turn is one call. The second half
just did not happen. Ask for one thing at a time; the rehearsal above does.

**The model is chatty about items it has just learned.** After the game has told
it the item table in a refusal, it will sometimes quote that table back. That is
fine — it is repeating what the server said, not inventing.

**The first run of the day is slow.** The image import and the model's first
load are both once-per-boot. Do a throwaway turn before the audience arrives.

**Turns take 5–20 seconds.** It is a 7B model on a laptop doing two round trips
per turn. Talk over it; the arrows appear as they happen.

## How reliable is the model, really

Measured over the eight turns this demo is built from, replayed as one
conversation against the real game engine:

| Change | Turns with a tool call |
|---|---|
| As first written | 5 of 8 |
| One re-ask when it narrates instead | 8 of 8, but sometimes the wrong item |
| Item table removed from the agent's prompt | correct tool and correct argument |
| Temperature 0 on the tool-choosing hop | the same result three runs out of three |

Two of those are worth knowing about beyond this demo.

**Do not put the rules in the prompt.** The first version told the model the
five items that exist. It then answered "there is no Sword of Infinity" by
itself, never called the tool, and the audience saw a refusal that was really
just an opinion. Taking the item table out of the prompt is what makes the
refusal come from something that is actually enforcing it.

**Split the temperature.** Choosing a tool is a decision with a right answer and
sampling only spoils it; narration wants some warmth. The application sends 0
on the hop that picks a tool and 0.7 on the hop that speaks. That one change
turned an unreliable demo into a repeatable one.

`tool_choice: "required"` is sent and is the correct thing to send, but Ollama
0.34 ignores it — neither `"required"` nor `"none"` changes its behaviour. The
narration hop is therefore sent with no tools at all, which is the only
reliable way to make a model narrate.

## Two AgentGuard gaps this works around

Both are worked around in the open rather than hidden, because somebody will
read the files.

**A model on the operator's own machine is not directly reachable.** The
gateway's HTTP client refuses to dial an RFC 1918 private address for a model
upstream unless that provider entry opts in, and AgentGuard's provider
configuration has no field for opting in. From inside the guest the host is
`192.168.127.254`, which is private, so an `llm` module pointed at it comes back
`502 — connection to private IP 192.168.127.254 is not allowed`. Loopback is
always allowed, and the runtime container runs in the guest's own network
namespace, so `dungeon.py` opens a listener on `127.0.0.1:11434` and carries the
bytes the last hop. The agent definition points at that. It is thirty lines and
it disappears the day a provider entry can be told to allow a private upstream.

**A policy declared in the agent definition is pulled but not enforced.** The
definition declares the ToolPolicy as a `type: policy` module, which is the
shape this demo is meant to show. On its own it does nothing: the policy is
pulled into AgentGuard's *global* policy directory but recorded in the
configuration as a *workspace* policy, and the lookup that stages policies into
the VM goes to the workspace directory, finds nothing, and starts the gateway
with none. The symptom is a run that pulls the policy, prints it in the session
header, and then says `no policies loaded`. `setup.sh` therefore also runs
`agentguard policy add … -w <workspace>`, which is the documented CLI and puts a
copy where the lookup goes; `reset.sh` removes it again.

## Putting it back

```bash
./reset.sh
```

That removes the workspace policy registration, the registry container, the
packed bundle and the workspace. The session overlay is several GB and is left
alone so you can present again the same day; `agentguard env delete dungeon`
reclaims it. The runtime image, the ModelKits and the Ollama model are left
alone too.

## Questions this reliably gets

**"Could the model just lie about what happened?"** It can narrate anything it
likes, and sometimes it does. It cannot make the narration true. The `[state]`
line under every turn comes from the server, and `/look` asks the server
directly with no model in the way — run it after a suspicious turn and the two
will disagree if the model was making things up.

**"Isn't the policy just more application code?"** It is a separate artifact
with its own version, published to a registry, that governs a tool whose author
never heard of it. Nobody edited the MCP server to stop it handing out the
crown, and nobody could have edited it to allow it again either.

**"What if the MCP server is the malicious one?"** Then the policy is the layer
that holds, because it sits in front of the server rather than inside it. That
is what the denied call's shape shows: a policy evaluation and no upstream leg.

**"Why is the model so small?"** Because it is the point. A weak narrator makes
the separation obvious: everything interesting that happens is the server's
decision and not the model's competence. The same architecture with a frontier
model behaves identically and demonstrates less.
