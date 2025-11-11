variable "region" { default = "ap-south-1" }
variable "project_name" { default = "aws-cost-optimizer" }
variable "dry_run" { type = bool; default = true }
variable "age_days" { type = number; default = 30 }
variable "schedule" { default = "cron(0 2 ? * SUN *)" }
