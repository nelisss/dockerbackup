#!/bin/sh
#================================================================
# HEADER
#================================================================
#% SYNOPSIS
#+    ${script_name} [-hvixz] [options] [command]
#%
#% DESCRIPTION
#%    Shell script to create systemd services to regularly 
#%    back up docker mount directories.
#%
#% COMMANDS
#%
#%    list                          List previously created backup
#%                                  services
#%    add [directory]               Add a new backup service for 
#%                                  directory
#%    remove [name]                 Remove backup service
#%
#% GLOBAL OPTIONS
#%
#%    -h                            Print this help
#%    -v                            Print verbose output
#%    -i                            Run script interactively
#%    -x                            Ignore existence of lock file
#%    -z                            Print script info
#%
#% ADD OPTIONS
#%
#%    -o [directory]                output_dir
#%                                  Directory to output backups to
#%                                  Defaults to ~/dockerbackup/<service
#%                                  name>
#%    -n [name]                     service_name
#%                                  Name to assign to systemd services
#%                                  Defaults to name of directory
#%    -x [pattern]                  exclude_patterns
#%                                  Exclude pattern or colon-separated 
#%                                  list of exclude patterns to exclude 
#%                                  from the backup, via tar --exclude
#%                                  For syntax, see the 'man tar' 
#%    -p [file]                     compose_file
#%                                  Docker compose file associated with
#%                                  backup service
#%                                  Will compose down and up before and
#%                                  after running backup, respectively
#%    -c [container1:container2]    containers
#%                                  Docker container or colon-separated
#%                                  list of docker containers to back
#%                                  up
#%                                  Will stop and start before and after
#%                                  running backup, respectively
#%                                  Will be ignored if -a is set
#%    -s [cron schedule]            schedule
#%                                  Schedule to run the backup service
#%                                  in cron format
#%                                  Defaults to "*-*-* 02:00:00" + 5
#%                                  minutes for every running service
#%    -u [command1:command2]        user_commands
#%                                  Shell command or colon-separated
#%                                  list of commands to be executed
#%                                  before performing the directory
#%                                  backup
#%                                  Command(s) will be added as
#%                                  ExecStartPre definition(s) in the 
#%                                  systemd service file
#%    -e [file]                     env_file
#%                                  Environment file to be loaded in
#%                                  systemd service via EnvironmentFile
#%                                  Included variables can be used in
#%                                  user_commands
#%    -r [days]                     prune_lag
#%                                  Number of days after which backups
#%                                  will be pruned
#%                                  Set to 0 to never prune backups
#%                                  Defaults to 14 days
#%    -f [file]                     config_file
#%                                  Config file to use for creation of
#%                                  service
#%                                  Flags take precedence over the
#%                                  config file
#%                                  See CONFIG FILE below for syntax
#%
#% CONFIG FILE
#%
#%    A config file can be supplied instead of using flags. All options
#%    should be in the format <option_name>="value", with one option per
#%    line.
#%
#%    Options:
#%      backup_dir              second argument
#%      output_dir              flag -o
#%      service_name            flag -n
#%      exclude_patterns        flag -x
#%      compose_file            flag -p
#%      containers              flag -c
#%      schedule                flag -s
#%      user_commands           flag -u
#%      env_file                flag -e
#%      prune_lag               flag -r
#%    
#% EXAMPLES
#%
#%    ${script_name} list           List enabled backup services
#%
#%    ${script_name} add ~/docker/pihole/data           
#%                                  Add a backup service for a docker
#%                                  data directory with defaults
#%
#%    ${script_name} -f ~/docker/pihole/dockerbackup_pihole.conf \
#%    add ~/docker/pihole/data           
#%                                  Add a backup service for a docker
#%                                  data directory using a config file
#%
#%    ${script_name} -o ~/backups -c pihole:cloudflared \
#%    -r 7 add ~/docker/pihole/data
#%                                  Add a backup service for a docker
#%                                  data directory, defining output 
#%                                  directory, docker containers to
#%                                  stop and start and a custom
#%                                  command to run before backing up
#%
#%    ${script_name} remove pihole
#%                                  Remove a backup service
#%
#================================================================
#- IMPLEMENTATION
#-    version         ${script_name} ${script_version}
#-    author          nelisss
#-    copyright       Copyright (c) nelisss 2026
#-    license         GNU General Public License v3
#-
#================================================================
#  DEBUG OPTION
#    set -n  # Uncomment to check your syntax, without execution.
#    set -x  # Uncomment to debug this shell script
#
#================================================================
# END_OF_HEADER
#================================================================

