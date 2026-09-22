# AgentGuard telemetry demo stack

A Grafana board fed by a real `agentguard run`, for showing what governed agent
traffic looks like: what policy decided, what it cost in latency, and what the
agent spent in tokens — with the audit trail linked to the request that caused
it. Both paths out of the sandbox are covered, the model calls the agent makes
and the MCP tool calls it makes.

## Run it

```bash
docker compose up -d
export OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318
agentguard run claude-code
open http://localhost:3000
```

That environment variable is read by the **host relay** inside `agentguard
run`, never by the sandbox. The agent cannot see this address, which is the
point of the relay: the collector's location and credentials stay outside the
VM. At boot you should see the relay confirm its destinations:

```
telemetry: traces → http://127.0.0.1:4318
telemetry: metrics → http://127.0.0.1:4318
telemetry: logs → http://127.0.0.1:4318
```

If a destination is rejected you get `OTLP telemetry disabled: <reason>` on the
terminal instead of silence.

The MCP row stays empty under a plain `agentguard run claude-code`, because an
agent with no MCP modules has no tools to call. To fill it, run an agent
definition that declares at least one server:

```yaml
includes:
  - name: github
    type: mcp
    source:
      endpoint: https://api.githubcopilot.com/mcp/
    transport: http
    headers:
      Authorization: "Bearer ${needs.GITHUB_TOKEN}"
```

```bash
agentguard run claude-code --agent-ref <your-agent-kit>
```

Every module is routed through the in-VM gateway, local and remote alike, so
there is no second thing to configure: if the agent can call the tool, the call
is on the board.

## What the board shows

**Governance** — policy evaluations, how many were denied, and the audit trail
itself. Two things feed these totals: every LLM request is evaluated twice
(request in, response out), and every MCP tool call is evaluated once. So the
evaluation count runs a little above double the request count whenever the agent
is also using tools. `gerty_policy_kind` separates the two.

**Latency** — model request latency, and the gateway's total against the
upstream provider call. Resist reading that gap as overhead: since SSE spans
now end at stream close while the upstream metric records at round-trip
completion, on streamed traffic the gap is mostly generation time. The honest
overhead number is the policy-evaluation panel, which is sub-millisecond.

**Usage** — tokens by model and direction, taken from the provider's own usage
reporting. Attribution is per model rather than per host, which is what makes
cost allocation possible later.

**Traces** — the calls themselves, not a number about them. One panel lists
every MCP tool call as a trace, the other lists only the calls a policy refused,
selected on the `error.type` the gateway stamps. Opening a row gives the span
tree, and from any span the Tempo datasource links on to that call's audit
records in Loki.

**MCP** — tool calls by server and tool, how many were denied, and the audit
record for each. Servers are named as the agent definition declares them, which
is the same identity policies match on, rather than the sanitized client name the
gateway composes tool names from. Two duration lines per call: the gateway's
whole round trip, policy evaluation included, and the upstream leg it spent
talking to the server. Unlike the LLM latency panel above, the gap between these
two really is the gateway's cost, because both measure a complete round trip.

## The demo moment

Trigger a denial, then follow it across all three signals:

1. The **Policy decisions** panel turns red for that interval.
2. The **Audit trail** panel shows the record, with the policy and the rules
   that fired.
3. Click the record's `TraceID` and land on the exact request span in Tempo —
   the model call, both policy evaluations, and the upstream leg.

That round trip is the argument for emitting audit events as OTLP logs rather
than only shipping them to Hub: evidence and telemetry become one queryable
story in infrastructure the customer already owns.

The same jump works from a **metric**. The gateway records its duration
histograms inside the span that produced them, so each bucket carries the trace
id of one real call — an exemplar. Grafana draws those as dots on the latency
panels, and clicking one lands on that call in Tempo. It is the answer to the
question a latency graph always raises and never answers: which call was that.
Hover a dot on **Tool call duration** and you are one click from the span tree
of the call that produced the spike.

