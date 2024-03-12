#!/usr/bin/env bash
set -Eeo pipefail
# TODO swap to -Eeuo pipefail above (after handling all potentially-unset variables)

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		printf >&2 'error: both %s and %s are set (but are exclusive)\n' "$var" "$fileVar"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

# check to see if this file is being run or sourced from another script
_is_sourced() {
	# https://unix.stackexchange.com/a/215279
	[ "${#FUNCNAME[@]}" -ge 2 ] \
		&& [ "${FUNCNAME[0]}" = '_is_sourced' ] \
		&& [ "${FUNCNAME[1]}" = 'source' ]
}

# used to create initial postgres directories and if run as root, ensure ownership to the "postgres" user
docker_create_db_directories() {
	local user; user="$(id -u)"

	mkdir -p "$PGDATA"
	# ignore failure since there are cases where we can't chmod (and PostgreSQL might fail later anyhow - it's picky about permissions of this directory)
	chmod 00700 "$PGDATA" || :

	# ignore failure since it will be fine when using the image provided directory; see also https://github.com/docker-library/postgres/pull/289
	mkdir -p /var/run/halo || :
	chmod 03775 /var/run/halo || :

	# Create the transaction log directory before initdb is run so the directory is owned by the correct user
	if [ -n "${POSTGRES_INITDB_WALDIR:-}" ]; then
		mkdir -p "$POSTGRES_INITDB_WALDIR"
		if [ "$user" = '0' ]; then
			find "$POSTGRES_INITDB_WALDIR" \! -user halo -exec chown halo '{}' +
		fi
		chmod 700 "$POSTGRES_INITDB_WALDIR"
	fi

	# allow the container to be started with `--user`
	if [ "$user" = '0' ]; then
		find "$PGDATA" \! -user halo -exec chown halo '{}' +
		find /var/run/halo \! -user halo -exec chown halo '{}' +
	fi
}

# initialize empty PGDATA directory with new database via 'initdb'
# arguments to `initdb` can be passed via POSTGRES_INITDB_ARGS or as arguments to this function
# `initdb` automatically creates the "postgres", "template0", and "template1" dbnames
# this is also where the database user is created, specified by `POSTGRES_USER` env
docker_init_database_dir() {
	# "initdb" is particular about the current user existing in "/etc/passwd", so we use "nss_wrapper" to fake that if necessary
	# see https://github.com/docker-library/postgres/pull/253, https://github.com/docker-library/postgres/issues/359, https://cwrap.org/nss_wrapper.html
	local uid; uid="$(id -u)"
	if ! getent passwd "$uid" &> /dev/null; then
		# see if we can find a suitable "libnss_wrapper.so" (https://salsa.debian.org/sssd-team/nss-wrapper/-/commit/b9925a653a54e24d09d9b498a2d913729f7abb15)
		local wrapper
		for wrapper in {/usr,}/lib{/*,}/libnss_wrapper.so; do
			if [ -s "$wrapper" ]; then
				NSS_WRAPPER_PASSWD="$(mktemp)"
				NSS_WRAPPER_GROUP="$(mktemp)"
				export LD_PRELOAD="$wrapper" NSS_WRAPPER_PASSWD NSS_WRAPPER_GROUP
				local gid; gid="$(id -g)"
				printf 'halo:x:%s:%s:Halo:%s:/bin/false\n' "$uid" "$gid" "$PGDATA" > "$NSS_WRAPPER_PASSWD"
				printf 'halo:x:%s:\n' "$gid" > "$NSS_WRAPPER_GROUP"
				break
			fi
		done
	fi

	if [ -n "${POSTGRES_INITDB_WALDIR:-}" ]; then
		set -- --waldir "$POSTGRES_INITDB_WALDIR" "$@"
	fi

	# --pwfile refuses to handle a properly-empty file (hence the "\n"): https://github.com/docker-library/postgres/issues/1025
	eval 'initdb --username="$HALO_USER" --pwfile=<(printf "%s\n" "$HALO_PASSWORD") '"$POSTGRES_INITDB_ARGS"' "$@"'

	# unset/cleanup "nss_wrapper" bits
	if [[ "${LD_PRELOAD:-}" == */libnss_wrapper.so ]]; then
		rm -f "$NSS_WRAPPER_PASSWD" "$NSS_WRAPPER_GROUP"
		unset LD_PRELOAD NSS_WRAPPER_PASSWD NSS_WRAPPER_GROUP
	fi

	#创建archivedir文件夹
	mkdir -p $PGDATA/archivedir


}

