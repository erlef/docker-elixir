#!/usr/bin/env bash
set -eu

declare -a -r versions=(
	# https://github.com/elixir-lang/elixir/blob/main/SECURITY.md#supported-versions
	1.18
	1.17
	1.16
	1.15
	1.14
	1.13
	1.12
)
declare -A -r aliases=(
	[1.18]='latest'
)

# get the most recent commit which modified any of "$@"
fileCommit() {
	git log -1 --format='format:%H' HEAD -- "$@"
}

# get the most recent commit which modified "$1/Dockerfile" or any file COPY'd from "$1/Dockerfile"
dirCommit() {
	local dir="$1"; shift
	(
		cd "$dir"
		fileCommit \
			Dockerfile \
			$(git show HEAD:./Dockerfile | awk '
				toupper($1) == "COPY" {
					for (i = 2; i < NF; i++) {
						print $i
					}
				}
			')
	)
}

# prints "$2$1$3$1...$N"
join() {
	local sep="$1"; shift
	local out; printf -v out "${sep//%/%%}%s" "$@"
	echo "${out#$sep}"
}

extractElixirVersion() {
  awk '
        $1 == "ENV" && /_VERSION/ {
        match($2, /"v(.*)"/)
        print substr($2, RSTART + 2, RLENGTH - 3)
        exit
      }'

}

extractErlangVersion() {
  awk '
        $1 == "FROM" && /erlang/ {
        match($2, /"erlang\:(.*)"/)
        print substr($2, RSTART + 8)
        exit
      }'
}

self="${BASH_SOURCE##*/}"

cat <<-EOH
# this file is generated via https://github.com/erlef/docker-elixir/blob/$(fileCommit "$self")/$self

Maintainers: . <c0b@users.noreply.github.com> (@c0b),
             Tristan Sloughter <t@crashfast.com> (@tsloughter)
GitRepo: https://github.com/erlef/docker-elixir.git
EOH

for version in "${versions[@]}"; do
	commit="$(dirCommit "$version")"

	fullVersion="$(git show "$commit":"$version/Dockerfile" | extractElixirVersion)"

	versionAliases=( $fullVersion )
	while :; do
		localVersion="${fullVersion%.*}"
		if [ "$localVersion" = "$version" ]; then
			break
		fi
		versionAliases+=( $localVersion )
		fullVersion=$localVersion
		# echo "${versionAliases[@]}"
	done
	versionAliases+=( $version ${aliases[$version]:-} )

	for variant in '' slim alpine otp-23-slim otp-{24,25,26,27}{,-alpine,-slim}; do
		dir="$version${variant:+/$variant}"
		[ -f "$dir/Dockerfile" ] || continue

		commit="$(dirCommit "$dir")"

		variantAliases=( "${versionAliases[@]}" )
		if [ -n "$variant" ]; then
			variantAliases=( "${variantAliases[@]/%/-$variant}" )
			variantAliases=( "${variantAliases[@]//latest-/}" )
		fi

		erlangVersion="$(git show "$commit":"$dir/Dockerfile" | extractErlangVersion )"
		otpVersionAndVariant="otp-${erlangVersion}"

		if [ "$otpVersionAndVariant" != "$variant" ]; then
			variantAliases=( "${variantAliases[@]}" "${versionAliases[@]/%/-$otpVersionAndVariant}" )
			variantAliases=( "${variantAliases[@]//latest-/}" )
		fi

		variantArches=( amd64 arm32v7 arm64v8 i386 s390x ppc64le )

		case "$version" in
			1.13|1.12|1.11|1.10|1.9|1.8|1.7|1.6)
				variantArches=( ${variantArches[@]/ppc64le} )
				variantArches=( ${variantArches[@]/s390x} )
		esac

		case "$variant" in
			otp-24 | otp-24-alpine | otp-24-slim | otp-25 | otp-25-alpine | otp-25-slim )
			  variantArches=( ${variantArches[@]/ppc64le} )
			  variantArches=( ${variantArches[@]/s390x} )
		esac

		echo
		cat <<-EOE
			Tags: $(join ', ' "${variantAliases[@]}")
			Architectures: $(join ', ' "${variantArches[@]}")
			GitCommit: $commit
			Directory: $dir
		EOE
	done
done
