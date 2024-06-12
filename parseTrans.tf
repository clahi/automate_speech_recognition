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

resource "aws_lambda_permission" "autoSpeechRecogPermission" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.autoSpeechRecog.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.mySourceBucket.arn
}

resource "aws_s3_bucket_notification" "bucketNotification" {
  bucket = aws_s3_bucket.mySourceBucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.autoSpeechRecog.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "source/"
  }

  depends_on = [aws_lambda_permission.autoSpeechRecogPermission]
}