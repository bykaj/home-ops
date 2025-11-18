# VolSync - Persistent Volume Backup and Replication
> [!NOTE]
> Original by [@QNimbus](https://github.com/QNimbus) can be found [here](https://github.com/QNimbus/home-ops/blob/main/kubernetes/apps/volsync-system/volsync/README.md).

This directory contains the VolSync configuration for automated backup and replication of persistent volumes in the Kubernetes cluster. VolSync works in conjunction with Rook Ceph and OpenEBS to provide a comprehensive persistent storage and backup solution.

## Overview

VolSync is a Kubernetes operator that enables backup, restore, and migration of persistent volumes using various backends. In this cluster, it's configured to work with:

- **Rook Ceph**: Primary distributed block storage with replication
- **OpenEBS**: Local path provisioner for cache and temporary storage
- **NFS Server**: External backup destination for long-term data retention

## Quick Reference

### New Application Deployment Checklist

1. **Deploy application** with VolSync component
2. **Verify PVC is bound** and application starts
3. **Immediately trigger manual backup**:
   ```bash
   kubectl patch replicationsource <app-name> -n <namespace> \
     --type='merge' \
     -p='{"spec":{"trigger":{"manual":"initial-'$(date +%s)'"}}}'
   ```
4. **Wait for backup completion**:
   ```bash
   kubectl get replicationsource <app-name> -n <namespace> \
     -o jsonpath='{.status.latestMoverStatus.logs}'
   ```
5. **Verify backup exists**:
   ```bash
   # Should show snapshot files, not empty directory
   kubectl run verify-backup --rm -i --image=busybox --restart=Never \
     --overrides='{"spec":{"volumes":[{"name":"repo","nfs":{"server":"truenas.lan.home.vwn.io","path":"/mnt/vault/cluster/volsync"}}],"containers":[{"name":"verify","image":"busybox","command":["ls","-la","/repository/<app-name>/snapshots/"],"volumeMounts":[{"name":"repo","mountPath":"/repository"}]}]}}' \
     -n <namespace>
   ```

✅ **Application is now safe for removal/restoration operations**

### Bootstrap Window Emergency Recovery

If you need to restore an application that was removed during the bootstrap window:

1. **Accept that data is lost** (no backup exists)
2. **Deploy application normally** (will start with empty PVC)
3. **Restore application state manually** from external sources if needed
4. **Trigger immediate backup** to prevent future bootstrap window issues

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Rook Ceph     │    │    OpenEBS      │    │   NFS Server    │
│ (Primary PVs)   │    │  (Cache PVs)    │    │   (Backups)     │
│                 │    │                 │    │                 │
│ • Replicated    │    │ • Local storage │    │ • Long-term     │
│ • Snapshotable  │    │ • Fast cache    │    │ • Off-cluster   │
│ • High perf     │    │ • Temporary     │    │ • Disaster rec  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │     VolSync     │
                    │                 │
                    │ • Restic backend│
                    │ • Scheduled     │
                    │ • Incremental   │
                    │ • Encrypted     │
                    └─────────────────┘
```

## Components

### VolSync Operator

The main operator consists of:
- **Source Controller**: Manages backup sources (ReplicationSource)
- **Destination Controller**: Manages restore destinations (ReplicationDestination)
- **Restic Mover**: Handles backup/restore operations using Restic

### Storage Integration

1. **Primary Storage (Rook Ceph)**:
   - Provides persistent volumes for applications
   - Creates volume snapshots for consistent backups
   - Storage class: `ceph-block`
   - Snapshot class: `csi-ceph-blockpool`

2. **Cache Storage (OpenEBS)**:
   - Provides local storage for Restic cache
   - Improves backup performance with local caching
   - Storage class: `openebs-hostpath`

3. **Backup Destination (NFS)**:
   - External NFS server for backup repositories
   - Location: `/mnt/vault/Backups/Cluster/main/volsync`
   - Provides off-cluster disaster recovery

## Mutating Admission Policies

This cluster uses Kubernetes Mutating Admission Policies to automatically enhance VolSync jobs. These policies are critical for proper operation and provide several benefits:

### 1. VolSync Mover Jitter Policy (`volsync-mover-jitter`)

**Purpose**: Prevents backup stampede by adding random jitter to job execution.

**How it works**:
- Matches VolSync source jobs (prefix: `volsync-src-`)
- Injects an init container that sleeps for 1-120 random seconds
- Spreads backup execution across time to reduce resource contention

**Why it's required**:
- Multiple applications backing up simultaneously can overwhelm storage I/O
- Prevents resource conflicts during scheduled backup windows
- Improves overall cluster stability during backup operations

```yaml
# Adds random jitter init container to VolSync source jobs
initContainers:
- name: jitter
  image: ghcr.io/home-operations/busybox:1.37.0
  command: ["sh", "-c", "SLEEP_TIME=$(shuf -i 1-120 -n 1); echo \"Sleeping for $SLEEP_TIME seconds\"; sleep $SLEEP_TIME"]
```

### 2. VolSync Mover NFS Policy (`volsync-mover-nfs`)

**Purpose**: Automatically mounts NFS backup repository for jobs that don't have it configured.

**How it works**:
- Matches VolSync jobs without existing "repository" volume
- Injects NFS volume mount pointing to backup server
- Ensures all backup jobs have access to the repository

**Why it's required**:
- Eliminates need to manually configure NFS mounts in every ReplicationSource
- Provides consistent backup destination across all applications
- Simplifies backup configuration and reduces configuration drift

```yaml
# Automatically adds NFS repository volume and mount
volumeMounts:
- name: repository
  mountPath: /repository
volumes:
- name: repository
  nfs:
    server: "${NAS_HOST}"
    path: "/mnt/vault/cluster/volsync"
```

### Policy Benefits

1. **Automation**: Reduces manual configuration requirements
2. **Consistency**: Ensures all backup jobs follow the same patterns
3. **Reliability**: Prevents common configuration errors
4. **Performance**: Optimizes backup scheduling and resource usage
5. **Maintainability**: Centralizes backup infrastructure configuration

## Configuration Structure

```
volsync/
├── README.md                   # This documentation
├── ks.yaml                     # Flux Kustomization
└── app/
    ├── kustomization.yaml      # Kustomize configuration
    ├── helmrelease.yaml        # VolSync operator deployment
    └── mutatingadmissionpolicy.yaml  # Admission policies for automation
```

## How Applications Use VolSync

Applications can use VolSync by including the VolSync component in their Kustomization:

### 1. Include the Component

```yaml
# In app/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
components:
  - ../../../components/volsync
```

### 2. Configure Environment Variables

```yaml
# In app/kustomization.yaml
configurations:
  - ../../components/common/kustomization.yaml
configMapGenerator:
  - name: volsync-env
    literals:
      - APP=my-app
      - VOLSYNC_CLAIM=my-app-data
      - VOLSYNC_CACHE_CAPACITY=5Gi
      - VOLSYNC_UID=1000
      - VOLSYNC_GID=1000
```

### 3. Automatic Resources Created

The component automatically creates:
- **ExternalSecret**: Retrieves Restic repository credentials from 1Password
- **ReplicationSource**: Configures backup schedule and retention
- **PVC**: Creates cache volume for Restic operations

## Default Backup Configuration

- **Schedule**: Hourly backups (`0 * * * *`)
- **Retention**:
  - Hourly: 24 snapshots
  - Daily: 7 snapshots
- **Prune**: Every 7 days
- **Method**: Snapshot-based for consistency
- **Encryption**: All backups encrypted with Restic

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `APP` | (required) | Application name for backup repository |
| `VOLSYNC_CLAIM` | `${APP}` | PVC name to backup |
| `VOLSYNC_CACHE_CAPACITY` | `5Gi` | Cache volume size |
| `VOLSYNC_CACHE_ACCESSMODES` | `ReadWriteOnce` | Cache volume access mode |
| `VOLSYNC_STORAGECLASS` | `ceph-block` | Primary storage class |
| `VOLSYNC_SNAPSHOTCLASS` | `csi-ceph-blockpool` | Snapshot class |
| `VOLSYNC_CACHE_SNAPSHOTCLASS` | `openebs-hostpath` | Cache storage class |
| `VOLSYNC_COPYMETHOD` | `Snapshot` | Backup method |
| `VOLSYNC_UID` | `4000` | User ID for mover pod |
| `VOLSYNC_GID` | `4000` | Group ID for mover pod |

## Monitoring and Troubleshooting

### Manual Backup Operations

Sometimes you may need to trigger a backup manually outside of the regular schedule. This is useful for testing, before maintenance windows, or when you need an immediate backup before making changes.

#### Trigger Manual Backup

To manually trigger a backup for any application using VolSync:

```bash
# Trigger manual backup (replace 'app-name' and 'namespace' with actual values)
kubectl patch replicationsource <app-name> -n <namespace> \
  --type='merge' \
  -p='{"spec":{"trigger":{"manual":"sync-'$(date +%s)'"}}}'

# Example: Trigger backup for pgadmin-config in tools namespace
kubectl patch replicationsource pgadmin-config -n tools \
  --type='merge' \
  -p='{"spec":{"trigger":{"manual":"sync-'$(date +%s)'"}}}'
```

The manual trigger uses a timestamp to ensure uniqueness. Each manual trigger creates a new backup job.

#### Check Manual Backup Progress

After triggering a manual backup, monitor its progress:

```bash
# Check ReplicationSource status
kubectl get replicationsource <app-name> -n <namespace> -o yaml

# Look for the lastManualSync field in status
kubectl get replicationsource <app-name> -n <namespace> \
  -o jsonpath='{.status.lastManualSync}'

# Check if backup job is running
kubectl get jobs -n <namespace> | grep volsync-src-<app-name>

# Monitor job progress in real-time
kubectl get jobs -n <namespace> -w | grep volsync-src-<app-name>
```

#### Check Backup Job Status and Logs

To see detailed information about the backup operation:

```bash
# Get job details
kubectl describe job volsync-src-<app-name>-<timestamp> -n <namespace>

# View backup job logs
kubectl logs job/volsync-src-<app-name>-<timestamp> -n <namespace>

# Follow logs in real-time (if job is still running)
kubectl logs job/volsync-src-<app-name>-<timestamp> -n <namespace> -f

# Check all containers in the job (including init containers)
kubectl logs job/volsync-src-<app-name>-<timestamp> -n <namespace> --all-containers=true
```

#### Verify Backup Completion

Check that the backup completed successfully:

```bash
# Check ReplicationSource conditions
kubectl get replicationsource <app-name> -n <namespace> \
  -o jsonpath='{.status.conditions}' | jq '.'

# Look for "Synchronization completed successfully" message
kubectl describe replicationsource <app-name> -n <namespace>

# Check last sync time
kubectl get replicationsource <app-name> -n <namespace> \
  -o jsonpath='{.status.lastSyncTime}'

# Verify backup completed without errors
kubectl get events -n <namespace> --field-selector type=Normal | grep <app-name>
```

#### Troubleshooting Manual Backups

Common issues and solutions:

1. **Manual trigger not working**:
   ```bash
   # Check if ReplicationSource exists
   kubectl get replicationsource <app-name> -n <namespace>

   # Verify the patch was applied
   kubectl get replicationsource <app-name> -n <namespace> \
     -o jsonpath='{.spec.trigger.manual}'
   ```

2. **Job not starting**:
   ```bash
   # Check VolSync controller logs
   kubectl logs deployment/volsync -n volsync-system

   # Look for admission policy issues
   kubectl get events -n <namespace> --field-selector type=Warning
   ```

3. **Backup job failing**:
   ```bash
   # Check job status and conditions
   kubectl describe job volsync-src-<app-name>-<timestamp> -n <namespace>

   # Verify NFS connectivity (if using NFS backend)
   kubectl get pods -n <namespace> | grep volsync
   kubectl exec -it <volsync-pod> -n <namespace> -- df -h /repository
   ```

4. **Bootstrap Window Restoration Failure**:

   **Symptom**: Restoration says "No eligible snapshots found" for a previously working application

   **Cause**: Application was removed during bootstrap window (before first backup completed)

   **Solution**:
   ```bash
   # Check if backup repository is empty
   kubectl apply -f - <<EOF
   apiVersion: v1
   kind: Pod
   metadata:
     name: debug-repo
     namespace: <namespace>
   spec:
     containers:
     - name: debug
       image: busybox
       command: ["sleep", "300"]
       volumeMounts:
       - name: repository
         mountPath: /repository
     volumes:
     - name: repository
       nfs:
         server: truenas.lan.home.vwn.io
         path: /mnt/vault/cluster/volsync
     restartPolicy: Never
   EOF

   # Check if snapshots directory is empty
   kubectl exec debug-repo -n <namespace> -- ls -la /repository/<app-name>/snapshots/

   # If empty, this confirms bootstrap window issue
   # Solution: Let application start with empty PVC and wait for first backup
   kubectl delete pod debug-repo -n <namespace>
   ```

   **Prevention**: Always trigger manual backup immediately after new deployments

### Browse PVC Contents with Read-Only Mount

Sometimes you need to inspect the contents of a PVC without risking any modifications. You can create an ephemeral pod that mounts the PVC in read-only mode:

#### Method 1: Direct PVC Mount (Read-Only)

```yaml
# Create a temporary pod to browse PVC contents
apiVersion: v1
kind: Pod
metadata:
  name: pvc-browser
  namespace: <namespace>
spec:
  containers:
  - name: browser
    image: busybox:1.36
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /data
      readOnly: true  # Mount as read-only
    securityContext:
      runAsUser: 1000
      runAsGroup: 1000
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: <pvc-name>
      readOnly: true  # PVC mounted read-only
  restartPolicy: Never
```

Apply and use:
```bash
# Apply the pod configuration
kubectl apply -f pvc-browser-pod.yaml

# Wait for pod to be ready
kubectl wait --for=condition=Ready pod/pvc-browser -n <namespace>

# Browse the PVC contents
kubectl exec -it pvc-browser -n <namespace> -- sh

# Inside the pod, explore the data
ls -la /data/
find /data -type f -name "*.log" | head -10
du -sh /data/*
```

#### Method 2: Snapshot-Based Browsing

For even safer inspection, create a snapshot first and mount that:

```bash
# Create a volume snapshot
kubectl create -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: <app-name>-browse-snapshot
  namespace: <namespace>
spec:
  source:
    persistentVolumeClaimName: <pvc-name>
  volumeSnapshotClassName: csi-ceph-blockpool
EOF

# Wait for snapshot to be ready
kubectl wait --for=condition=ReadyToUse volumesnapshot/<app-name>-browse-snapshot -n <namespace>

# Create PVC from snapshot
kubectl create -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <app-name>-browse-pvc
  namespace: <namespace>
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-block
  resources:
    requests:
      storage: <size>  # Same size as original or larger
  dataSource:
    name: <app-name>-browse-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
EOF

# Mount the snapshot-based PVC (read-only for safety)
kubectl create -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: snapshot-browser
  namespace: <namespace>
spec:
  containers:
  - name: browser
    image: busybox:1.36
    command: ["sleep", "3600"]
    volumeMounts:
    - name: snapshot-data
      mountPath: /data
      readOnly: true
  volumes:
  - name: snapshot-data
    persistentVolumeClaim:
      claimName: <app-name>-browse-pvc
      readOnly: true
  restartPolicy: Never
EOF
```

#### Method 3: One-liner for Quick Inspection

For quick data inspection without creating YAML files:

```bash
# Create ephemeral pod with read-only PVC mount
kubectl run pvc-browser \
  --image=busybox:1.36 \
  --rm -it \
  --restart=Never \
  --namespace=<namespace> \
  --overrides='
{
  "spec": {
    "containers": [{
      "name": "pvc-browser",
      "image": "busybox:1.36",
      "command": ["sh"],
      "stdin": true,
      "tty": true,
      "volumeMounts": [{
        "name": "data",
        "mountPath": "/data",
        "readOnly": true
      }]
    }],
    "volumes": [{
      "name": "data",
      "persistentVolumeClaim": {
        "claimName": "<pvc-name>",
        "readOnly": true
      }
    }]
  }
}' -- sh
```

#### Use Cases for Read-Only PVC Browsing

1. **Data Verification**: Confirm backup contents before/after operations
2. **Troubleshooting**: Inspect application data when pods are failing
3. **Migration Planning**: Analyze data structure before moving applications
4. **Audit**: Review data without risk of modification
5. **Debugging**: Check file permissions, ownership, and structure

#### Cleanup

Don't forget to clean up temporary resources:

```bash
# Remove browser pod
kubectl delete pod pvc-browser -n <namespace>

# Clean up snapshot-based resources (if used)
kubectl delete pod snapshot-browser -n <namespace>
kubectl delete pvc <app-name>-browse-pvc -n <namespace>
kubectl delete volumesnapshot <app-name>-browse-snapshot -n <namespace>
```

#### Important Notes

- **Read-Only Safety**: Always use `readOnly: true` to prevent accidental modifications
- **Security Context**: Match the application's user/group IDs if needed for file access
- **Resource Limits**: Add resource limits for production environments
- **Access Modes**: Some storage classes may not support concurrent read-only access
- **Snapshot Overhead**: Snapshot-based browsing uses additional storage temporarily

### Check VolSync Status

```bash
# Check all VolSync resources
kubectl get replicationsource,replicationdestination -A

# Check specific backup status
kubectl describe replicationsource <app-name> -n <namespace>

# View backup job logs
kubectl logs job/volsync-src-<app-name> -n <namespace>
```

### Common Issues

1. **Backup Jobs Failing**:
   - Check if mutating admission policies are running
   - Verify NFS server connectivity
   - Ensure Restic repository credentials are available

2. **Resource Conflicts**:
   - Jitter policy should prevent this
   - Check if multiple large backups are running simultaneously

3. **Cache Issues**:
   - Verify OpenEBS storage class is available
   - Check cache PVC status and capacity

### Admission Policy Status

```bash
# Check if policies are active
kubectl get mutatingadmissionpolicy

# Verify policy bindings
kubectl get mutatingadmissionpolicybinding

# Check policy application logs
kubectl logs deployment/kube-apiserver -n kube-system | grep -i "admission"
```

## Security

- **Encryption**: All backups encrypted at rest using Restic
- **Credentials**: Repository passwords stored in 1Password and synced via External Secrets
- **Network**: NFS traffic within trusted network
- **Access**: Backup jobs run with minimal required privileges

## Disaster Recovery

To restore from backup:

1. **Create ReplicationDestination** in target cluster
2. **Point to same NFS repository** with appropriate credentials
3. **Specify target PVC** for restoration
4. **VolSync will restore** the latest or specified snapshot

This architecture ensures that persistent data is automatically backed up to external storage while maintaining high performance for running applications through the Rook Ceph + OpenEBS combination.

### Restore cross-namespace with Kopia
Source: https://perfectra1n.github.io/volsync/usage/kopia/cross-namespace-restore.html

```yaml
---
apiVersion: volsync.backube/v1alpha1
kind: ReplicationDestination
metadata:
  name: ${APP}-restore
  namespace: default  # Target namespace
spec:
  trigger:
    manual: restore-once
  kopia:
    # Repository configuration in staging namespace
    repository: ${APP}-volsync-secret

    # Create or use existing PVC in staging
    destinationPVC: ${APP}
    copyMethod: Direct

    moverSecurityContext:
      runAsUser: ${APP_UID:=1000}
      runAsGroup: ${APP_GID:=1000}
      fsGroup: ${APP_GID:=1000}

    # Specify the source backup to restore from
    sourceIdentity:
      sourceName: ${APP}
      sourceNamespace: tools  # Source namespace
      # sourcePVCName is auto-discovered from the ReplicationSource
```

## Bootstrap Process for New Applications

When a kustomization including the VolSync component is applied for the first time and no PVC exists yet, the following bootstrap process occurs:

### 1. Initial Resource Creation

The VolSync component creates these resources in order:

1. **ExternalSecret**: Retrieves Restic repository credentials from 1Password
2. **ReplicationDestination** (bootstrap): Named `${APP}-bootstrap` with manual trigger
3. **PVC**: References the ReplicationDestination as a data source

### 2. Bootstrap Flow

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ ExternalSecret  │    │ ReplicationDest │    │      PVC        │
│                 │───▶│   (bootstrap)   │───▶│                 │
│ • Credentials   │    │ • Manual trigger│    │ • dataSourceRef │
│ • From 1Pass    │    │ • Restore once  │    │ • Waits for RD  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │  Restore Job    │
                       │                 │
                       │ • Checks backup │
                       │ • Creates volume│
                       │ • Restores data │
                       └─────────────────┘
```

### 3. What Happens in Each Scenario

#### Scenario A: Backup Repository Exists
If a Restic repository already exists for the application:

1. **ReplicationDestination** is created with `manual: restore-once` trigger
2. **VolSync** automatically starts a restore job
3. **Restore job** downloads the latest backup from NFS/Restic repository
4. **PVC** is populated with restored data
5. **ReplicationSource** begins regular scheduled backups

#### Scenario B: No Backup Repository Exists
If no backup repository exists (truly new application):

1. **ReplicationDestination** is created but has no backup to restore from
2. **PVC** is created but remains empty (no data source available)
3. **Application** starts with an empty volume
4. **ReplicationSource** creates a new Restic repository on first backup
5. **Subsequent backups** save application data to the repository

### 4. Bootstrap Configuration

The bootstrap ReplicationDestination has specific settings:

```yaml
spec:
  trigger:
    manual: restore-once  # Only triggers once, not on schedule
  restic:
    # ... same configuration as ReplicationSource
    capacity: "${VOLSYNC_CAPACITY:-1Gi}"  # Creates PVC of specified size
    cleanupCachePVC: true    # Cleans up temporary cache after restore
    cleanupTempPVC: true     # Cleans up temporary PVCs
    enableFileDeletion: true # Allows file deletions during restore
```

### 5. Monitoring Bootstrap Process

```bash
# Check if bootstrap ReplicationDestination exists
kubectl get replicationdestination ${APP}-bootstrap -n <namespace>

# Monitor bootstrap restore job
kubectl get jobs -n <namespace> | grep volsync-dst

# Check bootstrap job logs
kubectl logs job/volsync-dst-${APP}-bootstrap -n <namespace>

# Verify PVC was created and bound
kubectl get pvc ${APP} -n <namespace>
```

### 6. Common Bootstrap Issues

1. **PVC Stuck in Pending**:
   - ReplicationDestination may be failing to restore
   - Check if backup repository exists and is accessible
   - Verify NFS server connectivity

2. **Bootstrap Job Fails**:
   - Repository credentials may be incorrect
   - NFS mount issues in backup jobs
   - Check admission policies are working

3. **Application Won't Start**:
   - PVC may not be bound yet
   - Wait for bootstrap process to complete
   - Check application pod events

### 7. Bootstrap Window Caveat

⚠️ **CRITICAL**: There is a **bootstrap window vulnerability** between application deployment and first backup completion.

#### The Problem

When a new kustomization is deployed:

1. ✅ **Initial deployment works fine** - PVC is empty, application starts normally
2. ⏰ **Bootstrap window begins** - Application is running, but no backup exists yet
3. ❌ **If removed during this window** - Restoration will fail because no backup data exists
4. ✅ **After first backup completes** - Restoration works normally

#### Timeline Example

```
00:00 - Application deployed (empty PVC, starts fine)
01:00 - First scheduled backup runs (hourly: 0 * * * *)
01:03 - First backup completes ✅
01:04+ - Removal/restoration now works safely
```

**Risk Period**: Between deployment and first backup completion (~1 hour max)

#### Detection and Mitigation

**Check if first backup completed**:
```bash
# Verify backup repository has snapshots
kubectl get replicationsource <app-name> -n <namespace> \
  -o jsonpath='{.status.latestMoverStatus.logs}'

# Look for successful backup message like:
# "snapshot abc123de saved"
# "Restic completed in Xs"
```

**Force immediate backup after deployment**:
```bash
# Trigger manual backup immediately after deployment
kubectl patch replicationsource <app-name> -n <namespace> \
  --type='merge' \
  -p='{"spec":{"trigger":{"manual":"initial-backup-'$(date +%s)'"}}}'
```

**Verify backup completion before any maintenance**:
```bash
# Check that backup repository contains data
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: verify-backup
  namespace: <namespace>
spec:
  containers:
  - name: verify
    image: busybox
    command: ["sh", "-c", "ls -la /repository/<app-name>/snapshots/ && echo 'Backup verification complete'"]
    volumeMounts:
    - name: repository
      mountPath: /repository
  volumes:
  - name: repository
    nfs:
      server: truenas.lan.home.vwn.io
      path: /mnt/vault/cluster/volsync
  restartPolicy: Never
EOF
```

### 8. Best Practices

- **Wait for Bootstrap**: Don't start applications until PVC is bound
- **Monitor First Deployment**: Watch bootstrap logs for new applications
- **Backup Verification**: **ALWAYS verify first backup completes before any removal/maintenance**
- **Manual Initial Backup**: Consider triggering immediate backup after new deployments
- **Repository Management**: Use consistent naming for backup repositories
- **Bootstrap Window Awareness**: Never remove applications during the bootstrap window (0-60 minutes after deployment)
