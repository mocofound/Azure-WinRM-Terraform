#create a public IP address for the virtual machine
resource "azurerm_public_ip" "win_pubip" {
  name                = "win_pubip"
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
  domain_name_label   = "${var.server_name}-${lower(substr("${join("", split(":", timestamp()))}", 8, -1))}"

  tags = {
    X-Dept        = var.tag_dept
    X-Customer    = var.tag_customer
    X-Project     = var.tag_project
    X-Application = var.tag_application
    X-Contact     = var.tag_contact
    X-TTL         = var.tag_ttl
  }
}

#create the network interface and put it on the proper vlan/subnet
resource "azurerm_network_interface" "win_ip" {
  name                = "win_ip"
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "win_ipconf"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "static"
    private_ip_address            = "10.1.1.10"
    public_ip_address_id          = azurerm_public_ip.win_pubip.id
  }

  tags = {
    X-Dept        = var.tag_dept
    X-Customer    = var.tag_customer
    X-Project     = var.tag_project
    X-Application = var.tag_application
    X-Contact     = var.tag_contact
    X-TTL         = var.tag_ttl
  }
}

#create the actual VM
resource "azurerm_virtual_machine" "win" {
  name                  = var.server_name
  location              = var.azure_region
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.win_ip.id]
  vm_size               = var.vm_size

  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }

  storage_os_disk {
    name              = "osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = var.server_name
    admin_username = var.username
    admin_password = var.password
    custom_data    = file("./files/winrm.ps1")
  }

#    os_profile_secrets {
#    source_vault_id = "${azurerm_key_vault.example.id}"
#
#    vault_certificates {
#      certificate_url   = "${azurerm_key_vault_certificate.example.secret_id}"
#      certificate_store = "My"
#    }
#  }

  os_profile_windows_config {
    provision_vm_agent = true
    winrm {
      protocol = "http"
    }
    # Auto-Login is required to configure WinRM
    additional_unattend_config {
      pass         = "oobeSystem"
      component    = "Microsoft-Windows-Shell-Setup"
      setting_name = "AutoLogon"
      content      = "<AutoLogon><Password><Value>${var.password}</Value></Password><Enabled>true</Enabled><LogonCount>1</LogonCount><Username>${var.username}</Username></AutoLogon>"
    }

    # Unattend config is to enable basic auth in WinRM, required for the provisioner stage.
    additional_unattend_config {
      pass         = "oobeSystem"
      component    = "Microsoft-Windows-Shell-Setup"
      setting_name = "FirstLogonCommands"
      content      = file("./files/FirstLogonCommands.xml")
    }
  }

  tags = {
    X-Dept        = var.tag_dept
    X-Customer    = var.tag_customer
    X-Project     = var.tag_project
    X-Application = var.tag_application
    X-Contact     = var.tag_contact
    X-TTL         = var.tag_ttl
  }

  connection {
    host     = azurerm_public_ip.win_pubip.fqdn
    type     = "winrm"
    port     = 5985
    #https    = true
    https    = false
    timeout  = "10m"
    user     = var.username
    password = var.password
    insecure = true
  }

  provisioner "file" {
    source      = "files/config.ps1"
    destination = "c:/terraform/config.ps1"
  }

  provisioner "remote-exec" {
    inline = [
      "Powershell.exe Get-Process | Powershell.exe Out-File -FilePath c:\\terraform\\remoteexec_script_ran_if_file_exists.txt",
      "cd C:\\Windows",
      "dir",
      #"PowerShell.exe -ExecutionPolicy Bypass c:\\terraform\\config.ps1",
      #"PowerShell.exe Enable-PSRemoting -Force",
    ]
  }


}

resource "azurerm_virtual_machine_extension" "winrm" {
  name                 = "winrm_extension_custom"
  virtual_machine_id   = azurerm_virtual_machine.win.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = <<SETTINGS
    {
        "commandToExecute": "hostname; Powershell.exe Get-Process | Powershell.exe Out-File -FilePath c:\\terraform\\win_rm_extension_script_ran_if_file_exists.txt"
    }
    SETTINGS
}


output "public_fqdn" {
  value = azurerm_public_ip.win_pubip.fqdn
}

output "public_ip" {
  value = azurerm_public_ip.win_pubip.ip_address
}