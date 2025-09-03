variable "INVOKEAI_VERSION" {
  default = "v6.5.1"
}

target "invokeai" {
  context = "./invokeai"
  tags = ["andyhite/invokeai:latest", "andyhite/invokeai:${INVOKEAI_VERSION}"]
  platforms = ["linux/amd64"]
  args = {
    VERSION = "${INVOKEAI_VERSION}"
  }
}

group "default" {
  targets = ["invokeai"]
}
