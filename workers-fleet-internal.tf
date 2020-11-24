##############################################################################
## WORKER SPOT FLEETS
# Set up the cloud-init user data for worker instances.
data "template_file" "worker_internal_user_data" {
  template = file("cloud-init/worker/worker-variables.template")

  vars = {
    # Add any variables here to pass to the setup script when the instance
    # boots.
    osbuild_commit  = var.osbuild_commit
    composer_commit = var.composer_commit

    # Change these to worker certs later.
    osbuild_ca_cert = filebase64("${path.module}/files/osbuild-ca-cert.pem")

    # TODO(mhayden): Remove the address below once DNS is working.
    composer_host    = var.composer_host_internal
    composer_address = aws_instance.composer_internal.private_ip

    # Provide the ARN to the secret that contains keys/certificates
    worker_ssl_keys_arn = data.aws_secretsmanager_secret.internal_worker_keys.arn

    # 💣 Split off most of the setup script to avoid shenanigans with
    # Terraform's template interpretation that destroys Bash variables.
    # https://github.com/hashicorp/terraform/issues/15933
    setup_script = file("cloud-init/worker/worker-setup.sh")
  }
}

# Create a launch template that specifies almost everything about our workers.
# This eliminates a lot of repeated code for the actual spot fleet itself.
resource "aws_launch_template" "worker_internal_x86" {
  name          = "imagebuilder-worker-internal-x86"
  image_id      = data.aws_ami.rhel8_x86.id
  instance_type = "t3.medium"
  key_name      = "tgunders"

  # Allow the instance to assume the internal_worker IAM role.
  iam_instance_profile {
    name = aws_iam_instance_profile.internal_worker.name
  }

  # Assemble the cloud-init userdata file.
  user_data = base64encode(data.template_file.worker_internal_user_data.rendered)

  # Get the security group for the instances.
  vpc_security_group_ids = [
    aws_security_group.internal_allow_egress.id,
    aws_security_group.internal_allow_trusted.id
  ]

  # Ensure the latest version of the template is marked as the default one.
  update_default_version = true

  # Block devices attached to each worker.
  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size = 50
      volume_type = "gp2"
    }
  }

  # Apply tags to the spot fleet definition itself.
  tags = merge(
    var.imagebuilder_tags, { Name = "Image Builder internal worker" },
  )

  # Apply tags to the instances created in the fleet.
  tag_specifications {
    resource_type = "instance"

    tags = merge(
      var.imagebuilder_tags, { Name = "Image Builder internal worker" },
    )
  }

  # Apply tags to the EBS volumes created in the fleet.
  tag_specifications {
    resource_type = "volume"

    tags = merge(
      var.imagebuilder_tags, { Name = "Image Builder internal worker" },
    )
  }
}

# Create a spot fleet with our launch template.
resource "aws_spot_fleet_request" "workers_internal_x86" {
  # Ensure we use the lowest price instances at all times.
  allocation_strategy = "lowestPrice"

  # Keep the fleet at the target_capacity at all times.
  fleet_type      = "maintain"
  target_capacity = 1

  # IAM role that the spot fleet service can use.
  iam_fleet_role = aws_iam_role.spot_fleet_tagging_role.arn

  # Instances that reach spot expiration or are stopped due to target capacity
  # limits should be terminated.
  terminate_instances_with_expiration = true

  # Create a new fleet before destroying the old one.
  # lifecycle {
  #   create_before_destroy = true
  # }

  # Use our pre-defined launch template.
  launch_template_config {
    launch_template_specification {
      id      = aws_launch_template.worker_internal_x86.id
      version = aws_launch_template.worker_internal_x86.latest_version
    }

    dynamic "overrides" {
      for_each = var.worker_instance_types

      content {
        instance_type = overrides.value
        subnet_id     = data.aws_subnet.internal_subnet_primary.id
      }
    }
  }

  tags = merge(
    var.imagebuilder_tags, { Name = "Image Builder internal worker fleet" },
  )
}