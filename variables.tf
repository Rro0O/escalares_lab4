variable "aws_region" {
  description = "Región de AWS donde se despliega la infraestructura."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Perfil de AWS CLI a usar (p.ej. \"academy\" en AWS Academy). Las credenciales de Academy expiran cada pocas horas: renuévalas en el portal del Learner Lab si terraform plan/apply falla con ExpiredToken."
  type        = string
  default     = "academy"
}

variable "project_name" {
  description = "Prefijo para nombrar los recursos."
  type        = string
  default     = "dashboard-metrics"
}

variable "environment" {
  description = "Nombre del ambiente (dev, staging, prod)."
  type        = string
  default     = "dev"
}

# --- Red ---------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR de la VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDRs de las subnets privadas (una por AZ). Lambda, RDS y ElastiCache viven aquí."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

# --- RDS (PostgreSQL) --------------------------------------------------------

variable "db_name" {
  description = "Nombre de la base de datos."
  type        = string
  default     = "metrics"
}

variable "db_username" {
  description = "Usuario maestro de RDS."
  type        = string
  default     = "metrics_admin"
}

variable "db_instance_class" {
  description = "Clase de instancia de RDS."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_engine_version" {
  description = "Versión de PostgreSQL."
  type        = string
  default     = "16"
}

variable "db_allocated_storage" {
  description = "Almacenamiento inicial de RDS en GB."
  type        = number
  default     = 20
}

variable "db_multi_az" {
  description = "Habilitar Multi-AZ en RDS."
  type        = bool
  default     = false
}

# --- ElastiCache (Redis) -----------------------------------------------------

variable "cache_node_type" {
  description = "Tipo de nodo de ElastiCache."
  type        = string
  default     = "cache.t4g.micro"
}

variable "cache_engine_version" {
  description = "Versión de Redis."
  type        = string
  default     = "7.1"
}

variable "cache_ttl_seconds" {
  description = "TTL de las métricas en caché (Cache-Aside). 300 s = 5 minutos."
  type        = number
  default     = 300
}

# --- Lambda ------------------------------------------------------------------

variable "lambda_zip_path" {
  description = "Ruta al paquete de la Lambda generado por build.sh."
  type        = string
  default     = "build/lambda.zip"
}

variable "existing_lambda_role_name" {
  description = "Rol IAM existente para la Lambda (\"LabRole\" en AWS Academy). null = Terraform crea el rol."
  type        = string
  default     = null
}

variable "lambda_memory_mb" {
  description = "Memoria asignada a la Lambda."
  type        = number
  default     = 256
}

variable "lambda_timeout_seconds" {
  description = "Timeout de la Lambda (debe cubrir el peor caso: cache miss + consulta a RDS)."
  type        = number
  default     = 15
}

variable "cors_allow_origins" {
  description = "Orígenes permitidos para el frontend del dashboard."
  type        = list(string)
  default     = ["*"]
}