set -e

## --- Header processing --------------------------------------------
script_headsize=$(head -200 ${0} |grep -n "^# END_OF_HEADER" | cut -f1 -d:)
script_name="$(basename ${0})"
program_name="${script_name%.*}"
script_version="0.0.1"
subject=${program_name}_qRPy2nF2
start_env=$( ( set -o posix ; set | sort ) )

usage() { printf "Usage: "; head -${script_headsize:-99} ${0} | grep -e "^#+" | sed -e "s/^#+[ ]*//g" -e "s/\${script_name}/${script_name}/g" ; }
usagefull() { head -${script_headsize:-99} ${0} | grep -e "^#[%+-]" | sed -e "s/^#[%+-]//g" -e "s/\${script_name}/${script_name}/g" | sed -e "s/^#+[ ]*//g" -e "s/\${script_version}/${script_version}/g" ; }
scriptinfo() { head -${script_headsize:-99} ${0} | grep -e "^#-" | sed -e "s/^#-//g" -e "s/\${script_name}/${script_name}/g" | sed -e "s/^#+[ ]*//g" -e "s/\${script_version}/${script_version}/g" ; }

# --- Other functions -----------------------------------------------
echoverbose() { if [ "$1" = true ]; then echo "$2"; fi ; }

## --- Options processing -------------------------------------------
if [ $# = 0 ] ; then
    usage
    exit 1;
fi

while getopts ":hvixzo:n:x:p:c:s:u:e:r:f:" optname
  do
    case "$optname" in
      "h")
        usagefull
        exit 0;
        ;;
      "v")
        verbose="true"
        ;;
      "i")
        interactive="true"
        ;;
      "x")
        ignore_lock=true
        ;;
      "z")
        scriptinfo
        exit 0;
        ;;
      "o")
        output_dir=$OPTARG
        ;;
      "n")
        service_name=$OPTARG
        ;;
      "x")
        exclude_patterns=$OPTARG
        ;;
      "p")
        compose_file=$OPTARG
        ;;
      "c")
        containers=$OPTARG
        ;;
      "s")
        schedule=$OPTARG
        ;;
      "u")
        user_commands=$OPTARG
        ;;
      "e")
        env_file=$OPTARG
        ;;
      "r")
        prune_lag=$OPTARG
        ;;
      "f")
        config_file=$OPTARG
        ;;
      "?")
        echo "Unknown option $OPTARG"
        exit 2;
        ;;
      ":")
        echo "No argument value for option $OPTARG"
        exit 2;
        ;;
      *)
        echo "Unknown error while processing options"
        exit 0;
        ;;
    esac
  done

shift $(($OPTIND - 1))

# --- Locks -------------------------------------------------------
if [ "$ignore_lock" != true ]; then
    lock_file=/tmp/$subject.lock
    if [ -f "$lock_file" ]; then
       echo "Error: script is already running." >&2
       exit 1
    fi

    trap "rm -f $lock_file" EXIT
    touch $lock_file
else
    lock_file=/tmp/$subject.lock
    if [ -f "$lock_file" ]; then
       echo "Info: -x is set, ignoring existing lock file."
    fi
fi
echoverbose "$verbose" "Info: running $script_name version $script_version."

## --- Set variables ----------------------------------------------
systemd_file_extension="_${program_name}"

