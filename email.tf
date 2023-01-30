data "aws_route53_zone" "domain" {
  name = var.domain
}

// Verify DKIM with the owned domain
resource "aws_ses_domain_identity" "domain" {
  domain = var.domain
}

resource "aws_ses_domain_dkim" "domain" {
  domain = aws_ses_domain_identity.domain.domain
}

resource "aws_route53_record" "domain_amazonses_dkim_record" {
  count   = 3
  zone_id = data.aws_route53_zone.domain.zone_id
  name    = "${aws_ses_domain_dkim.domain.dkim_tokens[count.index]}._domainkey.${var.domain}"
  type    = "CNAME"
  ttl     = "1800"
  records = ["${aws_ses_domain_dkim.domain.dkim_tokens[count.index]}.dkim.amazonses.com"]
}

// Add MX record
resource "aws_route53_record" "domain_mx" {
  zone_id = data.aws_route53_zone.domain.zone_id
  name    = var.domain
  type    = "MX"
  ttl     = "300"
  records = ["10 inbound-smtp.${var.region}.amazonaws.com"]
}

// Create S3 buckets to store the mail
resource "aws_s3_bucket" "storage" {
  bucket = var.s3_bucket_name
}

data "aws_iam_policy_document" "allow_ses_put" {
  statement {
    sid     = "AllowSESPuts"
    actions = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["ses.amazonaws.com"]
    }
    resources = ["arn:aws:s3:::${aws_s3_bucket.storage.id}/mail/*"]
    condition {
      test     = "StringLike"
      variable = "AWS:SourceArn"
      values   = ["${aws_ses_receipt_rule_set.this.arn}:receipt-rule/*"]
    }
  }
}

resource "aws_s3_bucket_policy" "allow_ses_put" {
  bucket = aws_s3_bucket.storage.id
  policy = data.aws_iam_policy_document.allow_ses_put.json
}

// Receipt rules to dump emails into the S3 bucket
resource "aws_ses_receipt_rule" "inboxes" {
  for_each = toset(var.inboxes)

  name          = each.key
  rule_set_name = aws_ses_receipt_rule_set.this.id
  recipients    = ["${each.key}@${var.domain}"]
  enabled       = true
  scan_enabled  = true

  s3_action {
    bucket_name       = aws_s3_bucket.storage.id
    object_key_prefix = "mail/${each.key}"
    position          = 1
  }

  stop_action {
    scope    = "RuleSet"
    position = 2
  }
}

resource "aws_ses_receipt_rule" "fallback" {
  name          = "unknown"
  rule_set_name = aws_ses_receipt_rule_set.this.id
  recipients    = ["${var.domain}"]
  enabled       = true
  scan_enabled  = true
  // The ordering for rules within a ruleset is newest one take priority
  // By setting the fallback as "after" the first inbox, it will be executed last
  after = aws_ses_receipt_rule.inboxes[var.inboxes[0]].id
  s3_action {
    bucket_name       = aws_s3_bucket.storage.id
    object_key_prefix = "mail/unknown"
    position          = 1
  }
}

resource "aws_ses_receipt_rule_set" "this" {
  rule_set_name = var.ruleset_name
}

resource "aws_ses_active_receipt_rule_set" "domain" {
  rule_set_name = aws_ses_receipt_rule_set.this.id
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region                   = var.region
  shared_credentials_files = ["~/.aws/credentials"]
  profile                  = var.aws_profile
}

terraform {
  backend "s3" {
    bucket  = "mchp-terraform-state"
    key     = "infinite-inboxes-ses/tfstate"
    region  = "us-west-2"
    profile = "email-admin"
  }
}