terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Le fichier d'état (state) contient TOUTE l'infrastructure, parfois des secrets en clair.
  # Il ne doit jamais être versionné dans Git : on le stocke dans un compte de stockage Azure
  # chiffré, à accès restreint, avec verrouillage (lease) et versionnement des blobs.
  # Décommentez ce bloc une fois le compte de stockage créé (voir la doc, étape TP 2).
  #
  # backend "azurerm" {
  #   resource_group_name  = "rg-tfstate"
  #   storage_account_name = "sttfstateboutique"
  #   container_name       = "tfstate"
  #   key                  = "tp2.terraform.tfstate"
  #   use_azuread_auth     = true
  # }
}

provider "azurerm" {
  features {}
}
