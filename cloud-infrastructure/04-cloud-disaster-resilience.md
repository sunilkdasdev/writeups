# How to Build Resilience for a Cloud Disaster

Every AWS account eventually accumulates "shadow resources"—infrastructure that exists outside of Terraform state, created by quick fixes, abandoned experiments, or deprecated services. These forgotten assets become liabilities during disasters.

## The Shadow Resource Problem

When disaster strikes, you need to rebuild your infrastructure from known-good state. But if your Terraform doesn't account for:

- Manually created S3 buckets
- Lambda functions deployed via console
- Security groups modified ad-hoc
- RDS instances provisioned outside of IaC

...your "complete" recovery plan is actually incomplete.

## Step 1: Assess Account Health

Start with a comprehensive audit:

```bash
# Compare Terraform state against actual resources
terraform import $(aws resourcegroupstaggingapi get-resources | jq -r '.ResourceTagMappingList[] | .ResourceARN')
```

Use AWS Config to track all resource changes:

```bash
aws configservice select-aggregated-resource-credentials \
  --expression "SELECT resourceId, resourceType, configuration"
```

## Step 2: Capture Terraform-Based Snapshots

Create snapshots of your current infrastructure state:

```bash
# Export all resources to JSON
aws resource-explorer get-updated-resources --region us-east-1

# Backup Terraform state
terraform state pull > backup-$(date +%Y%m%d).tfstate
```

## Step 3: Build Repeatable Recovery Plans

Document the recovery procedure for each critical service:

| Service | RTO Target | Recovery Steps | Dependencies |
|---------|------------|----------------|--------------|
| RDS | 1 hour | Restore from snapshot | Subnet group |
| ECS | 15 min | Redeploy from Terraform | ALB, ACM |
| S3 | 5 min | Enable versioning | IAM policies |

## Step 4: Test Your Recovery

The only way to know if your plan works is to test it:

1. **Game day exercises**: Simulate region failures
2. **Backup restoration**: Practice restoring from snapshots
3. **Chaos engineering**: Intentionally break components and recover

## Conclusion

A cloud disaster isn't the time to discover you have shadow resources. Regular audits and Terraform synchronization ensure your recovery plan actually recovers everything you need.