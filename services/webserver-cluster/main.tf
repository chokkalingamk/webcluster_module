provider "aws" {
    region = "us-east-2"
}

resource "aws_launch_configuration" "example" {
    image_id = "ami-0c55b159cbfafe1f0"
    instance_type = var.instance_type  // Fetch the variable information from Variable.tf
    security_groups = [aws_security_group.instance.id] 
    #Created Userdata script to publish the echo command to index.html
    user_data = data.template_file.user_data.rendered       // Calling the template file mentioned below
/*    user_data = <<-EOF
                #!/bin/bash
                echo "Hello, World" >> index.html
                echo "${data.terraform_remote_state.db.outputs.address}" >> index.html
                echo "${data.terraform_remote_state.db.outputs.port}" >> index.html
                nohup busybox httpd -f -p ${var.server_port} &
                EOF
*/
    # Required when using a launch configuration with an auto scaling group.
    # https://www.terraform.io/docs/providers/aws/r/launch_configuration.html
    #Lifecycle is to create the new instance 1st and point to new instance then proceed to delete the old instance
    lifecycle {
        create_before_destroy = true
    }
}

resource "aws_autoscaling_group" "example" {
    launch_configuration = aws_launch_configuration.example.name //calling launch configuration
    vpc_zone_identifier = data.aws_subnet_ids.default.ids   //using the subnets that are identified in subnet id's

    target_group_arns = [aws_lb_target_group.asg.arn]   //Target group resources 
    health_check_type = "ELB"

    min_size = var.min_size
    max_size = var.max_size

    tag { 
        key = "Name"
        value = var.cluster_name
        propagate_at_launch = true

    }
}

resource "aws_security_group" "instance" {
    name = "${var.cluster_name}-instance"

    ingress {
        from_port = var.server_port
        to_port = var.server_port
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

variable "server_port" {
    description = "The port the server will use for HTTP request"
    type = number
    default = 80
}

// Declaring the values once and refer in to the code as many times
locals {
    http_port = 80
    any_port = 0
    any_protocol = "-1"
    tcp_protocol = "tcp"
    all_ips = ["0.0.0.0/0"]
}

#Querying for default VPC id
data "aws_vpc" "default" {
    default = true
}

#querying for subnet details in the VPC
data "aws_subnet_ids" "default" {
    vpc_id = data.aws_vpc.default.id
}

#Creating ALB(Application LB)
resource "aws_lb" "example" {
    name = "${var.cluster_name}-asg-example"
    load_balancer_type = "application"
    subnets = data.aws_subnet_ids.default.ids
    security_groups = [aws_security_group.alb.id]
}

#Defining the listener for the LB
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port = local.http_port  //refercing local block
  protocol = "HTTP"

  #by default , return a simple 404 page
  default_action {
      type = "fixed-response"

      fixed_response {
          content_type = "text/plain"
          message_body = "404: page not found"
          status_code = 404
      }
  }
}

#security group for load balance to allow the ports to respond Old inline blocks has been replaced with seperate Resoruces
resource "aws_security_group" "alb" {
  name = "${var.cluster_name}-alb"
}
  #allow inbound HTTP requests
resource "aws_security_group_rule" "allow_http_inbound"{
    type    = "ingress"
    security_group_id = aws_security_group.alb.id   //referring to Security Group

    from_port = local.http_port
    to_port = local.http_port
    protocol = local.tcp_protocol
    cidr_blocks = local.all_ips
    
  }

  #allow all outbound requests
resource "aws_security_group_rule" "allow_all_outbound" {
    type    = "egress"
    security_group_id = aws_security_group.alb.id

    from_port = local.any_port
    to_port = local.any_port
    protocol = local.any_protocol
    cidr_blocks = local.all_ips
}

/*
#security group for load balance to allow the ports to respond
resource "aws_security_group" "alb" {
  name = "${var.cluster_name}-alb"

  #allow inbound HTTP requests
  ingress {
      from_port = local.http_port
      to_port = local.http_port
      protocol = local.tcp_protocol
      cidr_blocks = local.all_ips
  }
  #allow all outbound requests
  egress {
      from_port = local.any_port
      to_port = local.any_port
      protocol = local.any_protocol
      cidr_blocks = local.all_ips
  }
}
*/
#Target group resources 
resource "aws_lb_target_group" "asg" {
    name = "${var.cluster_name}-asg-example"
    port = var.server_port
    protocol = "HTTP"
    vpc_id = data.aws_vpc.default.id

    #defining healthprobe
    health_check {
        path = "/"
        protocol = "HTTP"
        matcher = "200"
        interval = 15
        timeout = 3
        healthy_threshold = 2
        unhealthy_threshold = 2
    }
  
}

#ALB Listener Rule
resource "aws_lb_listener_rule" "asg" {
    listener_arn = aws_lb_listener.http.arn
    priority = 100
    condition {
        path_pattern {
        values = ["*"]
        }
    }
    action {
        type = "forward"
        target_group_arn = aws_lb_target_group.asg.arn
    }
  
}

#Storing the tfstate in to the existing mysql tfstate file using remote state
data "terraform_remote_state" "db" {
  backend = "s3"
  config = {
    bucket = "terraform-up-and-running-chokk"
    key = "stage/data-stores/mysql/terraform.tfstate"
    region = "us-east-2"
  }
}

data "template_file" "user_data" {
    template = file("user-data.sh")     //using path.module to use the script

    vars = {
        server_port = var.server_port
        db_address = data.terraform_remote_state.db.outputs.address
        db_port = data.terraform_remote_state.db.outputs.port
    }
}
