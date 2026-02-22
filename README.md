# 🚓 LRP - LSPD Helper  
### by _spartacus

Script MoonLoader avancé pour SA-MP permettant d’afficher et gérer dynamiquement la liste des membres LSPD avec interface ImGui moderne, notifications sonores et système d’auto-refresh intelligent.

---

## 📋 Pré-requis

Les éléments suivants sont **obligatoires** :

- [CLEO v4.4.4](https://github.com/cleolibrary/CLEO4/releases/latest) ou version supérieure  
  ⚠️ **CLEO 5 non supporté**
- [SAMPFUNCS (v5.7.1 recommandé)](https://www.blast.hk/attachments/255877/)
- [MoonLoader (v0.26.5-beta)](https://samp-mods.com/index.php?do=files&op=showfile&lid=12965)

---

## 📦 Dépendances Lua requises

- [mimgui v1.7.1](https://github.com/THE-FYP/mimgui/releases/tag/v1.7.1)
- [samp.lua v2.3.0](https://github.com/THE-FYP/SAMP.Lua)

Ces fichiers doivent être placés dans :

moonloader/lib/

## 🛠 Installation

1. Installez tous les pré-requis.
2. Placez le dossier `LSPD_Helper` dans :

moonloader/


3. Vérifiez que l’arborescence correspond à celle-ci :

moonloader\lspdhelper.lua

moonloader\LSPD_Helper\config\lspdhelper.ini

moonloader\LSPD_Helper\sounds\panel_add.wav

4. Lancez le jeu.

Au lancement, le panel s'affichera dès que vous ferez CTRL + J

---

## 🎮 Commandes

| Commande | Description |
|----------|------------|
| `/lspdhelper` | Affiche l’aide des commandes |
| `/lspdreload` | Recharge la configuration (.ini) |
| `/lspdrefresh` | Force une actualisation via `/jmembres` |
| `/lspdvolume [0-100]` | Modifie le volume des notifications |
| `CTRL + J` | Ouvrir le panel (fenêtre amovible) | 
| `CTRL + K` | Rendre la souris disponible pour cliquer sur le panel |
| `N` | Activation des gyrophares et désactivation (pour FPS Unlock principalement` |

Hotkeys configurables dans le `.ini`.

---

## 📜 Licence

Projet développé pour usage SA-MP/OMP.
Modification et redistribution autorisées avec crédit.

---
