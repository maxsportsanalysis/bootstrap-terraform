data "aws_iam_policy_document" "breakglass_trust_policy" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRole"
    ]

    principals {
      type        = "AWS"
      identifiers = [
        "arn:aws:iam::242201314218:user/bootstrap"
      ]
    }

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role" "breakglass" {
  name               = "BreakGlassRoleTrustPolicy"
  assume_role_policy = data.aws_iam_policy_document.breakglass_trust_policy.json
}
