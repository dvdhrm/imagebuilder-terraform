# Create a policy that lets EC2 assume the role.
data "aws_iam_policy_document" "internal_infrastructure_ec2_principal" {
  statement {
    sid = "1"

    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Create roles for the internal composer and workers to use.
resource "aws_iam_role" "internal_worker" {
  name = "internal_worker"

  assume_role_policy = data.aws_iam_policy_document.internal_infrastructure_ec2_principal.json

  tags = merge(
    var.imagebuilder_tags, { Name = "Image Builder internal worker role" },
  )
}

resource "aws_iam_role" "internal_composer" {
  name = "internal_composer"

  assume_role_policy = data.aws_iam_policy_document.internal_infrastructure_ec2_principal.json

  tags = merge(
    var.imagebuilder_tags, { Name = "Image Builder internal composer role" },
  )
}

# Link instance profiles to the roles.
resource "aws_iam_instance_profile" "internal_worker" {
  name = "internal_worker"
  role = aws_iam_role.internal_worker.name
}

resource "aws_iam_instance_profile" "internal_composer" {
  name = "internal_composer"
  role = aws_iam_role.internal_composer.name
}

# Create policies that allows for reading secrets.
data "aws_iam_policy_document" "internal_worker_read_keys" {
  statement {
    sid = "1"

    actions = [
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds"
    ]

    # NOTE(mhayden): AWS adds some extra random characters on the end of the
    # secret name so it can do versioning. The asterisk at the end of this
    # ARN is *critical*.
    resources = [
      "arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:brew_keys*"
    ]
  }
}

data "aws_iam_policy_document" "internal_composer_read_keys" {
  statement {
    sid = "1"

    actions = [
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds"
    ]

    # NOTE(mhayden): AWS adds some extra random characters on the end of the
    # secret name so it can do versioning. The asterisk at the end of this
    # ARN is *critical*.
    resources = [
      "arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:brew_keys*"
    ]
  }
}

# Load the internal secrets policies.
resource "aws_iam_policy" "internal_worker_read_keys" {
  name   = "internal_worker_read_keys"
  policy = data.aws_iam_policy_document.internal_worker_read_keys.json
}

resource "aws_iam_policy" "internal_composer_read_keys" {
  name   = "internal_composer_read_keys"
  policy = data.aws_iam_policy_document.internal_composer_read_keys.json
}

# Attach the internal secrets policies to the internal worker and composer roles.
resource "aws_iam_role_policy_attachment" "internal_worker_read_keys" {
  role       = aws_iam_role.internal_worker.name
  policy_arn = aws_iam_policy.internal_worker_read_keys.arn
}

resource "aws_iam_role_policy_attachment" "internal_composer_read_keys" {
  role       = aws_iam_role.internal_composer.name
  policy_arn = aws_iam_policy.internal_composer_read_keys.arn
}
