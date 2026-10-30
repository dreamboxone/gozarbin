# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone

# GitHub's /latest endpoint excludes prereleases. Select the first published,
# supported tag from /releases, preserving its assets and prerelease flag.
select_release() {
	local file=$1 tag draft prerelease index=0 selected matched=0
	tag=$(jsonfilter -i "$file" -e '@.tag_name' 2>/dev/null || true)
	if ! valid_tag "$tag"; then
		while [ "$index" -lt 20 ]; do
			tag=$(jsonfilter -i "$file" -e "@[$index].tag_name" 2>/dev/null || true)
			[ -n "$tag" ] || return 1
			draft=$(jsonfilter -i "$file" -e "@[$index].draft" 2>/dev/null || true)
			if [ "$draft" != true ] && valid_tag "$tag"; then
				selected="$file.selected"
				jsonfilter -i "$file" -e "@[$index]" > "$selected" || return 1
				mv "$selected" "$file"
				matched=1
				break
			fi
			index=$((index + 1))
		done
		[ "$matched" = 1 ] || return 1
	fi
	valid_tag "$tag" || return 1
	draft=$(jsonfilter -i "$file" -e '@.draft' 2>/dev/null || true)
	[ "$draft" != true ] || return 1
	prerelease=$(jsonfilter -i "$file" -e '@.prerelease' 2>/dev/null || true)
	case "$prerelease" in true) ;; *) prerelease=false ;; esac
	printf '%s' "$prerelease" > "$RUN/prerelease"
	printf '%s' "$tag"
}
