resource "random_uuid" "resource" {}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "logs" {
  bucket = "config-${random_uuid.resource.id}"

  tags = var.tags
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = title(lower(var.versioning))
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_id != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_id
    }
  }
}

resource "aws_s3_bucket_logging" "logs" {
  count = var.enable_access_logging ? 1 : 0

  bucket = aws_s3_bucket.logs.id

  target_bucket = var.access_log_bucket
  target_prefix = var.access_log_prefix != null ? var.access_log_prefix : ""
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSConfigBucketPermissionsCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.logs.arn
      },
      {
        Sid       = "AWSConfigBucketExistenceCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:ListBucket"
        Resource  = aws_s3_bucket.logs.arn
      },
      {
        Sid       = "AWSConfigBucketDelivery"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.logs.arn}/${var.s3_key_prefix != null ? "${var.s3_key_prefix}/" : ""}AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
        Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
      }
    ]
  })
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "resource" {
  assume_role_policy = data.aws_iam_policy_document.assume.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "resource" {
  role       = aws_iam_role.resource.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_iam_role_policy" "s3_delivery" {
  role = aws_iam_role.resource.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetBucketAcl", "s3:ListBucket"]
        Resource = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
      }
    ]
  })
}

resource "aws_config_configuration_recorder" "resource" {
  name     = coalesce(var.name, random_uuid.resource.id)
  role_arn = aws_iam_role.resource.arn

  recording_group {
    all_supported                 = var.all_supported
    include_global_resource_types = var.all_supported ? var.include_global_resource_types : null
    resource_types                = var.all_supported ? null : var.resource_types
  }

  dynamic "recording_mode" {
    for_each = var.recording_frequency[*]

    content {
      recording_frequency = recording_mode.value
    }
  }

  depends_on = [aws_iam_role_policy_attachment.resource, aws_iam_role_policy.s3_delivery]
}

resource "aws_config_delivery_channel" "resource" {
  name           = coalesce(var.name, random_uuid.resource.id)
  s3_bucket_name = aws_s3_bucket.logs.id
  s3_key_prefix  = var.s3_key_prefix
  s3_kms_key_arn = var.kms_key_id
  sns_topic_arn  = var.sns_topic_arn

  dynamic "snapshot_delivery_properties" {
    for_each = var.delivery_frequency[*]

    content {
      delivery_frequency = snapshot_delivery_properties.value
    }
  }

  depends_on = [aws_config_configuration_recorder.resource, aws_s3_bucket_policy.logs]
}

resource "aws_config_configuration_recorder_status" "resource" {
  name       = aws_config_configuration_recorder.resource.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.resource]
}

output "id" {
  description = "The name of the configuration recorder."
  value       = aws_config_configuration_recorder.resource.id
}

output "role_arn" {
  description = "The ARN of the IAM role created for the recorder — pass to terraform-aws-config-rule if a rule's own policy needs to reference it."
  value       = aws_iam_role.resource.arn
}

output "bucket" {
  description = "The name of the S3 bucket configuration snapshots and history are delivered to."
  value       = aws_s3_bucket.logs.id
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket configuration snapshots and history are delivered to."
  value       = aws_s3_bucket.logs.arn
}