## --- Input validation -------------------------------------------
# Check root for systemctl commands
root=$( if [ "$( id -u )" = 0 ]; then echo "true"; else echo "false"; fi )
if [ "$root" = true ]; then
    systemctl_flag=""
    systemd_dir="/etc/systemd/system"
    echoverbose "$verbose" "Info: running as root, handling systemwide services."
else
    systemctl_flag="--user "
    systemd_dir="$HOME/.config/systemd/user"
    echoverbose "$verbose" "Info: running as non-root user, adding --user flag to systemctl commands."
fi

### config_file ###
if [ "$config_file" != "" ]; then
    if [ ! -f "$config_file" ]; then
        echo "Error: provided config file does not exist." >&2
        exit 2
    else
        config_file=$( echo "$( pwd )/${config_file}" )
        flag_env="`grep -vFe "$start_env" <<<"$( set -o posix ; set | sort )" | grep -v ^current_env=`"; unset current_env;
        # Source config file
        source "$config_file"
        # Reload flag inputs
        eval "$flag_env"
        echoverbose "$verbose" "Info: using config from $config_file for variables not defined using flags."
    fi
fi

# Check if command is given
if [ -n "$1" ]; then
    command=$1
else
    echo "Error: missing command (add/remove/list). Run '$script_name -h' for more info." >&2
    exit 2
fi

# Check if command is valid
if [ "$command" != "list" ] && [ "$command" != "add" ] && [ "$command" != "remove" ]; then
    echo "Error: command should be one of add/remove/list. Run '$script_name -h' for more info." >&2
    exit 2
fi

### ADD ###
if [ "$command" = "add" ]; then
    # Check if backup directory is given
    if [ -n "$2" ]; then
        backup_dir=$2
    else
        if [ "$config_file" = "" ]; then
            echo "Error: missing backup_dir. Run '$script_name -h' for more info." >&2
            exit 2
        else
            if [ "$backup_dir" == "" ]; then
                echo "Error: missing backup_dir in arguments and config file. Run '$script_name -h' for more info." >&2
                exit 2
            fi
        fi
    fi
    # Check if backup directory exists
    if [ ! -d "$backup_dir" ]; then
        echo "Error: specified backup_dir does not exist. Run '$script_name -h' for more info." >&2
        exit 2
    fi
    backup_dir=$( cd "$backup_dir"; pwd )
    # Check if additional arguments are given
    if [ -n "$3" ]; then
        echo "Warning: ${script_name} add command expects two arguments. Extra arguments will be ignored." >&2
    fi

### REMOVE ###
elif [ "$command" = "remove" ]; then
    # Check if backup service is given
    if [ -n "$2" ]; then
        backup_service=$2
    else
        echo "Error: missing backup service to remove. Run '$script_name -h' for more info." >&2
        exit 2
    fi
    # Check if backup service exists
    if ( ! systemctl ${systemctl_flag}list-units --type=timer | grep "$backup_service""$systemd_file_extension".timer > /dev/null ); then
        echo "Error: provided backup service does not exist. Run '$script_name list' for a list of currently enabled backup services." >&2
        exit 2
    fi
    # Check if additional arguments are given
    if [ -n "$3" ]; then
        echo "Warning: '$script_name remove' command expects two arguments. Extra arguments will be ignored." >&2
    fi
    # Check if additional flags are given
    if [ "$output_dir" != "" ] || [ "$service_name" != "" ] || [ "$exclude_patterns" != "" ] || [ "$compose_file" != "" ] || [ "$containers" != "" ] || [ "$schedule" != "" ] || [ "$user_commands" != "" ] || [ "$env_file" != "" ] || [ "$prune_lag" != "" ] || [ "$config_file" != "" ]; then
        echo "Warning: '$script_name remove' command only accepts -v and -x flags. Other flags will be ignored." >&2
    fi

