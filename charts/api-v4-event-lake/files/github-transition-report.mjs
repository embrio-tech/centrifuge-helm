/**
 * Report API v4 environment transitions to GitHub Deployments (embrio-tech-argocd).
 * Exits 0 even when GitHub is unavailable so Argo sync is not blocked.
 */

import { readFile } from "node:fs/promises";
import {
  API,
  OWNER,
  REPO,
  assertReportState,
  buildPayloadFromEnv,
  deploymentMatches,
  isTransientGitHubError,
  redactSecrets,
  signAppJwt,
  statusAlreadyPosted,
  statusDescription,
} from "./github-transition-report-lib.mjs";

function log(level, message) {
  process.stderr.write(`${level}: ${redactSecrets(message)}\n`);
}

function requiredEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`missing ${name}`);
  }
  return value;
}

function optionalEnv(name) {
  const value = process.env[name];
  return value === undefined || value === "" ? undefined : value;
}

async function ghFetch(path, { method = "GET", token, body } = {}) {
  const response = await fetch(`${API}${path}`, {
    method,
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "X-GitHub-Api-Version": "2022-11-28",
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`GitHub ${method} ${path} ${response.status}: ${text.slice(0, 300)}`);
  }
  if (response.status === 204) {
    return null;
  }
  return response.json();
}

async function installationToken(appId, installationId, privateKeyPem) {
  const jwt = signAppJwt(appId, privateKeyPem);
  const data = await ghFetch(`/app/installations/${installationId}/access_tokens`, {
    method: "POST",
    token: jwt,
    body: {
      repositories: [REPO],
      permissions: { contents: "read", deployments: "write", metadata: "read" },
    },
  });
  return data.token;
}

async function main() {
  const state = requiredEnv("REPORT_STATE");
  assertReportState(state);
  const task = requiredEnv("REPORT_TASK");
  const payload = buildPayloadFromEnv(process.env);
  const environment = payload.environment;
  const productionEnvironment = requiredEnv("REPORT_PRODUCTION_ENVIRONMENT") === "true";

  const appId = requiredEnv("GITHUB_APP_ID");
  const installationId = requiredEnv("GITHUB_INSTALLATION_ID");
  const keyPath = requiredEnv("GITHUB_PRIVATE_KEY_PATH");
  const privateKeyPem = await readFile(keyPath, "utf8");

  const token = await installationToken(appId, installationId, privateKeyPem);
  const refData = await ghFetch(`/repos/${OWNER}/${REPO}/git/ref/heads/main`, { token });
  const ref = refData.object.sha;

  const deployments = await ghFetch(
    `/repos/${OWNER}/${REPO}/deployments?environment=${encodeURIComponent(environment)}&ref=${ref}&per_page=30`,
    { token },
  );

  let deployment = Array.isArray(deployments)
    ? deployments.find((item) => deploymentMatches(item, task, payload.desiredStateFingerprint))
    : undefined;

  if (!deployment) {
    deployment = await ghFetch(`/repos/${OWNER}/${REPO}/deployments`, {
      method: "POST",
      token,
      body: {
        ref,
        task,
        environment,
        description: `${task} ${payload.transition} ${payload.component} ${payload.desiredStateFingerprint.slice(0, 12)}`,
        payload,
        auto_merge: false,
        required_contexts: [],
        production_environment: productionEnvironment,
        transient_environment: false,
      },
    });
  }

  const logUrl = optionalEnv("REPORT_LOG_URL");
  const environmentUrl = optionalEnv("REPORT_ENVIRONMENT_URL");
  const description = statusDescription(payload.transition, payload.component, state);

  const statuses = await ghFetch(
    `/repos/${OWNER}/${REPO}/deployments/${deployment.id}/statuses?per_page=5`,
    { token },
  );
  const duplicate = statusAlreadyPosted(statuses, state, description);
  if (!duplicate) {
    await ghFetch(`/repos/${OWNER}/${REPO}/deployments/${deployment.id}/statuses`, {
      method: "POST",
      token,
      body: {
        state,
        description,
        environment,
        ...(logUrl ? { log_url: logUrl } : {}),
        ...(environmentUrl ? { environment_url: environmentUrl } : {}),
        auto_inactive: false,
      },
    });
  }
}

const maxAttempts = 3;
for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
  try {
    await main();
    process.exit(0);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const transient = isTransientGitHubError(message);
    log("warn", `transition report attempt ${attempt}/${maxAttempts} failed: ${message}`);
    if (!transient || attempt === maxAttempts) {
      process.exit(0);
    }
    await new Promise((resolve) => setTimeout(resolve, attempt * 2000));
  }
}
