# ── Region ────────────────────────────────────────────────────────────────
variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-southeast-2"
}

# ── Naming ────────────────────────────────────────────────────────────────
variable "project" {
  description = "Short project name used as a prefix for all resource names."
  type        = string
  default     = "agentic-ide"
}

# ── Networking ────────────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "CIDR blocks for the two public subnets (ALB + EC2)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  description = "CIDR blocks for the two private subnets (Aurora)."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

# ── EC2 ───────────────────────────────────────────────────────────────────
variable "ec2_instance_type" {
  description = "EC2 instance type. g4dn.xlarge provides a T4 GPU for vLLM."
  type        = string
  default     = "g4dn.xlarge"
}

variable "key_pair_name" {
  description = "Name of the existing EC2 key pair in ap-southeast-2."
  type        = string
  default     = "CAD-DA2 SSH ACCESS KEY"
}

variable "ec2_root_volume_gb" {
  description = "Root EBS volume size in GiB. 60 GB leaves room for the model weights."
  type        = number
  default     = 60
}

# ── S3 ────────────────────────────────────────────────────────────────────
variable "s3_bucket_name" {
  description = "Globally unique S3 bucket name for workspace files."
  type        = string
  default     = "tharun-gopinath-1086-CAD-DA2"
}

# ── Aurora ────────────────────────────────────────────────────────────────
variable "db_name" {
  description = "Initial database name inside Aurora."
  type        = string
  default     = "agenticide"
}

variable "db_username" {
  description = "Master username for Aurora PostgreSQL."
  type        = string
  default     = "ideadmin"
}

variable "db_password" {
  description = "Master password for Aurora PostgreSQL. Override via TF_VAR_db_password."
  type        = string
  sensitive   = true
  default     = "change-me-db-pass"
}

# ── App auth ──────────────────────────────────────────────────────────────
variable "ide_user" {
  description = "HTTP Basic Auth username for the IDE."
  type        = string
  default     = "admin"
}

variable "ide_pass" {
  description = "HTTP Basic Auth password for the IDE. Override via TF_VAR_ide_pass."
  type        = string
  sensitive   = true
  default     = "change-me-ide-pass"
}

# ── LLM ───────────────────────────────────────────────────────────────────
variable "llm_model" {
  description = "HuggingFace model ID served by vLLM."
  type        = string
  default     = "Qwen/Qwen2.5-Coder-7B-Instruct-AWQ"
}

variable "idle_minutes" {
  description = "Minutes of inactivity before EC2 auto-stops."
  type        = number
  default     = 30
}
