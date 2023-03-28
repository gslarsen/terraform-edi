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
  region  = "us-east-1"
}

resource "aws_instance" "aws-cloud9-lambdaLayer-675cc62ded834830a5001d7332ef5cd2" {
  ami           = "ami-06ccf6ffb21d5e9be"
  instance_type = "t2.micro"

  lifecycle {
    ignore_changes = [
        user_data,
        user_data_replace_on_change
    ]
  }
}

resource "aws_lambda_layer_version" "edi"{
  layer_name = "edi"
  compatible_runtimes = ["python3.9"]
}

resource "aws_sqs_queue" "edi-DeadLetters" {
    name = "edi-DeadLetters.fifo"
    content_based_deduplication = true
    deduplication_scope = "queue"
    fifo_queue = true
    fifo_throughput_limit = "perQueue"
    kms_data_key_reuse_period_seconds = 300
    message_retention_seconds = 600
    receive_wait_time_seconds = 2
    visibility_timeout_seconds = 0
}

resource "aws_sqs_queue" "edi-queue" {
    name = "edi-queue.fifo"
    content_based_deduplication = true
    deduplication_scope = "queue"
    fifo_queue = true
    fifo_throughput_limit = "perQueue"
    kms_data_key_reuse_period_seconds = 300
    message_retention_seconds = 180
    receive_wait_time_seconds = 2
    visibility_timeout_seconds = 60
}

resource "aws_api_gateway_rest_api" "edi-transfer-2" {
  name = "edi-transfer-2"
}

resource "aws_api_gateway_resource" "edi-transfer-2" {
  rest_api_id = "729c8fu7u3"
  parent_id   = ""
  path_part   = ""
}

resource "aws_api_gateway_integration" "edi-transfer-2" {
  rest_api_id             = "729c8fu7u3"
  resource_id             = "nir4gk"
  type                    = "AWS"
  http_method             = "POST"
  integration_http_method = "POST"
  credentials             = "arn:aws:iam::186314775128:role/api-gateway-to-sqs"
  request_parameters      = {
    "integration.request.header.Content-Type": "'application/x-www-form-urlencoded'"
  }
  request_templates       = {
    "application/json": "Action=SendMessage\u0026MessageGroupId=edi\u0026MessageBody=$util.urlEncode($input.body)"
  }
  uri                     = "arn:aws:apigateway:us-east-1:sqs:path/186314775128/edi-queue.fifo"
}

resource "aws_api_gateway_method" "edi-transfer-2" {
  rest_api_id   = "729c8fu7u3"
  resource_id   = "nir4gk"
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_stage" "edi-transfer-2" {
  deployment_id = "jka8ge"
  rest_api_id   = "729c8fu7u3"
  stage_name    = "v1"
}

resource "aws_lambda_function" "edi-TenderMsgFunction-CI44xHeEeKTe" {
  filename = "${local.building_path}/${local.lambda_code_filename}"
  depends_on = [
        null_resource.build_lambda_function
  ]
  source_code_hash = "${data.archive_file.lambda.output_base64sha256}"
  function_name = "edi-TenderMsgFunction-CI44xHeEeKTe"
  role          = "arn:aws:iam::186314775128:role/edi-TenderMsgFunctionRole-1OY1LYYV71U88"
  runtime       = "python3.9"
  handler       = "tender_msg.lambda_handler"
  layers        =  [
    "arn:aws:lambda:us-east-1:186314775128:layer:edi:1"
  ]
  timeout       = 20
  
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
        command =  substr(pathexpand("~"), 0, 1) == "/"? "./py_build.sh \"${local.lambda_src_path}\" \"${local.building_path}\" \"${local.lambda_code_filename}\" Function" : "powershell.exe -File .\\PyBuild.ps1 ${local.lambda_src_path} ${local.building_path} ${local.lambda_code_filename} Function"
    }
}

resource "null_resource" "sam_metadata_aws_lambda_function_edi-TenderMsgFunction-CI44xHeEeKTe" {
    triggers = {
        resource_name = "aws_lambda_function.edi-TenderMsgFunction-CI44xHeEeKTe"
        resource_type = "ZIP_LAMBDA_FUNCTION"
        original_source_code = "${local.lambda_src_path}"
        built_output_path = "${local.building_path}/${local.lambda_code_filename}"
    }
    depends_on = [
        null_resource.build_lambda_function
    ]
}

data "archive_file" "lambda" {
  type        = "zip"
  source_dir = "./src"
  output_path = "${local.building_path}/${local.lambda_code_filename}"
}

resource "aws_iam_role" "edi-TenderMsgFunctionRole-1OY1LYYV71U88" {
  name               = "edi-TenderMsgFunctionRole-1OY1LYYV71U88"
  assume_role_policy = "{\"Statement\":[{\"Action\":\"sts:AssumeRole\",\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"lambda.amazonaws.com\"}}],\"Version\":\"2012-10-17\"}"
}

resource "aws_iam_role_policy_attachment" "AmazonSQSFullAccess" {
  role       = "edi-TenderMsgFunctionRole-1OY1LYYV71U88"
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
}

resource "aws_iam_role_policy_attachment" "AWSLambdaBasicExecutionRole" {
  role       = "edi-TenderMsgFunctionRole-1OY1LYYV71U88"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role" "AWSCloud9SSMAccessRole" {
  name               = "AWSCloud9SSMAccessRole"
  assume_role_policy = "{\"Statement\":[{\"Action\":\"sts:AssumeRole\",\"Effect\":\"Allow\",\"Principal\":{\"Service\":[\"cloud9.amazonaws.com\",\"ec2.amazonaws.com\"]}}],\"Version\":\"2012-10-17\"}"
  path               = "/service-role/"
}

resource "aws_iam_role" "api-gateway-to-sqs" {
  name               = "api-gateway-to-sqs"
  assume_role_policy = "{\"Statement\":[{\"Action\":\"sts:AssumeRole\",\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"apigateway.amazonaws.com\"},\"Sid\":\"\"}],\"Version\":\"2012-10-17\"}"
  description        = "Allows API Gateway to send to SQS"
}

resource "aws_iam_role_policy_attachment" "AmazonAPIGatewayPushToCloudWatchLogs" {
  role       = "api-gateway-to-sqs"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_iam_role_policy_attachment" "api-send-to-sqs" {
  role       = "api-gateway-to-sqs"
  policy_arn = "arn:aws:iam::186314775128:policy/api-send-to-sqs"
}

resource "aws_iam_policy" "api-send-to-sqs" {
  name          = "api-send-to-sqs"
  description   = "test sending edi files to sqs via api gateway"
  policy        = "{\"Statement\":[{\"Action\":[\"sqs:SendMessage\"],\"Effect\":\"Allow\",\"Resource\":[\"arn:aws:sqs:us-east-1:186314775128:edi-queue.fifo\"]}],\"Version\":\"2012-10-17\"}"
}

resource "aws_db_instance" "mysqlforlambda" {
  instance_class        = "db.t3.micro"
  storage_encrypted     = true
  apply_immediately     = null
  copy_tags_to_snapshot = true
  max_allocated_storage = 1000
  publicly_accessible   = true
  skip_final_snapshot   = true
}


