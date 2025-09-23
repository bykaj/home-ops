#!/bin/bash

# Script to remove finalizers from PVs with StorageClass = ceph-block
# WARNING: This bypasses Kubernetes cleanup mechanisms - use with caution!

set -e  # Exit on any error

STORAGE_CLASS="ceph-block"
DRY_RUN=${1:-false}  # Pass 'true' as first argument for dry run

echo "🔍 Searching for PVs with StorageClass: $STORAGE_CLASS"

# Get all PVs with the specified StorageClass
PV_LIST=$(kubectl get pv -o jsonpath='{range .items[?(@.spec.storageClassName=="'$STORAGE_CLASS'")]}{.metadata.name}{"\n"}{end}')

if [ -z "$PV_LIST" ]; then
    echo "✅ No PVs found with StorageClass: $STORAGE_CLASS"
    exit 0
fi

echo "📋 Found PVs:"
echo "$PV_LIST"
echo ""

# Count PVs
PV_COUNT=$(echo "$PV_LIST" | wc -l)
echo "📊 Total PVs to process: $PV_COUNT"
echo ""

if [ "$DRY_RUN" = "true" ]; then
    echo "🔍 DRY RUN MODE - No changes will be made"
    echo "The following PVs would have their finalizers removed:"
    echo "$PV_LIST"
    exit 0
fi

# Confirmation prompt
read -p "⚠️  WARNING: This will remove finalizers from $PV_COUNT PVs. This may leave storage resources dangling. Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Operation cancelled"
    exit 1
fi

echo "🚀 Starting finalizer removal..."
echo ""

# Counter for progress
PROCESSED=0
SUCCEEDED=0
FAILED=0

# Process each PV
while IFS= read -r pv_name; do
    if [ -n "$pv_name" ]; then
        PROCESSED=$((PROCESSED + 1))
        echo "[$PROCESSED/$PV_COUNT] Processing PV: $pv_name"

        # Check if PV has finalizers
        FINALIZERS=$(kubectl get pv "$pv_name" -o jsonpath='{.metadata.finalizers}' 2>/dev/null || echo "")

        if [ -n "$FINALIZERS" ] && [ "$FINALIZERS" != "[]" ]; then
            echo "  📝 Removing finalizers from: $pv_name"
            if kubectl patch pv "$pv_name" -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1; then
                echo "  ✅ Successfully removed finalizers from: $pv_name"
                SUCCEEDED=$((SUCCEEDED + 1))
            else
                echo "  ❌ Failed to remove finalizers from: $pv_name"
                FAILED=$((FAILED + 1))
            fi
        else
            echo "  ℹ️  No finalizers found on: $pv_name"
            SUCCEEDED=$((SUCCEEDED + 1))
        fi
        echo ""
    fi
done <<< "$PV_LIST"

# Summary
echo "📈 Summary:"
echo "  Total processed: $PROCESSED"
echo "  Successful: $SUCCEEDED"
echo "  Failed: $FAILED"

if [ $FAILED -eq 0 ]; then
    echo "✅ All operations completed successfully!"
else
    echo "⚠️  Some operations failed. Check the logs above."
    exit 1
fi

echo ""
echo "💡 Next steps:"
echo "  1. Verify PVs are deleted: kubectl get pv"
echo "  2. Check for any remaining PVCs: kubectl get pvc --all-namespaces"
echo "  3. Manually cleanup external storage resources if needed"
