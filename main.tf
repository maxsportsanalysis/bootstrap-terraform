data "aws_iam_policy_document" "breakglass_role_trust_policy" {
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

data "aws_iam_policy_document" "allow_assume_breakglass_role" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRole",
    ]

    resources = [
      "arn:aws:iam::242201314218:role/BreakGlassRoleTrustPolicy",
    ]
  }
}

resource "aws_iam_policy" "breakglass_assume_role_policy" {
  name        = "BreakGlassAssumeRolePolicy"
  description = "Allows sts:AssumeRole on BreakGlassRoleTrustPolicy"

  policy = data.aws_iam_policy_document.allow_assume_breakglass_role.json

}
