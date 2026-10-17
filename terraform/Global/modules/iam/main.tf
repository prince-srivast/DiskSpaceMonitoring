data "aws_iam_policy_document" "ec2_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "instance" {
  statement {
    sid       = "PublishDiskMetrics"
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["CWAgent"]
    }
  }

  statement {
    sid       = "ReadAgentConfig"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = [var.parameter_arn]
  }
}

data "aws_iam_policy_document" "controller" {
  statement {
    sid       = "DiscoverTaggedInstances"
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }

  statement {
    sid       = "PublishAgentConfiguration"
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:PutParameter"]
    resources = [var.parameter_arn]
  }

  statement {
    sid    = "ManageSsmSessions"
    effect = "Allow"
    actions = [
      "ssm:DescribeInstanceInformation",
      "ssm:SendCommand",
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
      "ssm:ListCommands",
      "ssm:StartSession",
      "ssm:ResumeSession",
      "ssm:TerminateSession"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "UseTransferBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [var.transfer_bucket_arn]
  }

  statement {
    sid    = "TransferFiles"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = ["${var.transfer_bucket_arn}/*"]
  }
}

resource "aws_iam_role" "instance" {
  name_prefix        = "${var.name}-"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
  tags               = var.tags
}

resource "aws_iam_instance_profile" "instance" {
  name_prefix = "${var.name}-"
  role        = aws_iam_role.instance.name
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "agent" {
  name   = "${var.name}-agent"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.instance.json
}

resource "aws_iam_policy" "controller" {
  name_prefix = "${var.name}-ansible-"
  policy      = data.aws_iam_policy_document.controller.json
  tags        = var.tags
}

output "instance_profile_name" {
  value = aws_iam_instance_profile.instance.name

  depends_on = [
    aws_iam_role_policy_attachment.ssm_core,
    aws_iam_role_policy.agent
  ]
}

output "transfer_policy_arn" {
  value = aws_iam_policy.controller.arn
}
