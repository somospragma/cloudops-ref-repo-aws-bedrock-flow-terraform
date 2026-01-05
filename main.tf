# AWS Bedrock Agent Flow Module

locals {
  flow_name = "${var.client}-${var.project}-${var.environment}-flow"

  # Flow nodes without ordering
  flow_nodes = { for k, v in var.flow_nodes : k => merge(v, { name = k }) }

  # Direct mapping of flow connections
  flow_connections = var.flow_connections

  base_tags = {
    Name        = local.flow_name
    Environment = var.environment
    Project     = var.project
    Client      = var.client
  }
}

resource "aws_bedrockagent_flow" "main" {
  provider                    = aws.project
  name                        = local.flow_name
  description                 = var.flow_description
  execution_role_arn          = var.execution_role_arn
  customer_encryption_key_arn = var.kms_key_arn
  definition {
    dynamic "node" {
      for_each = local.flow_nodes
      content {
        name = node.key
        type = node.value.type

        dynamic "configuration" {
          for_each = node.value.type == "Input" ? [1] : []
          content {
            input {}
          }
        }

        dynamic "configuration" {
          for_each = node.value.type == "Output" ? [1] : []
          content {
            output {}
          }
        }

        dynamic "configuration" {
          for_each = node.value.type == "Prompt" ? [1] : []
          content {
            prompt {
              source_configuration {
                inline {
                  model_id      = coalesce(node.value.model_id, "amazon.nova-lite-v1:0")
                  template_type = "TEXT"
                  template_configuration {
                    text {
                      text = node.value.template_file != null ? file("${path.root}/${node.value.template_file}") : coalesce(node.value.template, "Default template for {{input}}")
                    }
                  }
                  inference_configuration {
                    text {
                      max_tokens  = node.value.max_tokens
                      temperature = node.value.temperature
                      top_p       = node.value.top_p
                    }
                  }
                }
              }
            }
          }
        }

        dynamic "configuration" {
          for_each = node.value.type == "LambdaFunction" ? [1] : []
          content {
            lambda_function {
              lambda_arn = node.value.lambda_arn
            }
          }
        }

        dynamic "configuration" {
          for_each = node.value.type == "Collector" ? [1] : []
          content {
            collector {}
          }
        }

        dynamic "configuration" {
          for_each = node.value.type == "Condition" ? [1] : []
          content {
            condition {
              dynamic "condition" {
                for_each = try(node.value.conditions, [])
                content {
                  name       = condition.value.name
                  expression = try(condition.value.expression, null)
                }
              }
            }
          }
        }

        # Dynamic Inputs - Use inputs list for all nodes
        dynamic "input" {
          for_each = try(length(node.value.inputs), 0) > 0 ? node.value.inputs : (
            node.value.type == "Output" ? [{
              name       = "document"
              type       = "String"
              expression = "$.data"
              }] : node.value.type == "Prompt" ? [{
              name       = "input"
              type       = "String"
              expression = "$.data"
              }] : node.value.type == "LambdaFunction" ? [{
              name       = "input"
              type       = "String"
              expression = "$.data"
              }] : node.value.type == "Collector" ? [{
              name       = "document"
              type       = "String"
              expression = "$.data"
              }] : node.value.type == "Condition" ? [{
              name       = "input"
              type       = "String"
              expression = "$.data"
            }] : []
          )
          content {
            expression = input.value.expression
            name       = input.value.name
            type       = input.value.type
          }
        }

        # Dynamic Outputs
        dynamic "output" {
          for_each = contains(["Input", "Prompt", "LambdaFunction", "Collector"], node.value.type) ? [1] : []
          content {
            name = node.value.type == "Input" ? "document" : (
              node.value.type == "Prompt" ? "modelCompletion" : (
                node.value.type == "Collector" ? "document" : "functionResponse"
              )
            )
            type = coalesce(node.value.output_type, "String")
          }
        }
      }
    }

    dynamic "connection" {
      for_each = local.flow_connections
      content {
        name   = connection.value.name
        source = connection.value.source
        target = connection.value.target
        type   = coalesce(connection.value.type, "Data")

        dynamic "configuration" {
          for_each = coalesce(connection.value.type, "Data") == "Data" ? [1] : []
          content {
            data {
              source_output = connection.value.source_output
              target_input  = connection.value.target_input
            }
          }
        }

        dynamic "configuration" {
          for_each = coalesce(connection.value.type, "Data") == "Conditional" ? [1] : []
          content {
            conditional {
              condition = connection.value.condition
            }
          }
        }
      }
    }
  }

  tags = merge(local.base_tags, var.additional_tags)

  lifecycle {
    ignore_changes = [created_at]
  }
}



resource "null_resource" "flow_prepare" {

  provisioner "local-exec" {
    command = <<EOF

      if [ -z "${var.aws_role_arn}" ]; then
          #Be sure to set AWS_PROFILE and AWS_DEFAULT_REGION variables
          #export AWS_PROFILE=dev
          #export AWS_DEFAULT_REGION=us-east-1

          echo "aws_role is empty, using profile AWS_PROFILE"
          aws bedrock-agent prepare-flow --flow-identifier ${aws_bedrockagent_flow.main.id}
      else
          echo "Deploy Role: ${var.aws_role_arn}"

          # Assume role to execute script in the target account
          TEMP_CREDS=$(aws sts assume-role --role-arn "${var.aws_role_arn}" --role-session-name "TerraformExecuteCMD" --output json)
        
          if [ $? -ne 0 ]; then
            echo "Error al asumir el rol ${var.aws_role_arn}"
            exit 1
          fi
          
          # Export temporary credentials
          export AWS_ACCESS_KEY_ID=$(echo $TEMP_CREDS | jq -r '.Credentials.AccessKeyId')
          export AWS_SECRET_ACCESS_KEY=$(echo $TEMP_CREDS | jq -r '.Credentials.SecretAccessKey')
          export AWS_SESSION_TOKEN=$(echo $TEMP_CREDS | jq -r '.Credentials.SessionToken')
          
          echo "Credentials exported"

          aws bedrock-agent prepare-flow --flow-identifier ${aws_bedrockagent_flow.main.id}
      fi
    EOF
  }


  depends_on = [aws_bedrockagent_flow.main]

  triggers = {
    flow_id = aws_bedrockagent_flow.main.updated_at
  }
}

resource "null_resource" "flow_alias" {
  count = var.create_flow_version ? 1 : 0
  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/create_alias.sh"
    environment = {
      FLOWID       = aws_bedrockagent_flow.main.id
      FLOWVERDESC  = var.flow_version_description
      ALIASNAME    = "${local.flow_name}-${uuid()}-alias"
      ALIASSDESC   = "Auto-generated alias for ${local.flow_name}"
      PROFILE      = var.profile
      AWS_ROLE_ARN = var.aws_role_arn
      AWS_REGION   = var.aws_region
    }
  }

  depends_on = [null_resource.flow_prepare]

  triggers = {
    flow_id = timestamp()
  }
}