### LIST ###
else
    # Check if additional arguments are given
    if [ -n "$2" ]; then
        echo "Warning: '$script_name list' command expects a single argument. Extra arguments will be ignored." >&2
    fi
    # Check if additional flags are given
    if [ "$output_dir" != "" ] || [ "$service_name" != "" ] || [ "$exclude_patterns" != "" ] || [ "$compose_file" != "" ] || [ "$containers" != "" ] || [ "$schedule" != "" ] || [ "$user_commands" != "" ] || [ "$env_file" != "" ] || [ "$prune_lag" != "" ] || [ "$config_file" != "" ]; then
        echo "Warning: '$script_name list' command only accepts -v and -x flags. Other flags will be ignored." >&2
    fi
fi

# --- FLAG PROCESSING ---------------------------------------------
if [ "$command" = "add" ]; then

    ### service_name ###
    if [ "$service_name" = "" ]; then
        service_name=$(basename "$backup_dir")
        service_name=$( echo "$service_name" | sed 's/[^A-Za-z0-9_-]//g' )
        echoverbose "$verbose" "Info: no service_name provided, using $service_name."
    else
        if ( echo "$service_name" | grep -P ".*[^A-Za-z0-9_-].*" > /dev/null ); then
            echo "Error: invalid service name \"$service_name\". Service name should only contain a-z, A-Z, 0-9, _ and -." >&2
            exit 2
        fi
    fi
    n_services_active=$( systemctl ${systemctl_flag}list-units "*${systemd_file_extension}.timer" | grep -oP "[0-9]*(?= loaded units listed)" )
    if [ ! "$n_services_active" = 0 ]; then
        services_active=$( systemctl ${systemctl_flag}list-units "*${systemd_file_extension}.timer" | grep -oP ".*(?=${systemd_file_extension}\.timer)" )
        services_active=$( echo "$services_active" | sed -e "s/${systemd_file_extension}//" )
        if ( echo "${services_active}" | grep "${service_name}\$" ); then
            echo "Error: backup service with service_name ${service_name} already exists." >&2
            exit 2
        fi
    fi

    ### exclude_patterns ###
    if [ "$exclude_patterns" != "" ]; then
        exclude_patterns_sep=$( echo "$exclude_patterns" | sed "s/\\\:/_tmpescape_/" )
        exclude_patterns_sep=$( echo "$exclude_patterns_sep" | tr ":" "\n" )
        exclude_patterns_sep=$( echo "$exclude_patterns_sep" | sed "s/_tmpescape_/:/" )
    fi

    ### output_dir ###
    if [ "$output_dir" != "" ]; then
        if [ ! -d "$output_dir" ]; then
            mkdir -p "$output_dir"
            echoverbose "$verbose" "Info: provided output_dir does not exist, created."
        fi
    else
        output_dir="$HOME"/${program_name}/"$service_name"
        echoverbose "$verbose" "Info: no output_dir provided, using $output_dir."
    fi

    ### compose_file ###
    if [ "$compose_file" != "" ]; then
        if [ -d "$compose_file" ]; then
            echo "Error: provided compose_file is a directory." >&2
            exit 2
        fi
        if [ ! -f "$compose_file" ]; then
            echo "Error: provided compose_file does not exist." >&2
            exit 2
        fi
        if ( ! echo "$compose_file" | grep -P ".*\.ya?ml$" > /dev/null ); then
            echo "Error: provided compose_file is not a y(a)ml file." >&2
            exit 2
        fi
        if ( ! docker compose -f "$compose_file" config > /dev/null ); then
            echo "Error: provided compose_file is invalid." >&2
            exit 2
        fi
        compose_file=$( cd $( echo "$compose_file" | grep -oP "(.*)(?=/.*\.ya?ml$)" ); pwd )/$( basename "$compose_file" )
    fi

    ### containers ###
    if [ "$containers" != "" ]; then
        if [ "$compose_file" = "" ]; then
            containers_sep=$( echo "$containers" | sed "s/\\\:/_tmpescape_/" )
            containers_sep=$( echo "$containers_sep" | tr ":" "\n" )
            containers_sep=$( echo "$containers_sep" | sed "s/_tmpescape_/:/" )
            while IFS= read -r container; do
                if [ "$( docker ps -q -f name="$container" )" = "" ]; then
                    if [ "$( docker ps -a -q -f name="$container" )" = "" ]; then
                        echo "Error: provided container \"$container\" does not exist." >&2
                        container_fail=true
                    else
                        echo "Warning: provided container \"$container\" state is exited." >&2
                    fi
                fi
            done <<< "$containers_sep"
            if [ "$container_fail" = true ]; then
                exit 2
            fi
        else
            echo "Warning: containers (-c) and compose_file (-p) flags were both provided, ignoring containers." >&2
            containers_ignored=true
            containers=""
        fi
    fi

    ### schedule ###
    if [ "$schedule" != "" ]; then
        cat <<EOF > "/tmp/${subject}.timer"
