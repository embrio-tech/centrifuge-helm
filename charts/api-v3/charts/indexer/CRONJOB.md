# Indexer CronJob for Regular Restarts

This Helm chart includes a CronJob that automatically restarts the indexer deployment at regular intervals to ensure clean memory and a working setup.

## Configuration

The CronJob can be configured through the `values.yaml` file under the `cronjob` section:

```yaml
cronjob:
  enabled: true                    # Enable/disable the CronJob
  schedule: "0 */6 * * *"         # Cron schedule (every 6 hours by default)
  image:
    repository: bitnami/kubectl   # Container image for kubectl
    tag: "latest"
    pullPolicy: IfNotPresent
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi
  rolloutTimeout: "5m"            # Timeout for rollout status check
  successfulJobsHistoryLimit: 3   # Keep 3 successful job records
  failedJobsHistoryLimit: 1       # Keep 1 failed job record
```

## How It Works

1. The CronJob runs on the specified schedule
2. It uses `kubectl` to patch the deployment with a restart annotation
3. This triggers a rolling update of the deployment
4. The job waits for the rollout to complete before finishing
5. If the rollout fails, the job will fail and be retried according to the CronJob policy

## Benefits

- **Clean Memory**: Regular restarts prevent memory leaks
- **Fresh State**: Ensures the indexer starts with a clean state
- **Reliability**: Helps maintain a working setup over time
- **Automated**: No manual intervention required

## Monitoring

You can monitor the CronJob using:

```bash
# Check CronJob status
kubectl get cronjobs -n <namespace>

# View job history
kubectl get jobs -n <namespace> -l app.kubernetes.io/component=cronjob

# Check logs of the latest job
kubectl logs -n <namespace> -l app.kubernetes.io/component=cronjob --tail=50
```

## Customization

### Schedule Examples

- Every 6 hours: `"0 */6 * * *"`
- Every 12 hours: `"0 */12 * * *"`
- Daily at 2 AM: `"0 2 * * *"`
- Every 4 hours during business hours: `"0 9-17/4 * * *"`

### Disabling the CronJob

Set `cronjob.enabled: false` in your values file or override it during installation:

```bash
helm install my-indexer . --set cronjob.enabled=false
```

## Requirements

- The CronJob requires `kubectl` access to the cluster
- The service account running the CronJob needs permissions to patch deployments
- Ensure the deployment name matches the expected pattern
