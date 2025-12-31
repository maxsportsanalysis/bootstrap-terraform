terraform {
  backend "s3" {
    bucket       = ""
    key          = ""
    region       = ""
    profile      = ""
    encrypt      = true
    use_lockfile = true
  }
}