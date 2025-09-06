# =============================================================================
# Shared Variables and Functions
# =============================================================================

variable "REGISTRY" {
  default = "andyhite"
}

variable "PLATFORM" {
  default = "linux/amd64"
}

# Function to generate common tags for services
function "service_tags" {
  params = [service, version]
  result = ["${REGISTRY}/${service}:latest", "${REGISTRY}/${service}:${version}"]
}

# Common build arguments
function "common_args" {
  params = [version]
  result = {
    VERSION = version
  }
}

# =============================================================================
# Service-Specific Variables and Targets
# =============================================================================

# InvokeAI Configuration
variable "INVOKEAI_VERSION" {
  default = "v6.5.1"
}

target "invokeai" {
  context = "./services/invokeai"
  tags = service_tags("invokeai", INVOKEAI_VERSION)
  platforms = [PLATFORM]
  args = common_args(INVOKEAI_VERSION)
}

# =============================================================================
# Build Groups
# =============================================================================

# Default group - builds all services
group "default" {
  targets = ["invokeai"]
}

# Service-specific groups
group "invokeai" {
  targets = ["invokeai"]
}
