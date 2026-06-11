{{/*
Redis URI for in-cluster Bitnami Redis (no auth). Matches https://docs.erpc.cloud/config/database/shared-state
*/}}
{{- define "erpc.redisSharedStateUri" -}}
redis://{{ .Release.Name }}-redis-master.{{ .Release.Namespace }}.svc.cluster.local:6379/?pool_size=10&dial_timeout=5s&read_timeout=1s&write_timeout=2s
{{- end }}

{{/*
Default evmJsonRpcCache: memory for hot paths, PostgreSQL for finalized archive (per https://docs.erpc.cloud/config/database/evm-json-rpc-cache).
Tuned for Ponder-style indexing: negative-cache empty eth_getLogs, unfinalized tip caching, tx-hash data in Postgres.
Requires POSTGRES_CACHE_URI in the upstream eRPC Secret (connectionUri uses env substitution in erpc).
Cap maxConns to avoid exhausting Postgres max_connections (SQLSTATE 53300); scale max_connections on CNPG if you add replicas.
*/}}
{{- define "erpc.defaultEvmJsonRpcCache" -}}
{{- $cache := .Values.erpc.database.evmJsonRpcCache | default dict }}
{{- $pg := $cache.postgresql | default dict }}
{{- $mem := $cache.memory | default dict }}
{{- $maxConns := default 20 $pg.maxConns }}
{{- $minConns := default 2 $pg.minConns }}
{{- $pgGetTimeout := default "2s" $pg.getTimeout }}
{{- $pgSetTimeout := default "5s" $pg.setTimeout }}
{{- $memMaxItems := default 200000 $mem.maxItems }}
{{- $memMaxTotalSize := default "1GB" $mem.maxTotalSize }}
connectors:
  - id: memory-cache
    driver: memory
    memory:
      maxItems: {{ $memMaxItems | int }}
      maxTotalSize: {{ $memMaxTotalSize | quote }}
    failsafeForGets:
      - matchMethod: "*"
        timeout:
          duration: 50ms
  - id: postgres-cache
    driver: postgresql
    postgresql:
      connectionUri: "${POSTGRES_CACHE_URI}"
      table: rpc_cache
      minConns: {{ $minConns | int }}
      maxConns: {{ $maxConns | int }}
      getTimeout: {{ $pgGetTimeout | quote }}
      setTimeout: {{ $pgSetTimeout | quote }}
    failsafeForGets:
      - matchMethod: "*"
        timeout:
          duration: 100ms
policies:
  # --- eth_getLogs: empty results only (negative cache for historical indexing) ---
  - network: "*"
    method: eth_getLogs
    finality: unfinalized
    empty: only          # cache [] only; non-empty logs never written
    connector: memory-cache
    ttl: 30s
  - network: "*"
    method: eth_getLogs
    finality: finalized
    empty: only          # historical empty ranges — forever in Postgres
    connector: postgres-cache
    ttl: 0

  # --- Realtime: safe methods only (no getBlockByNumber, no getLogs) ---
  - network: "*"
    method: "eth_getBlockByHash|eth_getBlockReceipts|eth_getTransactionByHash|eth_getTransactionReceipt|eth_call"
    finality: realtime
    empty: ignore
    connector: memory-cache
    ttl: 2s

  # --- Unfinalized: same allowlist ---
  - network: "*"
    method: "eth_getBlockByHash|eth_getBlockReceipts|eth_getTransactionByHash|eth_getTransactionReceipt|eth_call"
    finality: unfinalized
    empty: ignore
    connector: memory-cache
    ttl: 10s

  # --- Unknown finality (tx-hash keyed lookups) ---
  - network: "*"
    method: "eth_getTransactionByHash|eth_getTransactionReceipt"
    finality: unknown
    empty: ignore
    connector: postgres-cache
    ttl: 0

  # --- Finalized archive (still no getBlockByNumber, no non-empty getLogs) ---
  - network: "*"
    method: eth_call
    finality: finalized
    empty: allow           # keep if you want empty eth_call negative cache
    connector: postgres-cache
    ttl: 0
  - network: "*"
    method: "eth_getBlockByHash|eth_getBlockReceipts|eth_getTransactionByHash|eth_getTransactionReceipt"
    finality: finalized
    empty: ignore
    connector: postgres-cache
    ttl: 0
{{- end }}