# print large warning if POSTGRES_PASSWORD is long
# error if both POSTGRES_PASSWORD is empty and POSTGRES_HOST_AUTH_METHOD is not 'trust'
# print large warning if POSTGRES_HOST_AUTH_METHOD is set to 'trust'
# assumes database is not set up, ie: [ -z "$DATABASE_ALREADY_EXISTS" ]
docker_verify_minimum_env() {
	case "${PG_MAJOR:-}" in
		12 | 13) # https://github.com/postgres/postgres/commit/67a472d71c98c3d2fa322a1b4013080b20720b98
			# check password first so we can output the warning before postgres
			# messes it up
			if [ "${#HALO_PASSWORD}" -ge 100 ]; then
				cat >&2 <<-'EOWARN'
					WARNING: The supplied PASSWORD is 100+ characters.
					  This will not work if used via PGPASSWORD with "psql".
				EOWARN
			fi
			;;
	esac
	if [ -z "$HALO_PASSWORD" ] && [ 'trust' != "$POSTGRES_HOST_AUTH_METHOD" ]; then
		# The - option suppresses leading tabs but *not* spaces. :)
		cat >&2 <<-'EOE'
			Error: Database is uninitialized and superuser password is not specified.
			       You must specify HALO_PASSWORD to a non-empty value for the
			       superuser. For example, "-e HALO_PASSWORD=password" on "docker run".

			       You may also use "POSTGRES_HOST_AUTH_METHOD=trust" to allow all
			       connections without a password. This is *not* recommended.

			       See PostgreSQL documentation about "trust":
			       https://www.postgresql.org/docs/current/auth-trust.html
		EOE
		exit 1
	fi
	if [ 'trust' = "$POSTGRES_HOST_AUTH_METHOD" ]; then
		cat >&2 <<-'EOWARN'
			********************************************************************************
			WARNING: POSTGRES_HOST_AUTH_METHOD has been set to "trust". This will allow
			         anyone with access to the Postgres port to access your database without
			         a password, even if HALO_PASSWORD is set. See PostgreSQL
			         documentation about "trust":
			         https://www.postgresql.org/docs/current/auth-trust.html
			         In Docker's default configuration, this is effectively any other
			         container on the same system.

			         It is not recommended to use POSTGRES_HOST_AUTH_METHOD=trust. Replace
			         it with "-e HALO_PASSWORD=password" instead to set a password in
			         "docker run".
			********************************************************************************
		EOWARN
	fi
}

# usage: docker_process_init_files [file [file [...]]]
#    ie: docker_process_init_files /always-initdb.d/*
# process initializer files, based on file extensions and permissions
docker_process_init_files() {
	# psql here for backwards compatibility "${psql[@]}"
	psql=( docker_process_sql )

	printf '\n'
	local f
	for f; do
		case "$f" in
			*.sh)
				# https://github.com/docker-library/postgres/issues/450#issuecomment-393167936
				# https://github.com/docker-library/postgres/pull/452
				if [ -x "$f" ]; then
					printf '%s: running %s\n' "$0" "$f"
					"$f"
				else
					printf '%s: sourcing %s\n' "$0" "$f"
					. "$f"
				fi
				;;
			*.sql)     printf '%s: running %s\n' "$0" "$f"; docker_process_sql -f "$f"; printf '\n' ;;
			*.sql.gz)  printf '%s: running %s\n' "$0" "$f"; gunzip -c "$f" | docker_process_sql; printf '\n' ;;
			*.sql.xz)  printf '%s: running %s\n' "$0" "$f"; xzcat "$f" | docker_process_sql; printf '\n' ;;
			*.sql.zst) printf '%s: running %s\n' "$0" "$f"; zstd -dc "$f" | docker_process_sql; printf '\n' ;;
			*)         printf '%s: ignoring %s\n' "$0" "$f" ;;
		esac
		printf '\n'
	done
}

