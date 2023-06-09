# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

locals {
  building_path = "build"
  lambda_code_filename = "tender_msg.zip"
  lambda_src_path = "./src"
  account = "186314775128"
  stage_name = "v1"

  # add either arn or filepath/name for lambda layer
}