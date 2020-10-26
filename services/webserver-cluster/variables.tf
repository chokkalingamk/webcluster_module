variable "cluster_name" {
    description = "the name to use for all the clsuter resoruces"
    type = string
}

variable "db_remote_state_bucket" {
    description = "The name of the S3 bucket for the databases remote state"
    type = string
}

variable "db_remote_state_key" {
    description = "The path for the databses remote state in S3"
    type = string
}

variable "instance_type" {
    description = "The type of Ec2 Instances to run"
    type = string
}

variable "min_size" {
    description = "The minimum number of Ec2 Instances in the ASG"
    type = number
}

variable "max_size" {
    description = "The maximum number of ec2 instances in the ASG"
    type = number
}

variable "custom_tags" {
    description = "Custom tags to set on the instances in the ASG"
    type = map(string)
    default = {}
}

variable "enable_autoscaling" {
    description = "if set to true, enable auto scalling"
    type = bool
}