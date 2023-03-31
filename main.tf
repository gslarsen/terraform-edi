terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"

}

provider "aws" {
  region = "us-east-1"
}

resource "aws_sqs_queue" "edi-DeadLetters-2" {
  name                              = "edi-DeadLetters-2.fifo"
  content_based_deduplication       = true
  deduplication_scope               = "queue"
  fifo_queue                        = true
  fifo_throughput_limit             = "perQueue"
  kms_data_key_reuse_period_seconds = 300
  # message_retention_seconds         = 600  note: default is 345600 (4 days)
  receive_wait_time_seconds  = 1
  visibility_timeout_seconds = 1
  redrive_allow_policy       = "{\"redrivePermission\":\"allowAll\"}"
  redrive_policy             = ""
  sqs_managed_sse_enabled    = true
}

resource "aws_sqs_queue" "edi-queue-2" {
  name                              = "edi-queue-2.fifo"
  content_based_deduplication       = true
  deduplication_scope               = "queue"
  fifo_queue                        = true
  fifo_throughput_limit             = "perQueue"
  kms_data_key_reuse_period_seconds = 300
  message_retention_seconds         = 180
  receive_wait_time_seconds         = 2
  # visibility_timeout_seconds        = 60 note: default is 30
  redrive_allow_policy = ""
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.edi-DeadLetters-2.arn,
    maxReceiveCount     = 1
  })
  sqs_managed_sse_enabled = true
}

resource "aws_iam_role" "api-gateway-to-sqs-2" {
  name               = "api-gateway-to-sqs-2"
  assume_role_policy = "{\"Statement\":[{\"Action\":\"sts:AssumeRole\",\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"apigateway.amazonaws.com\"},\"Sid\":\"\"}],\"Version\":\"2012-10-17\"}"
  description        = "Allows API Gateway to send to SQS"
}

data "aws_iam_policy_document" "api-gateway-to-sqs-2" {
  statement {
    effect = "Allow"

    actions   = ["SQS:SendMessage"]
    resources = [aws_sqs_queue.edi-queue-2.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_iam_role.api-gateway-to-sqs-2.arn]
    }
  }
}

resource "aws_iam_policy" "api-send-to-sqs-2" {
  name        = aws_iam_role.api-gateway-to-sqs-2.name
  description = "test sending edi files to sqs via api gateway"
  policy      = data.aws_iam_policy_document.api-gateway-to-sqs-2.json
}

resource "aws_iam_role_policy_attachment" "api-send-to-sqs-2" {
  role       = aws_iam_role.api-gateway-to-sqs-2.name
  policy_arn = aws_iam_policy.api-send-to-sqs-2.arn
}

resource "aws_iam_role_policy_attachment" "AmazonAPIGatewayPushToCloudWatchLogs" {
  role       = aws_iam_role.api-gateway-to-sqs-2.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

data "aws_iam_policy_document" "edi-queue" {
  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.api-gateway-to-sqs-2.arn]
    }

    actions   = ["SQS:*"]
    resources = [aws_sqs_queue.edi-DeadLetters-2.arn]
  }

  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.api-gateway-to-sqs-2.arn]
    }

    actions   = ["SQS:*"]
    resources = [aws_sqs_queue.edi-queue-2.arn]
  }
}

resource "aws_sqs_queue_policy" "edi-queue-dead-letter" {
  queue_url = aws_sqs_queue.edi-DeadLetters-2.id
  policy    = data.aws_iam_policy_document.edi-queue.json
}

resource "aws_sqs_queue_policy" "edi-queue" {
  queue_url = aws_sqs_queue.edi-queue-2.id
  policy    = data.aws_iam_policy_document.edi-queue.json
}


resource "aws_api_gateway_rest_api" "edi" {
  name           = "edi"
  description    = "process edi transactions"
  api_key_source = "HEADER"
  binary_media_types = [
    "*.json"
  ]
  disable_execute_api_endpoint = false
}

resource "aws_api_gateway_resource" "edi" {
  rest_api_id = aws_api_gateway_rest_api.edi.id
  parent_id   = aws_api_gateway_rest_api.edi.root_resource_id
  path_part   = "edi"
}

resource "aws_api_gateway_integration" "edi" {
  rest_api_id             = aws_api_gateway_rest_api.edi.id
  resource_id             = aws_api_gateway_resource.edi.id
  type                    = "AWS"
  http_method             = "POST"
  integration_http_method = "POST"
  credentials             = aws_iam_role.api-gateway-to-sqs-2.arn
  request_parameters = {
    "integration.request.header.Content-Type" : "'application/x-www-form-urlencoded'"
  }
  request_templates = {
    "application/json" : "Action=SendMessage\u0026MessageGroupId=edi\u0026MessageBody=$util.urlEncode($input.body)"
  }
  passthrough_behavior = "WHEN_NO_TEMPLATES"
  uri                  = "arn:aws:apigateway:us-east-1:sqs:path/${local.account}/${aws_sqs_queue.edi-queue-2.name}"
}

