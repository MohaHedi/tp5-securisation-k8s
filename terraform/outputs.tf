output "ip_publique_site" {
  description = "Adresse du site (load balancer devant le groupe élastique)"
  value       = azurerm_public_ip.lb.ip_address
}

output "ip_publique_admin" {
  description = "Adresse SSH de la VM d'administration"
  value       = azurerm_public_ip.admin.ip_address
}
