provider "aws" {
  region = var.region
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_policy" "lambda_policy" {
  name = "${var.project_name}-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:DescribeVolumes",
          "ec2:DeleteVolume",
          "ec2:DescribeSnapshots",
          "ec2:DeleteSnapshot",
          "ec2:DescribeImages",
          "ec2:DeregisterImage"
        ],
        Effect = "Allow",
        Resource = "*"
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = ["sns:Publish"],
        Effect = "Allow",
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_lambda_function" "optimizer" {
  filename         = "${path.module}/lambda-archive/cost-optimizer.zip"
  function_name    = "${var.project_name}-optimizer"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  memory_size      = 512
  timeout          = 300

  environment {
    variables = {
      DRY_RUN        = var.dry_run ? "true" : "false"
      AGE_DAYS       = tostring(var.age_days)
      SNS_ARN        = aws_sns_topic.alerts.arn
      WHITELIST_TAGS = jsonencode(var.whitelist_tags)
    }
  }
}

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${var.project_name}-schedule"
  schedule_expression = var.schedule
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "lambda"
  arn       = aws_lambda_function.optimizer.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.optimizer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}
