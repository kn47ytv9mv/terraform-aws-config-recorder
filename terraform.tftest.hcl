mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock-config-role"
    }
  }
}

run "default_config_records_everything" {
  command = apply

  assert {
    condition     = aws_config_configuration_recorder.resource.recording_group[0].all_supported == true
    error_message = "all_supported should default to true."
  }

  assert {
    condition     = aws_config_configuration_recorder.resource.recording_group[0].include_global_resource_types == true
    error_message = "include_global_resource_types should default to true."
  }

  assert {
    condition     = aws_config_configuration_recorder_status.resource.is_enabled == true
    error_message = "The recorder status should always be enabled — this module has no way to create a recorder that is not recording."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.logs.block_public_acls == true
    error_message = "The log bucket should always have public access fully blocked."
  }

  assert {
    condition     = aws_s3_bucket_versioning.logs.versioning_configuration[0].status == "Enabled"
    error_message = "versioning should default to enabled."
  }
}

run "specific_resource_types_used_when_all_supported_false" {
  command = apply

  variables {
    all_supported  = false
    resource_types = ["AWS::EC2::Instance", "AWS::S3::Bucket"]
  }

  assert {
    condition     = aws_config_configuration_recorder.resource.recording_group[0].all_supported == false
    error_message = "all_supported should pass through unchanged."
  }

  assert {
    condition     = length(aws_config_configuration_recorder.resource.recording_group[0].resource_types) == 2
    error_message = "resource_types should pass through unchanged when all_supported is false."
  }

  assert {
    condition     = aws_config_configuration_recorder.resource.recording_group[0].include_global_resource_types == null
    error_message = "include_global_resource_types must not be sent at all when all_supported is false — AWS rejects true combined with all_supported = false with InvalidRecordingGroupException."
  }
}

run "recording_frequency_renders_recording_mode" {
  command = apply

  variables {
    recording_frequency = "DAILY"
  }

  assert {
    condition     = length(aws_config_configuration_recorder.resource.recording_mode) == 1
    error_message = "recording_frequency given should render exactly one recording_mode block."
  }

  assert {
    condition     = aws_config_configuration_recorder.resource.recording_mode[0].recording_frequency == "DAILY"
    error_message = "recording_frequency should pass through unchanged."
  }
}

run "no_recording_frequency_omits_recording_mode" {
  command = apply

  assert {
    condition     = length(aws_config_configuration_recorder.resource.recording_mode) == 0
    error_message = "No recording_frequency given should omit the recording_mode block, leaving AWS's own default."
  }
}

run "delivery_frequency_renders_snapshot_delivery_properties" {
  command = apply

  variables {
    delivery_frequency = "Six_Hours"
  }

  assert {
    condition     = length(aws_config_delivery_channel.resource.snapshot_delivery_properties) == 1
    error_message = "delivery_frequency given should render exactly one snapshot_delivery_properties block."
  }
}

run "access_log_bucket_enables_bucket_logging" {
  command = apply

  variables {
    enable_access_logging = true
    access_log_bucket     = "example-access-logs-bucket"
  }

  assert {
    condition     = length(aws_s3_bucket_logging.logs) == 1
    error_message = "access_log_bucket given should create exactly one aws_s3_bucket_logging resource."
  }
}

run "kms_key_id_encrypts_bucket_with_sse_kms" {
  command = apply

  variables {
    kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/abcd1234-ab12-cd34-ef56-abcdef123456"
  }

  assert {
    condition     = anytrue([for r in aws_s3_bucket_server_side_encryption_configuration.logs.rule : anytrue([for d in r.apply_server_side_encryption_by_default : d.sse_algorithm == "aws:kms"])])
    error_message = "kms_key_id given should switch the bucket's own encryption to SSE-KMS."
  }
}

run "readme_default_example" {
  command = plan
}

run "readme_specific_types_example" {
  command = plan

  variables {
    all_supported  = false
    resource_types = ["AWS::EC2::Instance", "AWS::S3::Bucket", "AWS::IAM::Role"]
  }
}

run "enable_access_logging_without_access_log_bucket_is_rejected" {
  command = plan

  variables {
    enable_access_logging = true
  }

  expect_failures = [var.enable_access_logging]
}

run "access_log_bucket_without_enable_access_logging_is_rejected" {
  command = plan

  variables {
    access_log_bucket = "example-access-logs-bucket"
  }

  expect_failures = [var.enable_access_logging]
}
