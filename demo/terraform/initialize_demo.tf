####### Referencing other terraform output ######

data "terraform_remote_state" "workshop" {
  backend = "local"

  config = {
    path = "${path.module}/../tmp/.terraform_staging/terraform.tfstate"
  }
}

resource "null_resource" "init_demo" {

// Copy init_demo script to the VM
  provisioner "file" {
    source      = "${path.module}/init_demo.sh"
    destination = "/tmp/init_demo.sh"

    connection {
      user     = var.ssh_user
      password = var.ssh_password
      insecure = true
      host     = var.vm_host
    }
  }

  provisioner "file" {
    content      = templatefile("${path.module}/deploy_docs.tpl", { 
      ext_ip = var.vm_host
    })
    destination = "/tmp/deploy_docs.sh"

    connection {
      user     = var.ssh_user
      password = var.ssh_password
      insecure = true
      host     = var.vm_host
    }
  }

  // Copy docs to the VM
  provisioner "file" {
    source      = "../asciidoc/"
    destination = ".workshop/docker/asciidoc"

    connection {
      user     = var.ssh_user
      password = var.ssh_password
      insecure = true
      host     = var.vm_host
    }
  }

  // Execute deploy_docs script on the VM to deploy docs
  provisioner "remote-exec" {
    inline = [
      "sleep 30",
      "chmod +x /tmp/deploy_docs.sh",
      "/tmp/deploy_docs.sh"
    ]

    connection {
      user     = var.ssh_user
      password = var.ssh_password
      insecure = true
      host     = var.vm_host
    }
  }
  

  // Execute init_demo script on the VM to initialize the demo
  provisioner "remote-exec" {
    inline = [
      "sleep 30",
      "chmod +x /tmp/init_demo.sh",
      "/tmp/init_demo.sh"
    ]

    connection {
      user     = var.ssh_user
      password = var.ssh_password
      insecure = true
      host     = var.vm_host
    }
  }

}

####### AWS Lambda ###########

resource "random_string" "lambda_func_random_string" {
  length = 4
  special = false
  upper = false
  lower = true
  number = false
}


data "archive_file" "lambda_zip_file" {
  type        = "zip"
  output_path = "../tmp/get_customer_360.zip"
  source {
    content  = templatefile("${path.module}/get_customer_360.py.tpl", { 
      dynamodb_table_name = data.terraform_remote_state.workshop.outputs.dynamodb_table_name
    })
    filename = "lambda_function.py"
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda-confluent-demo-${random_string.lambda_func_random_string.result}"

  assume_role_policy = <<EOF
{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Effect": "Allow",
			"Principal": {
				"Service": "lambda.amazonaws.com"
			},
			"Action": "sts:AssumeRole"
		}
	]
}
EOF
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess"
}


resource "aws_lambda_function" "get_customer_360" {
  filename         = data.archive_file.lambda_zip_file.output_path
  function_name    = "get_customer_360_${random_string.lambda_func_random_string.result}"
  role             = aws_iam_role.iam_for_lambda.arn
  source_code_hash = filebase64sha256(data.archive_file.lambda_zip_file.output_path)
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.8"
}


####### API Gateway Integration ###########

resource "aws_api_gateway_rest_api" "api" {
  name = "demo-aws-confluent-api-${random_string.lambda_func_random_string.result}"
  binary_media_types = ["*/*"]
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "resource" {
  path_part   = "get_customer_360_${random_string.lambda_func_random_string.result}"
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.api.id
}

resource "aws_api_gateway_method" "method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "integration" {
  depends_on  = [aws_api_gateway_method.method, aws_lambda_function.get_customer_360]
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.resource.id
  http_method             = aws_api_gateway_method.method.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = aws_lambda_function.get_customer_360.invoke_arn
}

resource "aws_api_gateway_method_response" "response_200" {
  depends_on  = [aws_api_gateway_method.method]
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.method.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "integration_response" {
  depends_on  = [aws_api_gateway_integration.integration, aws_api_gateway_method_response.response_200]
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.method.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_customer_360.function_name
  principal     = "apigateway.amazonaws.com"

  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn = "${aws_api_gateway_rest_api.api.execution_arn}/*/${aws_api_gateway_method.method.http_method}${aws_api_gateway_resource.resource.path}"
}





####### Variables ###########

variable "ssh_user" {
  description = "SSH Username to connect to the VM"
}

variable "ssh_password" {
  description = "SSH password to connect to the VM"
}

variable "vm_host" {
  description = "VM HOST , will be used to ssh"
}





 