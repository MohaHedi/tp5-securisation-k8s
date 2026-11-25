variable "prefixe" {
  description = "Préfixe des noms de ressources"
  type        = string
  default     = "boutique"
}

variable "region" {
  description = "Région Azure"
  type        = string
  default     = "francecentral"
}

variable "taille_vm" {
  description = "Taille des machines virtuelles"
  type        = string
  default     = "Standard_B2s"
}

variable "admin_utilisateur" {
  description = "Nom de l'administrateur des VM"
  type        = string
  default     = "azureuser"
}

variable "cle_ssh_publique" {
  description = "Clé SSH PUBLIQUE de l'administrateur (jamais de mot de passe)"
  type        = string
}

variable "ip_admin_autorisee" {
  description = "Adresse IP (CIDR) autorisée à se connecter en SSH, par exemple 203.0.113.10/32"
  type        = string

  validation {
    condition     = !contains(["*", "0.0.0.0/0", "Internet", "any"], var.ip_admin_autorisee)
    error_message = "Le SSH ne doit pas être ouvert à tout Internet : indiquez votre IP en /32."
  }
}

variable "instances_min" {
  description = "Nombre minimum d'instances dans le groupe élastique"
  type        = number
  default     = 1
}

variable "instances_max" {
  description = "Nombre maximum d'instances dans le groupe élastique"
  type        = number
  default     = 4
}
