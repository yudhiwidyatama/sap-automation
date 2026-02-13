# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.


locals {

  version_label                        = trimspace(file("${path.module}/../../../configs/version.txt"))
  // The environment of sap landscape and sap system
  environment                          = upper(local.infrastructure.environment)
  vnet_sap_arm_id                      = try(data.terraform_remote_state.landscape.outputs.vnet_sap_arm_id, "")

  vnet_logical_name                    = local.infrastructure.virtual_networks.sap.logical_name
  vnet_sap_exists                      = length(local.vnet_sap_arm_id) > 0 ? true : false


  db_sid                              =  coalesce(
                                           var.database_sid,

                                           upper(var.database_platform) == "HANA" ? (
                                             "HDB"
                                             ) : (
                                           coalesce(var.sid,substr(var.database_platform, 0, 3)))
                                         )

  sap_sid                             = upper(try(local.application_tier.sid, local.db_sid))
  web_sid                             = upper(try(var.web_sid, local.sap_sid))

  enable_db_deployment                = length(local.database.platform) > 0

  db_zonal_deployment                 = length(try(local.database.zones, [])) > 0

  // Locate the tfstate storage account


  parsed_id                           = provider::azurerm::parse_resource_id(var.tfstate_resource_id)

  SAPLibrary_subscription_id          = local.parsed_id["subscription_id"]
  SAPLibrary_resource_group_name      = local.parsed_id["resource_group_name"]
  tfstate_storage_account_name        = local.parsed_id["resource_name"]
  tfstate_container_name              = module.sap_namegenerator.naming.resource_suffixes.tfstate

  // Retrieve the arm_id of deployer's Key Vault
  spn_key_vault_arm_id               = trimspace(coalesce(
                                         var.spn_keyvault_id,
                                         try(data.terraform_remote_state.landscape.outputs.landscape_key_vault_spn_arm_id, ""),
                                         try(data.terraform_remote_state.deployer[0].outputs.deployer_kv_user_arm_id, ""),
                                         " "
                                       ))

  deployer_subscription_id           = length(local.spn_key_vault_arm_id) > 0 ? split("/", local.spn_key_vault_arm_id)[2] : ""

  // Custom naming: Load from JSON file (jsondecode creates tuples from JSON arrays)
  custom_names_raw                   = length(var.name_override_file) > 0 ? (
                                        jsondecode(file(format("%s/%s", path.cwd, var.name_override_file)))) : (
                                        null
                                      )

  // Convert specific attributes from tuple to list to match sap_namegenerator types
  // Per Build 143 debug output, only ANYDB_* and HANA_* attributes are lists in generator
  // All others (ANCHOR, SCS, etc) are tuples in generator, so leave custom naming as tuples
  // See: ~/docs/actual_sap_namegenerator_types_from_build143.md
  // Using tolist() explicitly to force type conversion
  custom_names                       = local.custom_names_raw == null ? null : {
                                        for k, v in local.custom_names_raw :
                                        k => (
                                          k == "virtualmachine_names" ? {
                                            for vm_key, vm_val in v :
                                            vm_key => (
                                              contains([
                                                "ANYDB_COMPUTERNAME",
                                                "ANYDB_VMNAME",
                                                "HANA_COMPUTERNAME",
                                                "HANA_SECONDARY_DNSNAME",
                                                "HANA_VMNAME"
                                              ], vm_key) ? tolist(vm_val) : vm_val  # Use tolist() to explicitly convert tuple → list
                                            )
                                          } : v
                                        )
                                      }

  workload_zone_name                 = coalesce(var.workload_zone_name, upper(format("%s-%s-%s", var.environment, module.sap_namegenerator.naming_new.location_short, var.network_logical_name)))
}
