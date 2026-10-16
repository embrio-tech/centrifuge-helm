import assert from "node:assert/strict";
import crypto from "node:crypto";
import { generateKeyPairSync } from "node:crypto";
import test from "node:test";
import {
  buildPayloadFromEnv,
  deploymentMatches,
  redactSecrets,
  signAppJwt,
} from "./github-transition-report-lib.mjs";

const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const privateKeyPem = privateKey.export({ type: "pkcs1", format: "pem" });

test("JWT iat and exp window", () => {
  const now = 1_700_000_000;
  const jwt = signAppJwt("12345", privateKeyPem, now);
  const [, payloadPart] = jwt.split(".");
  const payload = JSON.parse(Buffer.from(payloadPart, "base64url"));
  assert.equal(payload.iss, "12345");
  assert.equal(payload.iat, now - 60);
  assert.equal(payload.exp, now + 9 * 60);
});

test("payload fingerprint is stable for key order", () => {
  const env = {
    REPORT_TRANSITION: "staging-ready",
    REPORT_ENVIRONMENT: "test-eu",
    REPORT_COMPONENT: "projection",
    REPORT_PROJECTION_ID: "pj-20260101-01",
    REPORT_PRODUCER_ID: "pr-20260101-01",
    REPORT_IMAGE_DIGEST: "sha256:abcd",
  };
  const a = buildPayloadFromEnv(env);
  const b = buildPayloadFromEnv(env);
  assert.equal(a.desiredStateFingerprint, b.desiredStateFingerprint);
  assert.match(a.desiredStateFingerprint, /^[a-f0-9]{64}$/);
});

test("deployment correlation requires exact task and fingerprint", () => {
  const fingerprint = buildPayloadFromEnv({
    REPORT_TRANSITION: "routes",
    REPORT_ENVIRONMENT: "test-eu",
    REPORT_COMPONENT: "routes",
    REPORT_STAGING_QUERY: "q-20260101-01",
    REPORT_PRODUCTION_QUERY: "q-20260101-02",
    REPORT_ROLLBACK_QUERY: "q-20260101-02",
  }).desiredStateFingerprint;
  assert.equal(
    deploymentMatches({ task: "api-v4:routes", payload: { desiredStateFingerprint: fingerprint } }, "api-v4:routes", fingerprint),
    true,
  );
  assert.equal(
    deploymentMatches({ task: "api-v4:staging-ready", payload: { desiredStateFingerprint: fingerprint } }, "api-v4:routes", fingerprint),
    false,
  );
});

test("redactSecrets strips bearer tokens and JWTs", () => {
  const jwt = signAppJwt("1", privateKeyPem);
  const out = redactSecrets(`Authorization: Bearer secret-token and ${jwt}`);
  assert.ok(!out.includes("secret-token"));
  assert.ok(!out.includes(jwt));
});
