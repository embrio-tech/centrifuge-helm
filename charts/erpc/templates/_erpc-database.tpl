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
  - network: "*"
    method: "*"
    finality: realtime
    empty: ignore
    connector: memory-cache
    ttl: 2s
  - network: "*"
    method: eth_getLogs
    finality: unfinalized
    empty: allow
    connector: memory-cache
    ttl: 30s
  - network: "*"
    method: "*"
    finality: unfinalized
    empty: ignore
    connector: memory-cache
    ttl: 10s
  - network: "*"
    method: "*"
    finality: unknown
    empty: ignore
    connector: postgres-cache
    ttl: 0
  - network: "*"
    method: eth_getLogs
    finality: finalized
    empty: allow
    connector: postgres-cache
    ttl: 0
  - network: "*"
    method: eth_call
    finality: finalized
    empty: allow
    connector: postgres-cache
    ttl: 0
  - network: "*"
    method: eth_getBlockByNumber
    finality: finalized
    empty: ignore
    connector: postgres-cache
    ttl: 0
  - network: "*"
    method: "*"
    finality: finalized
    empty: ignore
    connector: postgres-cache
    ttl: 0
{{- end }}
