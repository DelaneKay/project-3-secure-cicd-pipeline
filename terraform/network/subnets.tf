resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.lab.id
  availability_zone       = var.availability_zones[count.index]
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-${count.index + 1}"
    Project     = var.project_name
    Environment = "lab"
    ManagedBy   = "Terraform"
    Tier        = "public"
  }
}

resource "aws_subnet" "private" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.lab.id
  availability_zone       = var.availability_zones[count.index]
  cidr_block              = var.private_subnet_cidrs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name        = "${var.project_name}-private-${count.index + 1}"
    Project     = var.project_name
    Environment = "lab"
    ManagedBy   = "Terraform"
    Tier        = "private"
  }
}
