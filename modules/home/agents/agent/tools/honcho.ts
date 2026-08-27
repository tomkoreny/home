// Honcho memory bridge: read/write the same self-hosted Honcho instance the
// homelab hermes-agent uses (workspace `hermes`), so OMP shares its memory.
//
// Server: honcho 3.0.6 in the proxmox-lab cluster, exposed VPN-only at
// https://honcho.home.tomkoreny.com (auth disabled upstream; the network is
// the boundary — see apps/services/honcho/README.md in homelab-services).
//
// Peer model: `user` is Tom (hermes' peerName), `hermes` is the assistant,
// and OMP writes as its own peer `omp` so provenance stays per-agent while
// everyone shares one representation of the user.
//
// Endpoints and request shapes are pinned against the live 3.0.6 OpenAPI
// spec. Semantic search and dialectic chat require the server's LLM key to
// have quota; the stored card/representation/conclusion reads do not.
import type { CustomToolFactory } from "@oh-my-pi/pi-coding-agent";

const BASE = (process.env.HONCHO_URL ?? "https://honcho.home.tomkoreny.com").replace(/\/+$/, "");
const WORKSPACE = process.env.HONCHO_WORKSPACE ?? "hermes";
const USER_PEER = "user";
const AGENT_PEER = "omp";

interface HonchoError {
	detail?: string;
}

async function api<T>(path: string, body: unknown, signal?: AbortSignal, method = "POST"): Promise<T> {
	const res = await fetch(`${BASE}/v3/workspaces/${WORKSPACE}${path}`, {
		method,
		headers: { "Content-Type": "application/json" },
		body: method === "GET" ? undefined : JSON.stringify(body ?? {}),
		signal,
	});
	const text = await res.text();
	let parsed: unknown;
	try {
		parsed = text ? JSON.parse(text) : {};
	} catch {
		parsed = { detail: text };
	}
	if (!res.ok) {
		const detail = (parsed as HonchoError).detail ?? text ?? res.statusText;
		throw new Error(`honcho ${method} ${path} -> ${res.status}: ${detail}`);
	}
	return parsed as T;
}

function text(t: string) {
	return { content: [{ type: "text" as const, text: t }] };
}

let agentPeerEnsured = false;
async function ensureAgentPeer(signal?: AbortSignal): Promise<void> {
	if (agentPeerEnsured) return;
	// POST /peers is get-or-create.
	await api("/peers", { id: AGENT_PEER, metadata: { kind: "coding-agent" } }, signal);
	agentPeerEnsured = true;
}

