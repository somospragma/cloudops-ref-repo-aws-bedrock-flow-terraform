# AWS Bedrock Agent Flow Module - Variables
variable "profile" {
  description = "AWS profile to use"
  type        = string
  default     = "default"
}

variable "client" {
  description = "Client name for resource naming and tagging"
  type        = string
}

variable "project" {
  description = "Project name for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  validation {
    condition     = contains(["dev", "qa", "pdn"], var.environment)
    error_message = "Environment must be one of: dev, qa, pdn."
  }
}

variable "flow_description" {
  description = "Description of the Bedrock Agent Flow"
  type        = string
  default     = "Bedrock Agent Flow for processing requests"
}

variable "execution_role_arn" {
  description = "ARN of the IAM role for flow execution"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for encryption"
  type        = string
  default     = null
}

variable "flow_nodes" {
  description = "Dynamic flow nodes configuration"
  type = any

  validation {
    condition = alltrue([
      for k, v in var.flow_nodes : contains(["Input", "Output", "Prompt", "LambdaFunction", "Collector", "Condition"], v.type)
    ])
    error_message = "Node type must be one of: Input, Output, Prompt, LambdaFunction, Collector, Condition"
  }
}

variable "flow_connections" {
  description = "Flow connections between nodes (required)"
  type = list(object({
    name          = string
    source        = string
    target        = string
    type          = optional(string, "Data")  # "Data" or "Conditional"
    source_output = optional(string)
    target_input  = optional(string)
    condition     = optional(string)  # For Conditional type
  }))

  validation {
    condition = alltrue([
      for conn in var.flow_connections :
      conn.type == "Data" ? (conn.source_output != null && conn.target_input != null) :
      conn.type == "Conditional" ? conn.condition != null : false
    ])
    error_message = "Data connections require source_output and target_input. Conditional connections require condition."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "create_flow_version" {
  description = "Whether to create a flow version"
  type        = bool
  default     = false
}

variable "flow_version_description" {
  description = "Description for the flow version"
  type        = string
  default     = "Flow version"
}

variable "create_flow_alias" {
  description = "Whether to create a flow alias"
  type        = bool
  default     = false
}

variable "flow_alias_name" {
  description = "Name for the flow alias"
  type        = string
  default     = "live"
}

variable "flow_alias_description" {
  description = "Description for the flow alias"
  type        = string
  default     = "Flow alias"
}

variable "prepare_flow" {
  description = "Whether to prepare the flow using AWS CLI"
  type        = bool
  default     = false
}

variable "aws_role_arn" {
  description = "AWS role ARN for cli execution"
  type        = string
}

variable "aws_region" {
  description = "AWS region for cli execution"
  type        = string
} 