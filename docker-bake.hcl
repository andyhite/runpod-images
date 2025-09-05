variable "INVOKEAI_VERSION" {
  default = env.INVOKEAI_VERSION != "" ? env.INVOKEAI_VERSION : "v6.5.1"
}

target "invokeai" {
  context = "./services/invokeai"
  tags = ["andyhite/invokeai:latest", "andyhite/invokeai:${INVOKEAI_VERSION}"]
  platforms = ["linux/amd64"]
  args = {
    VERSION = "${INVOKEAI_VERSION}"
  }
}

group "default" {
  targets = ["invokeai"]
}