const factory: CustomToolFactory = (pi) => [
	{
		name: "honcho_user",
		label: "Honcho User Memory",
		description:
			"Read the shared long-term memory about the user (Tom) from the Honcho instance the hermes assistant uses: the peer card (key facts) and a peer's accumulated representation (explicit and inductive observations). Cheap, no LLM involved. Use at the start of tasks where user preferences matter.",
		parameters: pi.zod.object({
			observer: pi.zod
				.string()
				.optional()
				.describe("Whose view of the user to read: 'hermes' (default, richest) or 'omp'"),
		}),
		async execute(_id, params, _onUpdate, _ctx, signal) {
			const observer = params.observer ?? "hermes";
			const [card, rep] = await Promise.all([
				api<{ peer_card?: string[] | null }>(`/peers/${USER_PEER}/card`, undefined, signal, "GET"),
				api<{ representation?: string }>(`/peers/${observer}/representation`, { target: USER_PEER }, signal),
			]);
			const cardText = card.peer_card?.length ? card.peer_card.map((line) => `- ${line}`).join("\n") : "(no peer card)";
			const repText = rep.representation ?? "(no representation)";
			return {
				...text(`## Peer card (${USER_PEER})\n${cardText}\n\n## ${observer}'s representation of ${USER_PEER}\n${repText}`),
				details: { observer, cardLines: card.peer_card?.length ?? 0 },
			};
		},
	},
	{
		name: "honcho_search",
		label: "Honcho Search",
		description:
			"Semantic search over messages stored in the shared hermes memory workspace. Requires the Honcho server's embedding provider to be up; errors surface as-is.",
		parameters: pi.zod.object({
			query: pi.zod.string().describe("Natural-language search query"),
			limit: pi.zod.number().int().min(1).max(100).optional().describe("Max results (default 10)"),
		}),
		async execute(_id, params, _onUpdate, _ctx, signal) {
			type Hit = { content: string; peer_id?: string; created_at?: string };
			// 3.0.6 returns a bare array; tolerate a paginated {items} shape too.
			const page = await api<Hit[] | { items?: Hit[] }>(
				"/search",
				{ query: params.query, limit: params.limit ?? 10 },
				signal,
			);
			const items = Array.isArray(page) ? page : (page.items ?? []);
			if (items.length === 0) return { ...text("No results."), details: { count: 0 } };
			const lines = items.map((m) => `- [${m.peer_id ?? "?"} ${m.created_at ?? ""}] ${m.content}`);
			return { ...text(lines.join("\n")), details: { count: items.length } };
		},
	},
	{
		name: "honcho_ask",
		label: "Honcho Ask",
		description:
			"Ask Honcho's dialectic model a question about the user, answered from accumulated memory (e.g. 'what stack does the user prefer for X?'). Costs an LLM call on the server; requires its LLM key to have quota.",
		parameters: pi.zod.object({
			query: pi.zod.string().max(10000).describe("Question about the user"),
			observer: pi.zod.string().optional().describe("Perspective peer (default 'hermes')"),
			reasoning: pi.zod.enum(["minimal", "low", "medium", "high", "max"]).optional().describe("Server-side reasoning level (default 'low')"),
		}),
		async execute(_id, params, _onUpdate, _ctx, signal) {
			const observer = params.observer ?? "hermes";
			const res = await api<{ content?: string } | string>(
				`/peers/${observer}/chat`,
				{ query: params.query, target: USER_PEER, reasoning_level: params.reasoning ?? "low" },
				signal,
			);
			const answer = typeof res === "string" ? res : (res.content ?? JSON.stringify(res));
			return { ...text(answer), details: { observer } };
		},
	},
	{
		name: "honcho_conclusions",
		label: "Honcho Conclusions",
		description:
			"List stored conclusions about the user from the shared memory (facts hermes or omp have concluded). Without a query this is a plain list and needs no LLM; with a query it is a semantic search and requires server embedding quota.",
		parameters: pi.zod.object({
			query: pi.zod.string().optional().describe("Optional semantic query; omit to list newest"),
			observer: pi.zod.string().optional().describe("Filter by concluding peer (default 'hermes')"),
			limit: pi.zod.number().int().min(1).max(100).optional().describe("Max results (default 20)"),
		}),
		async execute(_id, params, _onUpdate, _ctx, signal) {
			const observer = params.observer ?? "hermes";
			const filters = { observer, observed: USER_PEER };
			let items: Array<{ content: string; created_at?: string }>;
			if (params.query) {
				const res = await api<Array<{ content: string; created_at?: string }> | { items?: Array<{ content: string; created_at?: string }> }>(
					"/conclusions/query",
					{ query: params.query, top_k: params.limit ?? 20, filters },
					signal,
				);
				items = Array.isArray(res) ? res : (res.items ?? []);
			} else {
				const res = await api<{ items?: Array<{ content: string; created_at?: string }> }>(
					"/conclusions/list",
					{ filters },
					signal,
				);
				items = (res.items ?? []).slice(0, params.limit ?? 20);
			}
			if (items.length === 0) return { ...text("No conclusions."), details: { count: 0 } };
			return {
				...text(items.map((c) => `- ${c.content}`).join("\n")),
				details: { count: items.length, observer },
			};
		},
	},
	{
		name: "honcho_conclude",
		label: "Honcho Conclude",
		description:
			"Write a durable conclusion about the user into the shared memory, as peer 'omp'. Use sparingly for real, durable preferences or facts surfaced in this session — not task narration.",
		parameters: pi.zod.object({
			content: pi.zod.string().min(1).max(2000).describe("One conclusion about the user, standalone and durable"),
		}),
		async execute(_id, params, _onUpdate, _ctx, signal) {
			await ensureAgentPeer(signal);
			await api(
				"/conclusions",
				{ conclusions: [{ content: params.content, observer_id: AGENT_PEER, observed_id: USER_PEER }] },
				signal,
			);
			return { ...text(`Stored conclusion as ${AGENT_PEER}: ${params.content}`), details: { observer: AGENT_PEER } };
		},
	},
];

export default factory;