# Execute sql script, passed via stdin (or -f flag of pqsl)
# usage: docker_process_sql [psql-cli-args]
#    ie: docker_process_sql --dbname=mydb <<<'INSERT ...'
#    ie: docker_process_sql -f my-file.sql
#    ie: docker_process_sql <my-file.sql
docker_process_sql() {
	local query_runner=( psql -h /var/run/halo -v ON_ERROR_STOP=1 --username "$HALO_USER" --no-password --no-psqlrc )
	if [ -n "$HALO_DB" ]; then
		query_runner+=( --dbname "$HALO_DB" )
	fi

	PGHOST= PGHOSTADDR= "${query_runner[@]}" "$@"
}

# create initial database
# uses environment variables for input: HALO_DB
docker_setup_db() {
	local dbAlreadyExists
	dbAlreadyExists="$(
		HALO_DB= docker_process_sql --dbname halo0root --set db="$HALO_DB" --tuples-only <<-'EOSQL'
			SELECT 1 FROM pg_database WHERE datname = :'db' ;
		EOSQL
	)"
	if [ -z "$dbAlreadyExists" ]; then
		HALO_DB= docker_process_sql --dbname halo0root --set db="$HALO_DB" <<-'EOSQL'
			CREATE DATABASE :"db" ;
		EOSQL
		printf '\n'
	fi

	psql -c "CREATE USER $HALO_USER_REPLICATION PASSWORD '${HALO_PASSWORD_REPLICATION}' REPLICATION;"
    psql -c "CREATE USER $HALO_USER_REWIND SUPERUSER PASSWORD '${HALO_PASSWORD_REWIND}';"

	# psql -d $HALO_DB -c "create extension pg_stat_statements;"
	psql -d $HALO_DB -c "create extension aux_oracle cascade;"
	
}

# Loads various settings that are used elsewhere in the script
# This should be called before any other functions
docker_setup_env() {
	file_env 'HALO_PASSWORD' 'halo0root'
	file_env 'HALO_USER' 'halo'
	file_env 'HALO_DB' 'halo'


	file_env 'POSTGRES_INITDB_ARGS'
	: "${POSTGRES_HOST_AUTH_METHOD:=}"

	declare -g DATABASE_ALREADY_EXISTS
	: "${DATABASE_ALREADY_EXISTS:=}"
	# look specifically for PG_VERSION, as it is expected in the DB dir
	if [ -s "$PGDATA/PG_VERSION" ]; then
		DATABASE_ALREADY_EXISTS='true'
	fi
}




# start socket-only postgresql server for setting up or running scripts
# all arguments will be passed along as arguments to `postgres` (via pg_ctl)
docker_temp_server_start() {
	if [ "$1" = 'postgres' ]; then
		shift
	fi

	# internal start of server in order to allow setup using psql client
	# does not listen on external TCP/IP and waits until start finishes
	set -- "$@" -c listen_addresses='' -p "${PGPORT:-1921}"
	echo "$@"
	PGUSER="${PGUSER:-halo}" \
	pg_ctl -D "$PGDATA" \
		-o "$(printf '%q ' "$@")" \
		-w start
}

# stop postgresql server after done setting up user and running scripts
docker_temp_server_stop() {
	PGUSER="${PGUSER:-halo}" \
	pg_ctl -D "$PGDATA" -m fast -w stop
}

# check arguments for an option that would cause postgres to stop
# return true if there is one
_pg_want_help() {
	local arg
	for arg; do
		case "$arg" in
			# postgres --help | grep 'then exit'
			# leaving out -C on purpose since it always fails and is unhelpful:
			# postgres: could not access the server configuration file "/var/lib/postgresql/data/postgresql.conf": No such file or directory
			-'?'|--help|--describe-config|-V|--version)
				return 0
				;;
		esac
	done
	return 1
}

