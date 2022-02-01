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

///////////////
// IPAM data //
///////////////

resource "netris_allocation" "oob" {
  name = "OOB"
  prefix = "192.168.200.0/24"
  tenantid = data.netris_tenant.admin.id
}

resource "netris_allocation" "loopback" {
  name = "LOOPBACK"
  prefix = "192.0.2.0/24"
  tenantid = data.netris_tenant.admin.id
}

resource "netris_allocation" "common" {
  name = "COMMON"
  prefix = "10.0.0.0/8"
  tenantid = data.netris_tenant.admin.id
}

resource "netris_allocation" "public" {
  name = "PUBLIC"
  prefix = "198.51.100.0/24"
  tenantid = data.netris_tenant.admin.id
}

resource "netris_subnet" "oob-subnet" {
  name = "OOB-SUBNET"
  prefix = "192.168.200.0/24"
  tenantid = data.netris_tenant.admin.id
  purpose = "management"
  siteids = [data.netris_site.default.id]
  depends_on = [
    netris_allocation.oob,
  ]
}

resource "netris_subnet" "lo-subnet" {
  name = "LOOPBACK-SUBNET"
  prefix = "192.0.2.0/24"
  tenantid = data.netris_tenant.admin.id
  purpose = "loopback"
  siteids = [data.netris_site.default.id]
  depends_on = [
    netris_allocation.loopback,
  ]
}

resource "netris_subnet" "subnet-one" {
  name = "SUBNET-ONE"
  prefix = "10.0.1.0/24"
  tenantid = data.netris_tenant.admin.id
  purpose = "common"
  siteids = [data.netris_site.default.id]
  depends_on = [
    netris_allocation.common,
  ]
}

resource "netris_subnet" "subnet-two" {
  name = "SUBNET-TWO"
  prefix = "10.0.2.0/24"
  tenantid = data.netris_tenant.admin.id
  purpose = "common"
  siteids = [data.netris_site.default.id]
  depends_on = [
    netris_allocation.common,
  ]
}

resource "netris_subnet" "nat" {
  name = "PUBLIC-NAT"
  prefix = "198.51.100.0/25"
  tenantid = data.netris_tenant.admin.id
  purpose = "nat"
  siteids = [data.netris_site.default.id]
  depends_on = [
    netris_allocation.public,
  ]
}

resource "netris_subnet" "lb" {
  name = "PUBLIC-LB"
  prefix = "198.51.100.128/25"
  tenantid = data.netris_tenant.admin.id
  purpose = "load-balancer"
  siteids = [data.netris_site.default.id]
  depends_on = [
    netris_allocation.public,
  ]
}

/////////////
// Devices //
/////////////

resource "netris_switch" "leaf0" {
  name = "leaf0"
  tenantid = data.netris_tenant.admin.id
  nos = "cumulus_linux"
  portcount = 16
  asnumber = "4200000000"
  siteid = data.netris_site.default.id
  mainip = "192.0.2.4"
  mgmtip = "192.168.200.4"
}

resource "netris_switch" "leaf1" {
  name = "leaf1"
  tenantid = data.netris_tenant.admin.id
  nos = "cumulus_linux"
  portcount = 16
  asnumber = "4200000001"
  siteid = data.netris_site.default.id
  mainip = "192.0.2.5"
  mgmtip = "192.168.200.5"
}

resource "netris_switch" "leaf2" {
  name = "leaf2"
  tenantid = data.netris_tenant.admin.id
  nos = "cumulus_linux"
  portcount = 16
  asnumber = "4200000002"
  siteid = data.netris_site.default.id
  mainip = "192.0.2.6"
  mgmtip = "192.168.200.6"
}

resource "netris_switch" "leaf3" {
  name = "leaf3"
  tenantid = data.netris_tenant.admin.id
  nos = "cumulus_linux"
  portcount = 16
  asnumber = "4200000003"
  siteid = data.netris_site.default.id
  mainip = "192.0.2.7"
  mgmtip = "192.168.200.7"
}

resource "netris_switch" "spine0" {
  name = "spine0"
  tenantid = data.netris_tenant.admin.id
  nos = "cumulus_linux"
  portcount = 16
  asnumber = "4200000099"
  siteid = data.netris_site.default.id
  mainip = "192.0.2.2"
  mgmtip = "192.168.200.2"
}

resource "netris_switch" "spine1" {
  name = "spine1"
  tenantid = data.netris_tenant.admin.id
  nos = "cumulus_linux"
  portcount = 16
  asnumber = "4200000098"
  siteid = data.netris_site.default.id
  mainip = "192.0.2.3"
  mgmtip = "192.168.200.3"
}

resource "netris_softgate" "border0" {
  name = "border0"
  tenantid = data.netris_tenant.admin.id
  siteid = data.netris_site.default.id
  mainip = "192.0.2.13"
  mgmtip = "192.168.200.13"
}

resource "netris_softgate" "border1" {
  name = "border1"
  tenantid = data.netris_tenant.admin.id
  siteid = data.netris_site.default.id
  mainip = "192.0.2.14"
  mgmtip = "192.168.200.14"
}


///////////
// Links //
///////////

resource "netris_link" "l0s0" {
  ports = [
    "swp1@leaf0",
    "swp1@spine0"
  ]
}

resource "netris_link" "l0s1" {
  ports = [
    "swp2@leaf0",
    "swp1@spine1"
  ]
}

resource "netris_link" "l1s0" {
  ports = [
    "swp1@leaf1",
    "swp2@spine0"
  ]
}

resource "netris_link" "l1s1" {
  ports = [
    "swp2@leaf1",
    "swp2@spine1"
  ]
}

resource "netris_link" "l2s0" {
  ports = [
    "swp1@leaf2",
    "swp3@spine0"
  ]
}

resource "netris_link" "l2s1" {
  ports = [
    "swp2@leaf2",
    "swp3@spine1"
  ]
}

resource "netris_link" "l3s0" {
  ports = [
    "swp1@leaf3",
    "swp4@spine0"
  ]
}

resource "netris_link" "l3s1" {
  ports = [
    "swp2@leaf3",
    "swp4@spine1"
  ]
}

resource "netris_link" "l2b0" {
  ports = [
    "swp5@leaf2",
    "swp1@border0"
  ]
}

resource "netris_link" "l3b1" {
  ports = [
    "swp5@leaf3",
    "swp1@border1"
  ]
}