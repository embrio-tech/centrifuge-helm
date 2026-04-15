{{/*
Redis URI for in-cluster Bitnami Redis (no auth). Matches https://docs.erpc.cloud/config/database/shared-state
*/}}
{{- define "erpc.redisSharedStateUri" -}}
redis://{{ .Release.Name }}-redis-master.{{ .Release.Namespace }}.svc.cluster.local:6379/?pool_size=10&dial_timeout=5s&read_timeout=1s&write_timeout=2s
{{- end }}

{{/*
Default evmJsonRpcCache: memory for hot paths, PostgreSQL for finalized (per https://docs.erpc.cloud/config/database/evm-json-rpc-cache).
Requires POSTGRES_CACHE_URI in the upstream eRPC Secret (connectionUri uses env substitution in erpc).
Cap maxConns to avoid exhausting Postgres max_connections (SQLSTATE 53300); scale max_connections on CNPG if you add replicas.
*/}}
{{- define "erpc.defaultEvmJsonRpcCache" -}}
{{- $pg := .Values.erpc.database.evmJsonRpcCache.postgresql | default dict }}
{{- $maxConns := default 20 $pg.maxConns }}
{{- $minConns := default 2 $pg.minConns }}
connectors:
  - id: memory-cache
    driver: memory
    memory:
      maxItems: 100000
  - id: postgres-cache
    driver: postgresql
    postgresql:
      connectionUri: "${POSTGRES_CACHE_URI}"
      table: rpc_cache
      minConns: {{ $minConns | int }}
      maxConns: {{ $maxConns | int }}
policies:
  - network: "*"
    method: "*"
    finality: realtime
    empty: ignore
    connector: memory-cache
    ttl: 2s
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
    connector: memory-cache
    ttl: 0
  - network: "*"
    method: "*"
    finality: finalized
    empty: allow
    connector: postgres-cache
    ttl: 0
{{- end }}