[Unit]
Description=${program_name} timer for service

[Timer]
OnCalendar=$schedule
Unit=test.service

[Install]
WantedBy=timers.target
EOF
        if ( ! systemd-analyze verify "/tmp_${subject}.timer" > /dev/null 2>&1 ); then
            echo "Error: provided schedule \"$schedule\" is invalid. See e.g. https://crontab.guru/ for format." >&2
            exit 2
        fi
        rm "/tmp/${subject}.timer"
    else
        if ( systemctl ${systemctl_flag}list-units "*${systemd_file_extension}.timer" | grep -oP "[A-Za-z0-9_-]*${systemd_file_extension}\.timer" > /dev/null ); then
            existing_timers=$( systemctl ${systemctl_flag}list-units "*${systemd_file_extension}.timer" | grep -oP "[A-Za-z0-9_-]*${systemd_file_extension}\.timer" )
            iter=1
            while read timer; do
                schedule_iter="$( systemctl ${systemctl_flag}show "$timer" --property=TimersCalendar | grep -oP "(?<=OnCalendar=).*(?= ;)" )"
                if [ "$iter" = 1 ]; then
                    existing_schedules="${schedule_iter}"
                else
                    existing_schedules="${existing_schedules}""\n""${schedule_iter}"
                fi
                iter=$(( $iter + 1 ))
            done <<< "$existing_timers"
            init_schedule="*-*-* 02:00:00"
            schedule="*-*-* 02:00:00"
            first_iter=true
            while : ; do
                case "$existing_schedules" in
                    *"$schedule"*)
                        ;;
                    *)
                        break
                        ;;
                esac
                hour=$( echo "$schedule" | grep -oP '(?<=\*-\*-\* )[0-9]*' | sed 's/0//g' )
                minutes=$( echo "$schedule" | grep -oP '(?<=\*-\*-\* [0-9][0-9]:)[0-9][0-9]' )
                if [ "$minutes" != "55" ]; then
                    minutes=$(( $minutes + 5 ))
                else
                    minutes=0
                    if [ "$hour" = "23" ]; then
                        hour=0
                    else
                        hour=$(( $hour + 1 ))
                    fi
                fi
                minutes=$( printf "%02d" "$minutes" )
                schedule="*-*-* $( printf "%02d\n" $hour ):${minutes}:00"
                if [ "$first_iter" = false ]; then
                    if [ "$schedule" = "$init_schedule" ]; then
                        echo "Warning: no unique schedule found with 10-minute increments. Using $schedule." >&2
                        break
                    fi
                fi
                first_iter=false
            done
        else
            schedule="*-*-* 02:00:00"
        fi
        echoverbose "$verbose" "Info: no schedule provided, using $schedule."
    fi

    ### user_commands ###
    if [ "$user_commands" != "" ]; then
        user_commands_sep=$( echo "$user_commands" | sed "s/\\\:/_tmpescape_/" )
        user_commands_sep=$( echo "$user_commands_sep" | tr ":" "\n" )
        user_commands_sep=$( echo "$user_commands_sep" | sed "s/_tmpescape_/:/" )
    fi

    ### env_file ###
    if [ "$env_file" != "" ]; then
        if [ -d "$env_file" ]; then
            echo "Error: provided env_file is a directory." >&2
            exit 2
        fi
        if [ ! -f "$env_file" ]; then
            echo "Error: provided env_file does not exist." >&2
            exit 2
        fi
    fi

    ### prune_lag ###
    if [ "$prune_lag" != "" ]; then
        if ( echo "$prune_lag" | grep -oP "[^0-9]" > /dev/null ); then
            echo "Error: invalid value \"$prune_lag\" for prune_lag (-r), should be an integer number of days." >&2
            exit 2
        fi
    else
        prune_lag=14
    fi
    
