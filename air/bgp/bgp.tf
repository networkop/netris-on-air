terraform {
  required_providers {
    netris = {
      source  = "netrisai/netris"
    }
  }
  required_version = ">= 0.13"
}

provider "netris" {
  login = "netris"
  password = "newNet0ps"
}

data "netris_tenant" "admin" {
    name = "Admin"
}

data "netris_site" "default" {
    name = "Default"
}

data "netris_port" "border0-eth2" {
    name = "swp2@border0"
}

data "netris_port" "border1-eth2" {
    name = "swp2@border1"
}

resource "netris_bgp" "border0-bgp" {
   name = "INTERNET-1"
   siteid = data.netris_site.default.id
   hardware = "border0"
   neighboras = 64512
   portid = data.netris_port.border0-eth2.id
   localip = "100.64.0.2/30"
   remoteip = "100.64.0.1/30"
   state = "enabled"
}

resource "netris_bgp" "border1-bgp" {
   name = "INTERNET-2"
   siteid = data.netris_site.default.id
   hardware = "border1"
   neighboras = 64512
   portid = data.netris_port.border1-eth2.id
   localip = "100.64.0.6/30"
   remoteip = "100.64.0.5/30"
   state = "enabled"
}