##############################################################################
## RPMrepo
#
# This file defines all the resources needed by the RPMrepo snapshot
# infrastructure. It currently uses the following setup:
#
#   * A dedicated S3 bucket called `rpmrepo`, which has public and private
#     data.
#
#   * A VPC Endpoint Interface for S3 is used to provide access to RH-private
#     data in the dedicated S3 bucket.
#

##############################################################################
## S3 Storage

resource "aws_s3_bucket" "rpmrepo_s3" {
  acl = "private"
  bucket = "rpmrepo"
  tags = merge(
    var.imagebuilder_tags,
    { Name = "RPMrepo Storage" },
  )
}

data "aws_iam_policy_document" "rpmrepo_s3" {
  statement {
    actions = [
      "s3:GetObject",
    ]
    effect = "Allow"
    resources = [
      "${aws_s3_bucket.rpmrepo_s3.arn}/data/public/*",
      "${aws_s3_bucket.rpmrepo_s3.arn}/data/ref/*",
    ]
  }

  statement {
    actions = [
      "s3:GetObject",
    ]
    condition {
      test     = "ArnEquals"
      values   = [aws_vpc_endpoint.internal_vpc_rpmrepo.id]
      variable = "aws:SourceVpce"
    }
    effect = "Allow"
    resources = [
      "${aws_s3_bucket.rpmrepo_s3.arn}/data/rhvpn/*",
    ]
  }
}

resource "aws_s3_bucket_policy" "rpmrepo_s3" {
  bucket = aws_s3_bucket.rpmrepo_s3.id
  policy = data.aws_iam_policy_document.rpmrepo_s3.json
}