else
    echoverbose "$verbose" "Info: $command - skipping validation and processing of input flags."
fi

# --- ADD ---------------------------------------------------------
if [ "$command" = "add" ]; then
    command_summary=\
"Info: backup service config
    backup_dir: ${backup_dir}
    output_dir: ${output_dir}
    service_name: ${service_name}
    exclude_patterns: ${exclude_patterns:-"not set"}
    compose_file: ${compose_file:-"not set"}
    containers: $( if [ "$containers_ignored" = true ]; then echo "ignored"; else echo ${containers:-"not set"} | sed 's/:/, /g'; fi )
    schedule: ${schedule}
    user_commands: $( if [ "$user_commands" != "" ]; then echo "\"${user_commands}\""; else echo "not set"; fi )"
    if [ "$interactive" = true ]; then
        echo "$command_summary"
        iter=1
        valid_input=false
        while [ "$valid_input" = false ]; do
            if [ $iter = 1 ]; then
                echo "Info: add backup service with this config? y/n"
            else
                echo "Error: invalid input, input y(es) or n(o)" >&2
            fi
            read confirm_add
            if [[ "${confirm_add,,}" = "y" ]] || [[ "${confirm_add,,}" = "yes" ]]; then
                valid_input=true
            elif [[ "${confirm_add,,}" = "n" ]] || [[ "${confirm_add,,}" = "no" ]]; then
                echo "Info: not adding backup service."
                exit 0
            fi
            iter=$(( $iter + 1 ))
        done
    else
        echoverbose "$verbose" "$command_summary"
    fi

    systemd_service=$(cat <<EOF
[Unit]
Description=${program_name} for ${service_name}

[Service]
Type=oneshot
EnvironmentFile=-/tmp/%p.env$( 
if [ "$env_file" != "" ]; then
    printf "\nEnvironmentFile=${env_file}"
fi
)
ExecStartPre=/bin/sh -c 'echo date=\$( date +"%%Y-%%m-%%d" ) > /tmp/%p.env'
ExecStartPre=/bin/echo "${program_name}: Starting backup service for ${service_name}."$( 
if [ "$user_commands" != "" ]; then 
    printf "\nExecStartPre=/bin/echo \"${program_name}: Executing user-defined commands...\""
    while IFS= read -r user_command; do
        printf "\nExecStartPre=/bin/sh -c '"; echo -n "${user_command}'"
    done <<< "$user_commands_sep" 
fi 
)$( 
if [ "$containers" != "" ]; then
    printf "\nExecStartPre=/bin/echo \"${program_name}: Stopping docker containers...\""
    while IFS= read -r container; do
        printf "\nExecStartPre=/bin/docker stop $container"
    done <<< "$containers_sep"
elif [ "$compose_file" != "" ]; then
    printf "\nExecStartPre=/bin/echo \"dockerbackup: Executing docker compose down...\""
    printf "\nExecStartPre=/bin/docker compose -f \"${compose_file}\" down"
fi 
)
ExecStart=/bin/sh -c "echo \\"${program_name}: Performing backup for ${service_name}...\\" && echo \\"${program_name}: Adding files in ${backup_dir} to new archive...\\" && tar -cz$( 
if [ "$exclude_patterns" != "" ]; then
    while IFS= read -r exclude_pattern; do
        echo -n " --exclude='${exclude_pattern}'";
    done <<< "$exclude_patterns_sep"
fi
) -f \\"${output_dir}/${service_name}_backup_\$date.tar.gz\\" -C \\"${backup_dir}\\" . > /dev/null && echo \\"${program_name}: Removing old backups...\\" && find ${output_dir}/* -name \\"${service_name}_backup_.*\\" -prune -o -mtime +${prune_lag} -exec ls {} \\\\; && find ${output_dir}/* -name \\"${service_name}_backup_.*\\" -prune -o -mtime +${prune_lag} -exec rm {} \\\\;"$( 
if [ "$containers" != "" ]; then
    printf "\nExecStartPost=/bin/echo \"${program_name}: Starting docker containers...\""
    while IFS= read -r container; do
        printf "\nExecStartPost=/bin/docker start $container"
    done <<< "$containers_sep"
elif [ "$compose_file" != "" ]; then
    printf "\nExecStartPost=/bin/echo \"${program_name}: Executing docker compose up -d...\""
    printf "\nExecStartPost=/bin/docker compose -f \"${compose_file}\" up -d"
fi 
)$( 
if [ "$containers" != "" ]; then
    printf "\nExecStopPost=/bin/echo \"${program_name}: Execution of backup failed. Starting docker containers...\""
    while IFS= read -r container; do
        printf "\nExecStopPost=/bin/docker start $container"
    done <<< "$containers_sep"
elif [ "$compose_file" != "" ]; then
    printf "\nExecStopPost=/bin/echo \"${program_name}: Execution of backup failed. Executing docker compose up -d...\""
    printf "\nExecStopPost=/bin/docker compose -f \"${compose_file}\" up -d"
fi 
)
EOF
    )
    # 7za a \\"${output_dir}/${service_name}_backup_\$date.zip\\" \\"${backup_dir}\\" > /dev/null 
    if [ "$interactive" = true ]; then
        echo "Info: adding systemd service unit to ${systemd_dir} with the following content:"
        echo "        ========================================================"
        echo "$( printf "%s" "$systemd_service" |sed -e $'s/^/\t/' )"
        echo "        ========================================================"
        iter=1
        valid_input=false
        while [ "$valid_input" = false ]; do
            if [ $iter = 1 ]; then
                echo "Info: install systemd service? y/n"
            else
                echo "Error: invalid input, input y(es) or n(o)" >&2
            fi
            read confirm_add
            if [[ "${confirm_add,,}" = "y" ]] || [[ "${confirm_add,,}" = "yes" ]]; then
                valid_input=true
            elif [[ "${confirm_add,,}" = "n" ]] || [[ "${confirm_add,,}" = "no" ]]; then
                echo "Info: not adding backup service."
                exit 0
            fi
            iter=$(( $iter + 1 ))
        done
    else
        echoverbose "$verbose" "Info: adding systemd service unit to ${systemd_dir} with the following content:"
        echoverbose "$verbose" "        ========================================================"
        echoverbose "$verbose" "$( printf "%s" "$systemd_service" |sed -e $'s/^/\t/' )"
        echoverbose "$verbose" "        ========================================================"
    fi
    echo "$systemd_service" > ${systemd_dir}/${service_name}${systemd_file_extension}.service

    systemd_timer=$(cat <<EOF
[Unit]
Description=${program_name} for ${service_name}

[Timer]
OnCalendar=${schedule}
Unit=${service_name}${systemd_file_extension}.timer

[Install]
WantedBy=timers.target
EOF
    )
    if [ "$interactive" = true ]; then
        echo "Info: adding systemd timer unit to ${systemd_dir} with the following content:"
        echo "        ========================================================"
        echo "$( printf "%s" "$systemd_timer" |sed -e $'s/^/\t/' )"
        echo "        ========================================================"
        iter=1
        valid_input=false
        while [ "$valid_input" = false ]; do
            if [ $iter = 1 ]; then
                echo "Info: install systemd timer? y/n"
            else
                echo "Error: invalid input, input y(es) or n(o)" >&2
            fi
            read confirm_add
            if [[ "${confirm_add,,}" = "y" ]] || [[ "${confirm_add,,}" = "yes" ]]; then
                valid_input=true
            elif [[ "${confirm_add,,}" = "n" ]] || [[ "${confirm_add,,}" = "no" ]]; then
                echo "Info: not adding backup service."
                exit 0
            fi
            iter=$(( $iter + 1 ))
        done
    else
        echoverbose "$verbose" "Info: adding systemd service timer to ${systemd_dir} with the following content:"
        echoverbose "$verbose" "        ========================================================"
        echoverbose "$verbose" "$( printf "%s" "$systemd_timer" |sed -e $'s/^/\t/' )"
        echoverbose "$verbose" "        ========================================================"
    fi
    echo "$systemd_timer" > ${systemd_dir}/${service_name}${systemd_file_extension}.timer

    if ( systemctl ${systemctl_flag}enable --now "${service_name}${systemd_file_extension}.timer" > /dev/null 2>&1 ); then
        echoverbose "$verbose" "Info: enabled and started ${service_name}${systemd_file_extension}.timer."
    else
        echo "Error: enabling systemd timer failed. Systemd output:"
        systemctl ${systemctl_flag}enable --now "${service_name}${systemd_file_extension}.timer"
        exit 1
    fi
    if ( systemctl ${systemctl_flag}start "${service_name}${systemd_file_extension}.service" > /dev/null 2>&1 ); then
        echoverbose "$verbose" "Info: successfully ran ${service_name}${systemd_file_extension}.service."
        echo "Info: successfully added ${program_name} service for ${service_name}."
    else
        echo "Error: systemd service exited with non-zero exit status. Run 'systemctl ${systemctl_flag} status ${service_name}${systemd_file_extension}.service' to find out more."
        echo "Info: added ${program_name} service for ${service_name}."
        exit 1
    fi
fi

# --- REMOVE ------------------------------------------------------
if [ "$command" = "remove" ]; then
    if [ "$interactive" = true ]; then
        iter=1
        valid_input=false
        while [ "$valid_input" = false ]; do
            if [ $iter = 1 ]; then
                echo "Info: remove ${program_name} service for ${backup_service}? y/n"
            else
                echo "Error: invalid input, input y(es) or n(o)" >&2
            fi
            read confirm_add
            if [[ "${confirm_add,,}" = "y" ]] || [[ "${confirm_add,,}" = "yes" ]]; then
                valid_input=true
            elif [[ "${confirm_add,,}" = "n" ]] || [[ "${confirm_add,,}" = "no" ]]; then
                echo "Info: not removing backup service."
                exit 0
            fi
            iter=$(( $iter + 1 ))
        done
    fi
    echoverbose "$verbose" "Info: removing $program_name service for $backup_service."
    systemctl ${systemctl_flag}disable --now "${backup_service}${systemd_file_extension}.timer" > /dev/null 2>&1
    echoverbose "$verbose" "Info: disabled and stopped ${backup_service}${systemd_file_extension}.timer."
    rm ${systemd_dir}/${backup_service}${systemd_file_extension}.*
    echoverbose "$verbose" "Info: removed systemd service and timer unit from ${systemd_dir}."
    echo "Info: successfully removed ${program_name} service for ${backup_service}."
fi

# --- LIST --------------------------------------------------------
if [ "$command" = "list" ]; then
    n_services_active=$( systemctl ${systemctl_flag}list-units "*${systemd_file_extension}.timer" | grep -oP "[0-9]*(?= loaded units listed)" )
    if [ "$n_services_active" = 0 ]; then
        echo "No active backup services."
    else
        services_active=$( systemctl ${systemctl_flag}list-units "*${systemd_file_extension}.timer" | grep -oP ".*(?=${systemd_file_extension}\.timer)" )
        services_active=$( echo "$services_active" | sed -e "s/${systemd_file_extension}//" )
        echo "Currently activated ${program_name} services:"
        echo "$services_active" 
    fi
fi
# -----------------------------------------------------------------
exit 0