Two things to know before you point at it. Exemplars need
`--enable-feature=exemplar-storage` on Prometheus, which is still behind a flag:
without it the OTLP write is accepted and the exemplars on it are dropped, so
the panels simply have no dots and nothing says why. And the LLM metrics carry
none. The passthrough records `gen_ai.client.operation.duration` and
`gen_ai.client.token.usage` on a detached context, because the fasthttp request
context it would otherwise use is recycled out from under it, and a measurement
recorded outside a span cannot carry an exemplar. So the dots appear on the MCP
and policy-evaluation panels and not on the model-latency ones. Closing that gap
is a change in the gateway, not here.

A denied **tool call** tells the same story with a sharper picture. Write a
`ToolPolicy` that refuses one server, let the agent try it, and follow it the
same way: **Tool calls denied** ticks, the **MCP audit trail** names the server
and the tool, and its `TraceID` lands on the call's span in Tempo. What to point
at there is the shape rather than any attribute — the denied call's span has a
policy evaluation under it and nothing else, while an allowed call has a second
child for the upstream leg. The refusal is visible as a leg that never happened,
which is the clearest way to show enforcement sitting in front of the server
rather than beside it.

Tool arguments and results are deliberately absent from every span. They can
carry secrets and spans leave the box; the audit record holds sanitized
arguments instead.

## Timing notes

Traces batch out in a few seconds. **Metrics take up to 60s** — that is the SDK
export interval, not a broken pipeline, so give a fresh demo a minute before
concluding the panels are empty.

That 60s cadence is also why every rate-based panel pins `interval: 4m`.
Grafana resolves `$__rate_interval` to `interval + scrape_interval`, so a
pinned 1m gives a 75s window against Prometheus's 15s scrape — and with the
gateway exporting once a minute, that window holds a single sample. `rate()`
over one sample is not a small number, it is no data at all, so the panels read
empty rather than sparse. 4m gives 4m15s, four exports, which is the least that
produces a reliable rate at this cadence. The stat panels are unaffected because
they sum over `$__range` rather than a rate window, which is why a board can
show live counters above empty latency and usage graphs.

The gateway does not currently accept `OTEL_METRIC_EXPORT_INTERVAL` from the
host (only the endpoint and resource attributes are passed into the sandbox),
so shortening the cadence for snappier demos would need a change on the
AgentGuard side.

## Shape of it

```
agentguard run ──▶ host relay ──▶ otel-collector:4318 ──┬──▶ tempo       (traces)
                                                        ├──▶ loki        (logs)
                                                        └──▶ prometheus  (metrics)
                                                                  │
                                                              grafana:3000
```

A collector is used so there is one address to configure and one place to look
when nothing arrives. AgentGuard also supports per-signal endpoints
(`OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` and friends), so the three backends can
be targeted directly if you would rather drop the collector.

## Files

| File | Why |
|---|---|
| `docker-compose.yml` | The stack. Only 4318 matters to AgentGuard. |
| `otel-collector.yaml` | Receives OTLP, fans out per signal. |
| `prometheus.yml` | Promotes AgentGuard identity attributes to labels so the dashboard can filter by environment and run. |
| `tempo.yaml` | Short flush intervals so spans appear while you are still demoing. |
| `grafana/provisioning/` | Datasources (trace↔log linking both ways, and the exemplar→trace link on Prometheus) and the dashboard. |

## If a panel is empty

Check in this order: the relay printed its destinations at boot; the collector
received anything (uncomment the `debug` exporter in `otel-collector.yaml`);
metrics have had 60s. For the MCP row specifically, check that the agent
definition declares a server at all and that the agent actually called a tool —
`tools/list` alone produces no telemetry, because only `tools/call` is
instrumented. Missing exemplar dots are their own check: confirm Prometheus was
started with `--enable-feature=exemplar-storage`, then confirm the panel is one
of the MCP or policy ones, since the LLM metrics never carry them. Note the dashboard's metric names assume Prometheus's
OTLP naming (`gen_ai.client.operation.duration` becomes
`gen_ai_client_operation_duration_seconds`), which is what the
`otlp-write-receiver` path produces.

Prometheus 3.x renamed that flag from the 2.x `--enable-feature=otlp-write-receiver`
to `--web.enable-otlp-receiver`, and it ignores the old spelling instead of
refusing to start. The symptom is a healthy-looking Prometheus, a collector
logging `404` on `/api/v1/otlp/v1/metrics`, and an empty dashboard.
