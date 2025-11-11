provider "aws" {
  region = var.region
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect = "Allow"
    principals { type = "Service" ; identifiers = ["lambda.amazonaws.com"] }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_lambda_function" "optimizer" {
  filename         = "${path.module}/lambda-archive/cost-optimizer.zip"
  function_name    = "${var.project_name}-optimizer"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  environment {
    variables = {
      DRY_RUN = var.dry_run ? "true" : "false"
      AGE_DAYS = tostring(var.age_days)
      SNS_ARN = aws_sns_topic.alerts.arn
    }
  }
}

resource "aws_cloudwatch_event_rule" "schedule" {
  name  = "${var.project_name}-schedule"
  schedule_expression = var.schedule
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule = aws_cloudwatch_event_rule.schedule.name
  target_id = "lambda"
  arn = aws_lambda_function.optimizer.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.optimizer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}
