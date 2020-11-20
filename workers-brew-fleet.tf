##############################################################################
## WORKER SPOT FLEETS
# Set up the cloud-init user data for worker instances.
data "template_file" "worker_brew_user_data" {
  template = file("cloud-init/worker-brew/worker-variables.template")

  vars = {
    # Add any variables here to pass to the setup script when the instance
    # boots.
    node_hostname   = "worker-brew-fleet-testing"
    osbuild_commit  = var.osbuild_commit
    composer_commit = var.composer_commit

    # Change these to worker certs later.
    composer_brew_ca_cert = filebase64("${path.module}/files/composer-brew-ca-cert.pem")

    # TODO(mhayden): Remove the address below once DNS is working.
    composer_brew_host    = var.composer_brew_host
    composer_brew_address = aws_instance.composer_brew.private_ip

    # Provide the ARN to the secret that contains keys/certificates
    brew_keys_arn = data.aws_secretsmanager_secret.brew_keys.arn

    # 💣 Split off most of the setup script to avoid shenanigans with
    # Terraform's template interpretation that destroys Bash variables.
    # https://github.com/hashicorp/terraform/issues/15933
    setup_script = file("cloud-init/worker-brew/worker-setup.sh")
  }
}

# Create a launch template that specifies almost everything about our workers.
# This eliminates a lot of repeated code for the actual spot fleet itself.
resource "aws_launch_template" "worker_brew_x86" {
  name          = "imagebuilder-worker-brew-x86"
  image_id      = data.aws_ami.rhel8_x86.id
  instance_type = "t3.medium"
  key_name      = "mhayden"

  # Allow the instance to assume the brew_infrastructure IAM role.
  iam_instance_profile {
    name = aws_iam_instance_profile.brew_infrastructure.name
  }

  # Assemble the cloud-init userdata file.
  user_data = base64encode(data.template_file.worker_brew_user_data.rendered)

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
    var.imagebuilder_tags, { Name = "Image Builder Brew worker" },
  )

  # Apply tags to the instances created in the fleet.
  tag_specifications {
    resource_type = "instance"

    tags = merge(
      var.imagebuilder_tags, { Name = "Image Builder Brew worker" },
    )
  }

  # Apply tags to the EBS volumes created in the fleet.
  tag_specifications {
    resource_type = "volume"

    tags = merge(
      var.imagebuilder_tags, { Name = "Image Builder Brew worker" },
    )
  }
}

# Create a spot fleet with our launch template.
resource "aws_spot_fleet_request" "imagebuilder_worker_brew_x86" {
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
      id      = aws_launch_template.worker_brew_x86.id
      version = aws_launch_template.worker_brew_x86.latest_version
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
    var.imagebuilder_tags, { Name = "Image Builder Brew worker fleet" },
  )
}
