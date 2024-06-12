resource "aws_iam_role" "lambdaParseRole" {
  name = "lambdaParseRole"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17"
    "Statement" : [
      {
        "Effect" : "Allow"
        "Action" : [
          "sts:AssumeRole"
        ]
        "Principal" : {
          "Service" : [
            "lambda.amazonaws.com"
          ]
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambdaParseS3Policy" {
  name = "lambdaParseS3Policy"
  policy = jsonencode({
    Version : "2012-10-17"
    Statement : [
      {
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource" : "arn:aws:logs:*:*:*"
      },
      {
        Effect : "Allow"
        Action : [
          "s3:PutObject"
        ]
        Resource : "arn:aws:s3:::my-dest-bucket-76sdf700/*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "transcribe:*"
        ],
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "lambdaParseRolePolicyAttachment" {
  policy_arn = aws_iam_policy.lambdaParseS3Policy.arn
  roles      = [aws_iam_role.lambdaParseRole.name]
  name       = "lambdaRolePolicyAttachment"
}

data "archive_file" "lambdaParseFile" {
  type        = "zip"
  source_file = "${path.module}/parseTrans.py"
  output_path = "${path.module}/parseTrans.zip"
}

resource "aws_lambda_function" "ParseSpeechRecog" {
  role             = aws_iam_role.lambdaParseRole.arn
  filename         = data.archive_file.lambdaParseFile.output_path
  source_code_hash = data.archive_file.lambdaParseFile.output_base64sha256
  function_name    = "ParseSpeechRecog"
  runtime          = "python3.9"
  handler          = "parseTrans.lambda_handler"

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.myDestiBucket.id
    }
  }
}

resource "aws_cloudwatch_event_rule" "eventRule" {
  name        = "eventRule"
  description = "Rule to trigger lambda to stop all instances at a specific time"

  event_pattern = jsonencode({
    source        = ["aws.transcribe"],
    "detail-type" = ["Transcribe Job State Change"],
    detail = {
      TranscriptionJobStatus = ["COMPLETED"]
    }
  })
}

resource "aws_cloudwatch_event_target" "ParseSpeech" {
  rule      = aws_cloudwatch_event_rule.eventRule.name
  arn       = aws_lambda_function.ParseSpeechRecog.arn
  target_id = "ParseSpeech"
}

resource "aws_lambda_permission" "ec2_stop_perm" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ParseSpeechRecog.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.eventRule.arn
}