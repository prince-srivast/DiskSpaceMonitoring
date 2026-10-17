data "aws_ssm_parameter" "ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "instance" {
  name_prefix = "${var.name}-"
  description = "HTTPS egress for Systems Manager and CloudWatch Agent."
  vpc_id      = data.aws_subnet.selected.vpc_id

  egress {
    description = "HTTPS egress"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name}-instances"
  })
}

data "aws_subnet" "selected" {
  id = var.subnet_ids[0]
}

resource "aws_instance" "this" {
  count = var.instance_count

  ami                         = data.aws_ssm_parameter.ami.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids      = [aws_security_group.instance.id]
  iam_instance_profile        = var.instance_profile
  associate_public_ip_address = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, {
    Name           = "${var.name}-${format("%02d", count.index + 1)}"
    DiskMonitoring = "enabled"
  })
}
