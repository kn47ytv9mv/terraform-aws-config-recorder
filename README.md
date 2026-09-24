# terraform-aws-config-recorder

Terraform module for AWS Config's recorder — a continuous inventory of
every supported resource's configuration and its history, complementing
[`terraform-aws-cloudtrail`](https://github.com/kn47ytv9mv/terraform-aws-cloudtrail)'s
record of API calls with a record of what actually exists and how it
has changed over time. Pair with
[`terraform-aws-config-rule`](https://github.com/kn47ytv9mv/terraform-aws-config-rule)
to evaluate that inventory against compliance rules.

## Cost

AWS Config bills per configuration item recorded, plus a separate
per-evaluation charge for any Config Rules attached (see
`terraform-aws-config-rule`'s own Cost section). The S3 bucket this
module creates bills standard storage rates for the snapshots and
history delivered to it. See AWS's
[Config pricing](https://aws.amazon.com/config/pricing/) page for
current rates — a large, frequently-changing account can generate a
meaningful volume of configuration items, so `all_supported`/
`resource_types` is a real cost lever, not just a scope one.

## Design

Bundles three separate AWS resources most callers would otherwise have
to wire together by hand: the recorder itself, the delivery channel
(its own S3 bucket, created and secured the same way
`terraform-aws-cloudtrail` secures its log bucket — public access
blocked, encryption via `kms_key_id`, optional access logging), and —
easy to miss — the recorder's *status*. AWS models "does this recorder
exist" and "is this recorder actually turned on" as two separate API
calls; creating `aws_config_configuration_recorder` alone leaves
recording off. This module always enables it, since a configuration
recorder that exists but is not recording is not a meaningfully
different state from not having one.

`recording_frequency` (how often a configuration item is captured) and
`delivery_frequency` (how often a snapshot is delivered to S3) are
genuinely separate settings AWS itself keeps distinct — changes are
still tracked continuously either way; `recording_frequency: 'DAILY'`
only reduces how often a full item is recorded for unchanged
resources.

This module creates its own IAM role (the AWS-managed `AWS_ConfigRole`
policy, plus a tightly-scoped inline policy for the S3 bucket it
creates) rather than taking one as an input — the same reasoning
`terraform-aws-cloudtrail` uses for its CloudWatch delivery role: this
role has no reuse value outside recording into this specific bucket.

`include_global_resource_types` is only ever sent to AWS when
`all_supported` is true — confirmed against real AWS: setting both
`all_supported = false` and `include_global_resource_types = true`
together fails with `InvalidRecordingGroupException`, since selective
resource-type recording and "plus every global type" are a
contradiction AWS itself rejects. This module suppresses the argument
entirely rather than surfacing that error, matching what the
description already promised.

**Tearing this module down needs the bucket emptied first, by
design.** `versioning` defaults enabled and this module exposes no
`force_destroy` (the same deliberate choice
[`terraform-aws-s3`](https://github.com/kn47ytv9mv/terraform-aws-s3)
makes) — confirmed against real AWS: AWS Config itself writes a
`ConfigWritabilityCheckFile` object into the bucket as soon as the
recorder starts, so a first `terraform destroy` fails with
`BucketNotEmpty` until every object version is deleted from the bucket
first. This is the same safety property the family already applies to
general-purpose buckets, deliberately extended here rather than
special-cased away — losing configuration history in one destroy
command is exactly the kind of accident that property exists to
prevent.

### Switches that look redundant, and are not

`enable_access_logging` alongside `access_log_bucket` reads like a switch
you should not have to remember. It exists because **Terraform decides
how many resources to create before it knows any value AWS computes.**
Gating on `access_log_bucket != null` works only while the bucket name is
written literally in the configuration; point it at a bucket created in
the same apply and the plan fails outright with *"Invalid count argument
... cannot be determined until apply"*, because Terraform cannot yet tell
whether that name is null.

A boolean the caller writes is always known at plan time, so the gate
holds no matter where the bucket name comes from. Supplying one without
the other is rejected rather than silently ignored, in both directions.

## Usage

```hcl
module "config_recorder" {
  source = "kn47ytv9mv/config-recorder/aws"
}
```

Or directly from this repository, recording only a specific set of
resource types on a daily cadence:

```hcl
module "config_recorder" {
  source = "github.com/kn47ytv9mv/terraform-aws-config-recorder"

  all_supported        = false
  resource_types       = ["AWS::EC2::Instance", "AWS::S3::Bucket", "AWS::IAM::Role"]
  recording_frequency  = "DAILY"
  delivery_frequency   = "TwentyFour_Hours"
}
```

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.0 |
| aws | ~> 6.61 |
| random | ~> 3.9 |

## Providers

| Name | Version |
|---|---|
| aws | ~> 6.61 |
| random | ~> 3.9 |

## Inputs

| Name | Description | Default | Required |
|---|---|---|---|
| name | Name of the recorder and delivery channel. If null, a unique name is generated. | `null` | no |
| all_supported | Whether every resource type AWS Config supports is recorded, rather than only resource_types. Defaults true — a partial inventory misses whatever was left out, which defeats the purpose of a resource inventory for most accounts. | `true` | no |
| include_global_resource_types | Whether global resource types (IAM users, roles, and so on) are recorded, in addition to regional ones. Only meaningful when all_supported is true. | `true` | no |
| resource_types | Specific resource types to record (e.g. 'AWS::EC2::Instance'), when all_supported is false. Ignored when all_supported is true. | `[]` | no |
| recording_frequency | How often configuration items are recorded: 'CONTINUOUS' (as changes happen) or 'DAILY' (once a day). If null, AWS's own default (CONTINUOUS) applies. | `null` | no |
| delivery_frequency | How often configuration snapshots are delivered to the S3 bucket (e.g. 'One_Hour', 'Six_Hours', 'TwentyFour_Hours'). This is separate from recording_frequency — configuration changes are still tracked continuously; this only controls snapshot delivery cadence. If null, AWS's own default applies. | `null` | no |
| s3_key_prefix | Prefix for delivered object keys in the log bucket, before the AWSLogs/<account-id>/Config/ path AWS adds automatically. | `null` | no |
| kms_key_id | ARN of a KMS key to encrypt the log bucket with (SSE-KMS). If null, the bucket uses SSE-S3. | `null` | no |
| versioning | Versioning state of the log bucket (e.g. 'enabled', 'suspended', or 'disabled'). Defaults enabled, so a configuration snapshot cannot be silently overwritten or lost. | `"enabled"` | no |
| enable_access_logging | Whether the delivery bucket delivers server access logs to `access_log_bucket`. Separate from the bucket name because Terraform needs the decision known at plan time — see Design. | `false` | no |
| access_log_bucket | Name of a separate S3 bucket to send this module's own log bucket's server access logs to. Requires `enable_access_logging`. | `null` | no |
| access_log_prefix | Prefix for access log object keys in access_log_bucket. Only used when access_log_bucket is set. | `null` | no |
| sns_topic_arn | ARN of an SNS topic to notify of configuration changes and compliance state changes. If null, no notification is sent. | `null` | no |
| tags | A map of tags to assign to the log bucket and the service role. | `null` | no |

## Outputs

| Name | Description |
|---|---|
| id | The name of the configuration recorder. |
| role_arn | The ARN of the IAM role created for the recorder — pass to terraform-aws-config-rule if a rule's own policy needs to reference it. |
| bucket | The name of the S3 bucket configuration snapshots and history are delivered to. |
| bucket_arn | The ARN of the S3 bucket configuration snapshots and history are delivered to. |

## License

MIT — see [LICENSE.md](LICENSE.md).