# setup for halo ，修改配置文件
docker_setup_postgres_conf(){
	pg_conf=$PGDATA/postgresql.conf
	echo "修改postgresql.conf"
	sed -i "s/#cluster_name = ''/cluster_name = 'halo-cluster'/" $pg_conf
	sed -i "s/#archive_mode = off/archive_mode = on/" $pg_conf
	sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" $pg_conf
	sed -i "s/#port = 1921/port = 1921/" $pg_conf
	sed -i "s/#logging_collector = off/logging_collector = on/" $pg_conf
	sed -i "s/#wal_buffers = -1/wal_buffers = 16MB/" $pg_conf
	sed -i "s/shared_buffers = 128MB/shared_buffers = 128MB/" $pg_conf
	# Oracle模式配置参数
	sed -i "s/#standard_parserengine_auxiliary = 'on'/standard_parserengine_auxiliary = 'on'/" $pg_conf
	sed -i "s/#database_compat_mode = 'postgresql'/database_compat_mode = 'oracle'/" $pg_conf
	sed -i "s/#oracle.use_datetime_as_date = false/oracle.use_datetime_as_date = true/" $pg_conf
	sed -i "s/#transform_null_equals = off/transform_null_equals = off/" $pg_conf
	#开启归档		
	sed -i "s/#archive_mode = off/archive_mode = on/" $pg_conf
	sed -i "s/#archive_command = ''/archive_command = 'test ! -f \/data\/halo\/archivedir\/%f \&\& cp %p \/data\/halo\/archivedir\/%f'/" $pg_conf
	sed -i "s/#restore_command = ''/restore_command = 'cp \/data\/halo\/archivedir\/%f %p'/" $pg_conf

}


# append POSTGRES_HOST_AUTH_METHOD to pg_hba.conf for "host" connections
# all arguments will be passed along as arguments to `postgres` for getting the value of 'password_encryption'
docker_setup_hba_conf() {

	{
					echo "host 		all 				all  			0/0 			md5"
			} >> "$PGDATA/pg_hba.conf"

}



_main() {
	# if first arg looks like a flag, assume we want to run postgres server
	if [ "${1:0:1}" = '-' ]; then
		set -- postgres "$@"
	fi

	if [ "$1" = 'postgres' ] && ! _pg_want_help "$@"; then
		docker_setup_env
		# setup data directories and permissions (when run as root)
		docker_create_db_directories
		if [ "$(id -u)" = '0' ]; then
			# then restart script as postgres user
			exec gosu halo "$BASH_SOURCE" "$@"
		fi

		# only run initialization on an empty data directory
		if [ -z "$DATABASE_ALREADY_EXISTS" ]; then
			docker_verify_minimum_env

			# check dir permissions to reduce likelihood of half-initialized database
			ls /docker-entrypoint-initdb.d/ > /dev/null

			docker_init_database_dir
			
			# #修改配置文件
			docker_setup_hba_conf
			docker_setup_postgres_conf

			# PGPASSWORD is required for psql when authentication is required for 'local' connections via pg_hba.conf and is otherwise harmless
			# e.g. when '--auth=md5' or '--auth-local=md5' is used in POSTGRES_INITDB_ARGS
			export PGPASSWORD="${PGPASSWORD:-$HALO_PASSWORD}"
			docker_temp_server_start "$@"

			docker_setup_db

			docker_process_init_files /docker-entrypoint-initdb.d/*

			docker_temp_server_stop
			
			unset PGPASSWORD

			cat <<-'EOM'

				Halo init process complete; ready for start up.

			EOM

		else
			cat <<-'EOM'

				Halo Database directory appears to contain a database; Skipping initialization

			EOM
		fi
	fi

	pg_ctl start

	# exec "$@" 
	# exit 0
}

if ! _is_sourced; then
	_main "$@"
fi