resource "aws_api_gateway_method" "edi" {
  rest_api_id   = aws_api_gateway_rest_api.edi.id
  resource_id   = aws_api_gateway_resource.edi.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_deployment" "edi" {
  rest_api_id = aws_api_gateway_rest_api.edi.id

  depends_on = [
    aws_api_gateway_method.edi,
    aws_api_gateway_integration.edi
  ]
}

resource "aws_api_gateway_stage" "edi" {
  deployment_id = aws_api_gateway_deployment.edi.id
  rest_api_id   = aws_api_gateway_rest_api.edi.id
  stage_name    = local.stage_name
}

resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.edi.id
  resource_id = aws_api_gateway_resource.edi.id
  http_method = aws_api_gateway_method.edi.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "integration_response" {
  rest_api_id = aws_api_gateway_rest_api.edi.id
  resource_id = aws_api_gateway_resource.edi.id
  http_method = aws_api_gateway_method.edi.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code

  depends_on = [
    aws_api_gateway_integration.edi
  ]
}

resource "aws_lambda_layer_version" "edi-2" {
  filename            = "lambda-layer/edi-layer-requirements.zip"
  layer_name          = "edi-2"
  compatible_runtimes = ["python3.9"]
}

# note: assumes layer is already created
resource "aws_lambda_function" "edi-TenderMsgFunction" {
  filename = "${local.building_path}/${local.lambda_code_filename}"
  depends_on = [
    null_resource.build_lambda_function
  ]
  source_code_hash = data.archive_file.lambda.output_base64sha256
  function_name    = "edi-TenderMsgFunction"
  role             = aws_iam_role.edi-TenderMsgFunctionRole.arn
  runtime          = "python3.9"
  handler          = "tender_msg.lambda_handler"
  layers = [
    # "arn:aws:lambda:us-east-1:${local.account}:layer:edi:1"
    aws_lambda_layer_version.edi-2.arn
  ]
  timeout = 20

  lifecycle {
    ignore_changes = [
      publish
    ]
  }
}

resource "null_resource" "build_lambda_function" {
  triggers = {
    build_number = "${timestamp()}" # TODO: calculate hash of lambda function. Mo will have a look at this part
  }

  provisioner "local-exec" {
    command = substr(pathexpand("~"), 0, 1) == "/" ? "./py_build.sh \"${local.lambda_src_path}\" \"${local.building_path}\" \"${local.lambda_code_filename}\" Function" : "powershell.exe -File .\\PyBuild.ps1 ${local.lambda_src_path} ${local.building_path} ${local.lambda_code_filename} Function"
  }
}

resource "null_resource" "sam_metadata_aws_lambda_function_edi-TenderMsgFunction" {
  triggers = {
    resource_name        = "aws_lambda_function.edi-TenderMsgFunction"
    resource_type        = "ZIP_LAMBDA_FUNCTION"
    original_source_code = "${local.lambda_src_path}"
    built_output_path    = "${local.building_path}/${local.lambda_code_filename}"
  }
  depends_on = [
    null_resource.build_lambda_function
  ]
}

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "./src"
  output_path = "${local.building_path}/${local.lambda_code_filename}"
}

resource "aws_iam_role" "edi-TenderMsgFunctionRole" {
  name               = "edi-TenderMsgFunctionRole"
  assume_role_policy = "{\"Statement\":[{\"Action\":\"sts:AssumeRole\",\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"lambda.amazonaws.com\"}}],\"Version\":\"2012-10-17\"}"
}

resource "aws_iam_role_policy_attachment" "AmazonSQSFullAccess" {
  role       = aws_iam_role.edi-TenderMsgFunctionRole.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
}

resource "aws_lambda_event_source_mapping" "event_source_mapping" {
  event_source_arn        = aws_sqs_queue.edi-queue-2.arn
  function_name           = aws_lambda_function.edi-TenderMsgFunction.function_name
  batch_size              = 5
  function_response_types = ["ReportBatchItemFailures"]
}

resource "aws_iam_role_policy_attachment" "AWSLambdaBasicExecutionRole" {
  role       = aws_iam_role.edi-TenderMsgFunctionRole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# resource "aws_db_instance" "mysqlforlambda" {
#   instance_class        = "db.t3.micro"
#   storage_encrypted     = true
#   apply_immediately     = null
#   copy_tags_to_snapshot = true
#   max_allocated_storage = 1000
#   publicly_accessible   = true
#   skip_final_snapshot   = true
# }


