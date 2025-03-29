# `external_mover.sh`

## Description:

`external_mover.sh` is a script designed to free up space on Enigma2 devices by moving certain system directories (like Enigma2 and Python folders) to an external drive.

## Usage:

### Without Auto-Confirmation (Interactive):

```bash
sh -c "$(wget -qO- https://raw.githubusercontent.com/Kamal-OS/enigma2-scripts/refs/heads/main/external_mover.sh)"
```

### With Auto-Confirmation (No Prompts):

```bash
sh -c "$(wget -qO- https://raw.githubusercontent.com/Kamal-OS/enigma2-scripts/refs/heads/main/external_mover.sh)" -- -y
```
