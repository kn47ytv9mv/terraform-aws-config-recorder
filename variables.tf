variable "name" {
  default     = null
  description = "Name of the recorder and delivery channel. If null, a unique name is generated."
}

variable "all_supported" {
  default     = true
  description = "Whether every resource type AWS Config supports is recorded, rather than only resource_types. Defaults true — a partial inventory misses whatever was left out, which defeats the purpose of a resource inventory for most accounts."
}

variable "include_global_resource_types" {
  default     = true
  description = "Whether global resource types (IAM users, roles, and so on) are recorded, in addition to regional ones. Only meaningful when all_supported is true."
}

variable "resource_types" {
  default     = []
  description = "Specific resource types to record (e.g. 'AWS::EC2::Instance'), when all_supported is false. Ignored when all_supported is true."
}

variable "recording_frequency" {
  default     = null
  description = "How often configuration items are recorded: 'CONTINUOUS' (as changes happen) or 'DAILY' (once a day). If null, AWS's own default (CONTINUOUS) applies."
}

variable "delivery_frequency" {
  default     = null
  description = "How often configuration snapshots are delivered to the S3 bucket (e.g. 'One_Hour', 'Six_Hours', 'TwentyFour_Hours'). This is separate from recording_frequency — configuration changes are still tracked continuously; this only controls snapshot delivery cadence. If null, AWS's own default applies."
}

variable "s3_key_prefix" {
  default     = null
  description = "Prefix for delivered object keys in the log bucket, before the AWSLogs/<account-id>/Config/ path AWS adds automatically."
}

variable "kms_key_id" {
  default     = null
  description = "ARN of a KMS key to encrypt the log bucket with (SSE-KMS). If null, the bucket uses SSE-S3."
}

variable "versioning" {
  default     = "enabled"
  description = "Versioning state of the log bucket (e.g. 'enabled', 'suspended', or 'disabled'). Defaults enabled, so a configuration snapshot cannot be silently overwritten or lost."
}

variable "enable_access_logging" {
  default     = false
  description = "Whether the delivery bucket delivers server access logs to access_log_bucket. This is a separate switch because Terraform requires the decision to be known before it plans, and a target bucket created in the same configuration is not — see the Design section."

  validation {
    condition     = !var.enable_access_logging || var.access_log_bucket != null
    error_message = "enable_access_logging requires access_log_bucket to name the bucket receiving the logs."
  }

  validation {
    condition     = var.access_log_bucket == null || var.enable_access_logging
    error_message = "access_log_bucket is set but enable_access_logging is false, so no logs would be delivered. Set enable_access_logging = true."
  }
}

variable "access_log_bucket" {
  default     = null
  description = "Name of a separate S3 bucket to send this module's own log bucket's server access logs to. If null, access logging is disabled."
}

variable "access_log_prefix" {
  default     = null
  description = "Prefix for access log object keys in access_log_bucket. Only used when access_log_bucket is set."
}

variable "sns_topic_arn" {
  default     = null
  description = "ARN of an SNS topic to notify of configuration changes and compliance state changes. If null, no notification is sent."
}

variable "tags" {
  default     = null
  description = "A map of tags to assign to the log bucket and the service role."
}
