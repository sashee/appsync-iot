provider "aws" {
}

resource "random_id" "id" {
  byte_length = 8
}

resource "aws_iam_role" "appsync" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "appsync.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

data "aws_iam_policy_document" "appsync" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:*:*:*"
    ]
  }
  statement {
    actions = [
      "iot:GetThingShadow",
      "iot:UpdateThingShadow",
    ]
    resources = [
      "${aws_iot_thing.thing.arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "appsync_logs" {
  role   = aws_iam_role.appsync.id
  policy = data.aws_iam_policy_document.appsync.json
}

resource "aws_appsync_graphql_api" "appsync" {
  name                = "appsync_test"
  schema              = file("schema.graphql")
  authentication_type = "AWS_IAM"
  log_config {
    cloudwatch_logs_role_arn = aws_iam_role.appsync.arn
    field_log_level          = "ALL"
  }
}

resource "aws_cloudwatch_log_group" "loggroup" {
  name              = "/aws/appsync/apis/${aws_appsync_graphql_api.appsync.id}"
  retention_in_days = 14
}

resource "aws_iot_thing" "thing" {
  name = "thing_${random_id.id.hex}"
}

data "aws_region" "current" {}

data "aws_iot_endpoint" "iot_endpoint" {
	endpoint_type = "iot:Data-ATS"
}

resource "aws_appsync_datasource" "shadow" {
  api_id           = aws_appsync_graphql_api.appsync.id
  name             = "shadow"
  service_role_arn = aws_iam_role.appsync.arn
  type             = "HTTP"
	http_config {
		endpoint = "https://${data.aws_iot_endpoint.iot_endpoint.endpoint_address}"
		authorization_config {
			authorization_type = "AWS_IAM"
			aws_iam_config {
				signing_region = data.aws_region.current.name
				signing_service_name = "iotdevicegateway"
			}
		}
	}
}

resource "aws_appsync_function" "get_value" {
  api_id      = aws_appsync_graphql_api.appsync.id
  data_source = aws_appsync_datasource.shadow.name
  name                     = "get_value"
  request_mapping_template = <<EOF
{
	"version": "2018-05-29",
	"method": "GET",
	"params": {
		"query": {
			"name": "test"
		},
	},
	"resourcePath": "/things/${aws_iot_thing.thing.name}/shadow"
}
EOF

  response_mapping_template = <<EOF
#if ($ctx.error)
	$util.error($ctx.error.message, $ctx.error.type)
#end
#if ($ctx.result.statusCode == 404)
	#return(0)
#end
#if ($ctx.result.statusCode < 200 || $ctx.result.statusCode >= 300)
	$util.error($ctx.result.body, "StatusCode$ctx.result.statusCode")
#end
$util.toJson($util.parseJson($ctx.result.body).state.reported.value)
EOF
}

resource "aws_appsync_function" "increase" {
  api_id      = aws_appsync_graphql_api.appsync.id
  data_source = aws_appsync_datasource.shadow.name
  name                     = "increase"
  request_mapping_template = <<EOF
#set($newVal = $ctx.prev.result + 1)
{
	"version": "2018-05-29",
	"method": "POST",
	"params": {
		"query": {
			"name": "test"
		},
		"body": $util.toJson({
			"state": {"reported": {"value": $newVal}}
		})
	},
	"resourcePath": "/things/${aws_iot_thing.thing.name}/shadow"
}
EOF

  response_mapping_template = <<EOF
#if ($ctx.error)
	$util.error($ctx.error.message, $ctx.error.type)
#end
#if ($ctx.result.statusCode < 200 || $ctx.result.statusCode >= 300)
	$util.error($ctx.result.body, "StatusCode$ctx.result.statusCode")
#end
$util.toJson($util.parseJson($ctx.result.body).state.reported.value)
EOF
}


resource "aws_appsync_resolver" "Query_current" {
  api_id      = aws_appsync_graphql_api.appsync.id
  type        = "Query"
  field       = "current"
  request_template  = "{}"
  response_template = "$util.toJson($ctx.result)"
  kind              = "PIPELINE"
  pipeline_config {
    functions = [
      aws_appsync_function.get_value.function_id,
    ]
  }
}

resource "aws_appsync_resolver" "Mutation_increase" {
  api_id      = aws_appsync_graphql_api.appsync.id
  type        = "Mutation"
  field       = "increase"
  request_template  = "{}"
  response_template = "$util.toJson($ctx.result)"
  kind              = "PIPELINE"
  pipeline_config {
    functions = [
      aws_appsync_function.get_value.function_id,
      aws_appsync_function.increase.function_id,
    ]
  }
}

