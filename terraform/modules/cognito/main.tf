# Customer user pool
resource "aws_cognito_user_pool" "customers" {
  name = "${var.name}-customers"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  mfa_configuration = "OPTIONAL"
  software_token_mfa_configuration { enabled = true }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "ShopCloud – Verify your email"
    email_message        = "Your verification code is {####}"
  }

  user_pool_add_ons {
    advanced_security_mode = "ENFORCED"
  }

  schema {
    name                     = "email"
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    required                 = true
    string_attribute_constraints {
      min_length = 5
      max_length = 254
    }
  }

  schema {
    name                     = "name"
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    required                 = true
    string_attribute_constraints {
      min_length = 1
      max_length = 100
    }
  }

  tags = var.tags
}

resource "aws_cognito_user_pool_client" "customers" {
  name         = "${var.name}-customers-client"
  user_pool_id = aws_cognito_user_pool.customers.id

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]

  access_token_validity  = 1    # hours
  id_token_validity      = 1
  refresh_token_validity = 30   # days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  prevent_user_existence_errors = "ENABLED"
  generate_secret               = false
}

# Admin user pool
resource "aws_cognito_user_pool" "admins" {
  name = "${var.name}-admins"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 16
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 1
  }

  mfa_configuration = "ON"
  software_token_mfa_configuration { enabled = true }

  user_pool_add_ons {
    advanced_security_mode = "ENFORCED"
  }

  tags = var.tags
}

resource "aws_cognito_user_pool_client" "admins" {
  name         = "${var.name}-admins-client"
  user_pool_id = aws_cognito_user_pool.admins.id

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]

  access_token_validity  = 8    # hours (workday)
  id_token_validity      = 8
  refresh_token_validity = 1

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  prevent_user_existence_errors = "ENABLED"
  generate_secret               = true
}

resource "aws_cognito_user_group" "admins" {
  name         = "admins"
  user_pool_id = aws_cognito_user_pool.admins.id
  description  = "ShopCloud administrators"
}
