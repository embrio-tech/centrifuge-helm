/**
 * Shared logic for GitHub transition reporting (unit-tested).
 */

import crypto from "node:crypto";

export const API = "https://api.github.com";
export const OWNER = "centrifuge";
export const REPO = "api-v4-gitops";

export function base64url(input) {
  return Buffer.from(input)
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

export function signAppJwt(appId, privateKeyPem, nowSeconds = Math.floor(Date.now() / 1000)) {
  const header = { alg: "RS256", typ: "JWT" };
  const payload = { iat: nowSeconds - 60, exp: nowSeconds + 9 * 60, iss: appId };
  const encoded = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(payload))}`;
  const signer = crypto.createSign("RSA-SHA256");
  signer.update(encoded);
  return `${encoded}.${base64url(signer.sign(privateKeyPem))}`;
}

export function buildPayloadFromEnv(env) {
  function optional(name) {
    const value = env[name];
    return value === undefined || value === "" ? undefined : value;
  }
  function required(name) {
    const value = env[name];
    if (!value) {
      throw new Error(`missing ${name}`);
    }
    return value;
  }
  const payload = {
    schemaVersion: 1,
    transition: required("REPORT_TRANSITION"),
    environment: required("REPORT_ENVIRONMENT"),
    component: required("REPORT_COMPONENT"),
  };
  for (const [envName, key] of [
    ["REPORT_PRODUCER_ID", "producerId"],
    ["REPORT_PROJECTION_ID", "projectionId"],
    ["REPORT_QUERY_ID", "queryId"],
    ["REPORT_SOURCE_COMMIT", "sourceCommit"],
    ["REPORT_IMAGE_DIGEST", "imageDigest"],
    ["REPORT_CHART_NAME", "chartName"],
    ["REPORT_CHART_VERSION", "chartVersion"],
    ["REPORT_CHART_DIGEST", "chartDigest"],
    ["REPORT_OPERATION_ID", "operationId"],
    ["REPORT_ACTIVATION_COMMAND", "activationCommand"],
  ]) {
    const value = optional(envName);
    if (value !== undefined) {
      payload[key] = value;
    }
  }
  if (payload.transition === "routes") {
    const routesInput = {
      stagingQuery: required("REPORT_STAGING_QUERY"),
      productionQuery: required("REPORT_PRODUCTION_QUERY"),
      rollbackQuery: required("REPORT_ROLLBACK_QUERY"),
    };
    payload.routesFingerprint = crypto
      .createHash("sha256")
      .update(JSON.stringify(routesInput, Object.keys(routesInput).sort()))
      .digest("hex");
  }
  const fingerprintInput = { ...payload };
  delete fingerprintInput.schemaVersion;
  payload.desiredStateFingerprint = crypto
    .createHash("sha256")
    .update(JSON.stringify(fingerprintInput, Object.keys(fingerprintInput).sort()))
    .digest("hex");
  return payload;
}

export function parseDeploymentPayload(raw) {
  if (raw === null || raw === undefined || raw === "") {
    return null;
  }
  if (typeof raw === "object") {
    return raw;
  }
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

export function deploymentMatches(deployment, task, fingerprint) {
  if (deployment.task !== task) {
    return false;
  }
  const parsed = parseDeploymentPayload(deployment.payload);
  return parsed?.desiredStateFingerprint === fingerprint;
}

const REPORT_STATES = new Set(["success", "failure", "in_progress"]);

/**
 * GitHub deployment status state this reporter is allowed to post.
 *
 * @param {string} state
 */
export function assertReportState(state) {
  if (!REPORT_STATES.has(state)) {
    throw new Error(`invalid REPORT_STATE: ${state}`);
  }
}

/**
 * Short status line. GitHub rejects a description longer than 140 characters.
 *
 * @param {string} transition
 * @param {string} component
 * @param {string} state
 */
export function statusDescription(transition, component, state) {
  const description = `${transition} ${component} ${state}`;
  if (description.length > 140) {
    throw new Error(`status description exceeds 140 characters`);
  }
  return description;
}

/**
 * True when this state and description were already posted on the deployment.
 *
 * @param {Array<{ state?: string, description?: string }> | null | undefined} statuses
 * @param {string} state
 * @param {string} description
 */
export function statusAlreadyPosted(statuses, state, description) {
  return (
    Array.isArray(statuses) &&
    statuses.some((item) => item.state === state && item.description === description)
  );
}

export function redactSecrets(text) {
  return text
    .replace(/Bearer [^\s]+/gi, "Bearer [redacted]")
    .replace(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, "[jwt-redacted]");
}

export function isTransientGitHubError(message) {
  return /GitHub (GET|POST).* (429|5\d\d):/.test(message) || message.includes("fetch failed");
}
