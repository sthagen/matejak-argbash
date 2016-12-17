#!/bin/bash

version=_ARGBASH_VERSION
# DEFINE_SCRIPT_DIR
# ARG_POSITIONAL_SINGLE([input], [The input template file (pass '-' for stdout)])
# ARG_OPTIONAL_SINGLE([output], o, [Name of the output file (pass '-' for stdout)], -)
# ARG_OPTIONAL_BOOLEAN([library],, [Whether the input file if the pure parsing library.])
# ARG_OPTIONAL_BOOLEAN([check-typos],, [Whether to check for possible argbash macro typos], [on])
# ARG_OPTIONAL_BOOLEAN([commented], c, [Commented mode - include explanatory comments with the parsing code], [off])
# ARG_OPTIONAL_REPEATED([search], I, [Directories to search for the wrapped scripts (directory of the template will be added to the end of the list)], ["."])
# ARG_OPTIONAL_SINGLE([debug],, [(developer option) Tell autom4te to trace a macro])
# ARG_VERSION([echo "argbash v$version"])
# ARG_HELP([Argbash is an argument parser generator for Bash.])

# ARGBASH_GO

# [

_trap=

# The main function that generates the parsing script body
do_stuff ()
{
	local _pass_also="$_wrapped_defns"
	test "$_arg_commented" = on && _pass_also="${_pass_also}m4_define([COMMENT_OUTPUT])"
	echo "$_pass_also" \
		| cat - "$m4dir/stuff.m4" "$output_m4" "$infile" \
		| autom4te "${DEBUG[@]}" -l m4sugar -I "$m4dir" \
		| grep -v '^#\s*needed because of Argbash -->\s*$' \
		| grep -v '^#\s*<-- needed because of Argbash\s*$'
	local _ret=$?
	if test $_ret != 0
	then
		echo "Error during autom4te run, aborting!" >&2;
		exit $_ret;
	fi
}

# Fills content to variable _wrapped_defns --- where are scripts of given stems
settle_wrapped_fname ()
{
	# Get arguments to ARGBASH_WRAP
	# Based on http://stackoverflow.com/a/19772067/592892
	IFS=$'\n' _srcfiles=($(echo 'm4_changecom()m4_define([ARGBASH_WRAP])' "$(cat "$infile")" \
			| autom4te -l m4sugar -t 'ARGBASH_WRAP:$1'))

	test "${#_srcfiles[@]}" -gt 0 || return
	for srcstem in "${_srcfiles[@]}"
	do
		_found=no
		for searchdir in "${_arg_search[@]}"
		do
			test -f "$searchdir/$srcstem.m4" && { _found=yes; ext='.m4'; break; }
			test -f "$searchdir/$srcstem.sh" && { _found=yes; ext='.sh'; break; }
			test -f "$searchdir/$srcstem.sh" && { _found=yes; ext=''; break; }
		done
		# The last searchdir is a correct one
		test $_found = yes || { echo "Couldn't find wrapped file of stem '$srcstem' in any of dirrectories: ${_arg_search[*]}" >&2; exit 2; }
		_wrapped_defns="${_wrapped_defns}m4_define([_SCRIPT_$srcstem], [[$searchdir/$srcstem$ext]])"
	done
}

# If we want to have the parsing code in a separate file,
# 1. Find out the (possible) filename
# 2. If the file exists, finish (OK).
# 3. If the .m4 file exists, finish (OK)
# 4. Something is wrong
function get_parsing_code
{
	# Get the argument of INCLUDE_PARSING_CODE
	_srcfile="$(echo 'm4_changecom()m4_define([INCLUDE_PARSING_CODE])' "$(cat "$infile")" \
			| autom4te -l m4sugar -t 'INCLUDE_PARSING_CODE:$1' \
			| tail -n 1)"
	test -n "$_srcfile" || return 1
	_thatfile="$(dirname "$infile")/$_srcfile"
	test -f "$_thatfile" && echo "$_thatfile" && return
	# Take out everything after last dot (http://stackoverflow.com/questions/125281/how-do-i-remove-the-file-suffix-and-path-portion-from-a-path-string-in-bash)
	_thatfile="${_thatfile%.*}.m4"
	test -f "$_thatfile" && echo "$_thatfile" && return
	# if we are here, we are out of luck
	test -n "$_srcfile" && echo "Strange, we think that there was a source file '$_srcfile' that should be included, but we haven't found it in directory '$(dirname "$_thatfile")'" >&2 && return 1
}

# MS Windows compatibility fix
discard=/dev/null
test -e $discard || discard=NUL

set -o pipefail

infile="$_arg_input"

# If we are reading from stdout, then create a temp file
if test "$infile" = '-'
then
	infile=temp_in_$$
	rm_temp="yes"
	_trap="$_trap rm -f $infile;"
	trap "$_trap" EXIT
	cat > "$infile"
fi

m4dir="$script_dir/../src"
test -n "$_arg_debug" && DEBUG=('-t' "$_arg_debug")

output_m4="$m4dir/output.m4"
test "$_arg_library" = "on" && output_m4="$m4dir/output-standalone.m4"

test -f "$infile" || _PRINT_HELP=yes die "argument '$infile' is supposed to be a file!" 1
test -n "$_arg_output" || { echo "The output can't be blank - it is not a legal filename!" >&2; exit 1; }
outfname="$_arg_output"
autom4te --version > "$discard" 2>&1 || { echo "You need the 'autom4te' utility (it comes with 'autoconf'), if you have bash, that one is an easy one to get." 2>&1; exit 1; }
_arg_search+=("$(dirname "$infile")")
_wrapped_defns=""

# So let's settle the parsing code first. Hopefully we won't create a loop.
parsing_code="$(get_parsing_code)"
# Just if the original was m4, we replace .m4 with .sh
test -n "$parsing_code" && parsing_code_out="${parsing_code:0:-2}sh"
test "$_arg_library" = off && test -n "$parsing_code" && ($0 --library "$parsing_code" -o "$parsing_code_out")

# We may use some of the wrapping stuff, so let's fill the _wrapped_defns
settle_wrapped_fname

output="$(do_stuff)" || die "" "$?"
if test "$_arg_check_typos" = on
then
	# match against suspicious, then inverse match against correct stuff:
	# #<optional whitespace>\(allowed\|another allowed\|...\)<optional whitespace><opening bracket <or> end of line>
	# Then, extract all matches (assumed to be alnum chars + '_') from grep and put them in the error msg.
	grep_output="$(printf "%s" "$output" | grep '^#\s*\(ARG_\|ARGBASH\)' | grep -v '^#\s*\(]m4_set_contents([_KNOWN_MACROS], [\|])[\)\s*\((\|$\)' | sed -e 's/#\s*\([[:alnum:]_]*\).*/\1 /' | tr -d '\n\r')"
	test -n "$grep_output" && die "Your script contains possible misspelled Argbash macros: $grep_output" 1
fi
if test "$outfname" != '-'
then
	printf "%s\n" "$output" > "$outfname"
	chmod a+x "$outfname"
else
	printf "%s\n" "$output"
fi

# ]dnl
dnl vim: filetype=sh
