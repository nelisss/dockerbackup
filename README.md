# Dockerbackup

This is a shell script for periodic backups of docker bind mounts and databases.
It allows you to create systemd services with accompanying timers that create tarballs of a directory of your choice on a schedule of your choosing.
The service can integrate with docker, shutting down a container or performing `docker compose down` before archiving, to prevent corruption of databases, for example.
Optionally, you can provide user-defined shell commands which will be executed alongside the creation of the tarball.
This can be useful for creating a database dump alongside the directory archive.

## Requirements

- docker CLI
- systemd

## Installation

1. Clone this repository or download dockerbackup.sh

    ```bash
    git clone https://github.com/nelisss/dockerbackup.git
    ```

2. (Optional) Copy or symlink the script to a location in path (for symlink both paths should be absolute)

    ```bash
    cp /path/to/dockerbackup.sh /usr/local/bin/dockerbackup.sh
    ```

    OR

    ```bash
    ln -s /path/to/dockerbackup.sh /usr/local/bin/dockerbackup.sh 
    ```

## Usage

You can run `dockerbackup.sh -h` at any time for usage.

The general syntax is `dockerbackup.sh [flags] [subcommand] [arguments]`.

### Subcommands

| Command | Description |
| --- | --- |
| list | List previously created backup services |
| add [directory] | Add a new backup service for *directory* |
| remove [name] | Remove a previously created backup service |

### Common flags

| Flag | Description |
| --- | --- |
| -h | Print help and exit |
| -v | Print verbose output |
| -i | Run script interactively, confirm changes |
| -x | Ignore existence of lock file |
| -z | Print script info and exit |

### Add command

General syntax: `dockerbackup.sh [flags] add [directory]`.
To configure the service to add, you have two options: supply flags or use a config file.

***Flags***
| Flag | Name | Description | Default |
| --- | --- | --- | --- |
| -o | output_dir | Directory to output backups to | ~/dockerbackup/\<service_name> |
| -n | service_name | Name to assign to systemd services | Name of directory that is being backed up |
| -x | exclude_patterns | Exclude pattern or colon-separated list of exclude patterns to exclude from tarballs (via tar --exclude, see `man tar` for syntax) | None |
| -p | compose_file | Docker compose file associated with backup service, will execute `docker compose down` and `docker compose up -d` before and after creating tar | None |
| -c | containers | Docker container or colon-separated list of containers, will stop and start containers before and after creating tar | None |
| -s | schedule | Schedule to run the backup service ([examples](https://wiki.archlinux.org/title/Systemd/Timers#Examples)) | First unused schedule in 5 minute increments, starting at "\*-\*-\* 02:00:00" |
| -u | user_commands | Shell command or colon-separated list of commands to be executed before performing the directory backup (with containers still running if -p or -c is given) | None |
| -e | env_file | Environment file to be loaded in systemd service via EnvironmentFile, can be used in user_commands (note: variables aren't available in subshell of commands) | None |
| -r | prune_lag | Number of days after which backups will be pruned, set to 0 to never prune | 14 |
| -f | config_file | Config file to use for creation of service, flags take precedence | None |

***Config file***

A config file can be supplied instead of using flags. The config file is simply an environment file that will be sourced in the script. Therefore, the syntax is \<option name>=value, with one option per line.

The option names can be found in the table above, under Name.

*Example*

pihole_dockerbackup.conf:

```bash
backup_dir=~/docker/appdata/pihole
output_dir=~/docker/backups/pihole
service_name=pihole
exclude_patterns=listsCache
compose_file=~/docker/compose/pihole/docker-compose.yaml
```

Then run `dockerbackup.sh -f /path/to/pihole_dockerbackup.conf add`.

## Examples

*List enabled dockerbackup services*

```bash
dockerbackup.sh list
```

*Add a backup service for a docker data directory with defaults*

```bash
dockerbackup.sh add ~/docker/pihole/data
```

*Add a backup service for a docker data directory using a config file*

```bash
dockerbackup.sh -f ~/docker/pihole/pihole_dockerbackup.conf add
```

*Add a backup service for a docker data directory using flags: output directory (-o), two containers (-c), a prune lag of 7 days (-r) and service name pihole (-n)*

```bash
dockerbackup.sh -o ~/backups -c pihole:unbound -r 7 -n pihole add ~/docker/pihole/data
```

*Remove a backup service*

```bash
dockerbackup.sh remove pihole
```

## Notes

- user_commands (-u) should be enclosed in double quotes ("), requires escaping of all double quotes (") and dollar-sign ($) with a backslash (\\). Backslashes have to be escaped twice, so for one \ in the final command, user_commands should contain \\\\\\\\. :(

    Example: 

    user_commands="docker exec postgres bash -c \\"usr/bin/pg_dump -U username_example database_example > backups/dump_\\$date.sql\\":find /path/to/backups/* -name \\"dump_.*\\" -prune -o -mtime +14 -exec rm {} \\\\\\\\;"

- The systemd services are installed in the home directory (~/.config/systemd/user/) if the script is run as a non-root user, and in /etc/systemd/system/ if the script is run as root. As is to be expected, the script inherits the permissions of the user running the script, so running as non-root requires at least read permissions of the directory that is being backed up.

- Of course, this script does not ensure the safety of your backups (are they even backups? unsure about terminology); [3-2-1](https://www.backblaze.com/blog/the-3-2-1-backup-strategy/) is your responsibility. For example, I use this script to make backups of the config bind mounts of my docker services and simultaneously perform database dumps. I output these backups to a central folder, which I back up to another device on my local network and to a cloud provider every day.

- This script is not well suited to directories with large contents, as it creates a new tarball every time the service is triggered. It is mainly meant for things like config folders. For data directories, I keep incremental backups.
