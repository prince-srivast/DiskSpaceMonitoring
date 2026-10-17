provider "aws" {
  region              = var.region_1
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias               = "region_2"
  region              = var.region_2
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = local.common_tags
  }
}
