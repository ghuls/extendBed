#!/bin/bash
#
# Copyright (C) 2013  - Gert Hulselmans
#
# Purpose: Extend/truncate intervals in BED files based on the given
#          arguments, but keep them between the chromosome boundaries.



# Define the location of mawk and gawk:
#
# Those values can be overwritten from outside of this script with:
#      MAWK=/some/path/to/mawk ./extendBed.sh
# Or:
#      export MAWK=/some/path/to/mawk
#      ./extendBed.sh
trash="${MAWK:='mawk'}";
trash="${GAWK:='gawk'}";

# Try to use the following awk variants in the following order:
#   1. mawk
#   2. gawk
#   3. awk
if [ $(type "${MAWK}" > /dev/null 2>&1; echo $?) -eq 0 ] ; then
    AWK="${MAWK}";
elif  [ $(type "${GAWK}" > /dev/null 2>&1; echo $?) -eq 0 ] ; then
    AWK="${GAWK}";
else
    AWK='awk';
fi



# Filename of the file that contains the chromosome names and their size.
SPECIES_CHROM_SIZES='';

# Default parameters passed to awk part of this script which can be changed by
# the arguments passed to this script.
rightSlop=0;
leftSlop=0;
stranded=0;
fromStart=0;
fromEnd=0;

# Create an array for storing all BED filenames passed on the command line.
declare -a BED_files;
# Index for the BED_files array.
declare -i i=0;





# Function for printing the help text.
usage () {
    add_spaces="           ${0//?/ }";

    printf "\n%s\n%s\n%s\n%s\n\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n\n%s\n%s\n%s\n\n" \
           "Usage:     ${0} -g species_chromosome_file" \
           "${add_spaces} [-l number] [-r number]" \
           "${add_spaces} [--stranded] [--fromstart] [--fromend]" \
           "${add_spaces} [file(s)]" \
           "Arguments:" \
           "           -g species_chromosome_file" \
           "                        File with chromosome names and their size." \
           "           -l number    Extend(+)/truncate(-) number of bases from start." \
           "           -r number    Extend(+)/truncate(-) number of bases from end." \
           "           --stranded   Take into acount the strand info." \
           "           --fromstart  Extend/truncate interval start and end based on" \
           "                        current start only." \
           "           --fromend    Extend/truncate interval start and end based on" \
           "                        current end only." \
           "Purpose:" \
           "           Extend/truncate intervals in BED files based on the given" \
           "           arguments, but keep them between the chromosome boundaries.";
}





# Retrieve passed arguments and filenames.
until ( [ -z "$1" ] ) ; do
    case "${1}" in
        -g)          if [ -z "${2}" ] ; then
                         printf "\nERROR: Parameter '-g' requires a species chromosome file as argument.\n\n";
                         exit 1;
                     else
                         SPECIES_CHROM_SIZES="${2}";
                         shift 2;
                     fi;;
        -h)          usage;
                     exit 0;;
        --help)      usage;
                     exit 0;;
        -l)          if [ -z "${2}" ] ; then
                         printf "\nERROR: Parameter '-l' requires a integer value as argument.\n\n";
                         exit 1;
                     else
                         leftSlop="${2}";
                         shift 2;
                     fi;;
        -r)          if [ -z "${2}" ] ; then
                         printf "\nERROR: Parameter '-r' requires a integer value as argument.\n\n";
                         exit 1;
                     else
                         rightSlop="${2}";
                         shift 2;
                     fi;;
        --stranded)  stranded=1;
                     shift 1;;
        --fromstart) fromStart=1;
                     normalSlop=0;
                     shift 1;;
        --fromend)   fromEnd=1;
                     normalSlop=0;
                     shift 1;;
        --usage)     usage;
                     exit 0;;
        -)           # Add stdin to array.
                     BED_files[${i}]='-';
                     i=i+1;
                     shift 1;;
        *)           if [ ! -e "${1}" ] ; then
                         printf "\nERROR: Unknown parameter '$1'.\n\n";
                         usage;
                         exit 1;
                     fi
                     # Add BED files to array.
                     BED_files[${i}]="${1}";
                     i=i+1;
                     shift 1;;
    esac
done



if [ -z "${SPECIES_CHROM_SIZES}" ] ; then
    printf "\nERROR: Specify a species chromosome file.\n\n";
    exit 1;
elif [ ! -f "${SPECIES_CHROM_SIZES}" ] ; then
    printf "\nERROR: The species chromosome file '%s' could not be found.\n\n" "${SPECIES_CHROM_SIZES}";
    exit 1;
fi



if ( [ "${fromStart}" -eq 1 ] && [ "${fromEnd}" -eq 1 ] ) ; then
    printf "\nERROR: '--fromstart' and '--fromend' can not be used at the same time.\n\n";
    exit 1;
fi





# Extend/truncate intervals in BED files:
#   * Make sure that extended intervals stay inside the chromosome boundaries by
#     specifying a species specific chromosome file with all chromosome names
#     and their sizes. This file can be generated with fetchChromSizes of UCSC:
#
#       ${KENT_DIR}/src/utils/userApps/fetchChromSizes" hg19 > hg19.chrom.sizes
#
#   * Extend/truncate the interval to the left or to the right with x basepares:
#       - leftSlop=X:
#           ==> Change interval start with X basepares upstream or left.
#       - rightSlop=Y:
#           ==> Change interval end with Y basepares downstream or right.
#
#   * Allow to take into account the strand when extending or truncating:
#       - stranded=0: don't use at strand info
#       - stranded=1: use strand info
#
#   * Extend/truncate interval start and end based on the current start or end:
#       - fromStart=0 and fromEnd=0:
#           ==> default: Extend/truncate interval start and end from current
#               start and end respectively.
#       - fromStart=1 and fromEnd=0:
#           ==> Extend/truncate interval start and end based on current start
#               position only.
#       - fromStart=0 and fromEnd=1:
#           ==> Extend/truncate interval start and end based on current end
#               position only.
#       - fromStart=1 and fromEnd=1:
#           ==> Invalid combination.
"${AWK}" \
    -v species_chrom_file="${SPECIES_CHROM_SIZES}" \
    -v leftSlop="${leftSlop}" \
    -v rightSlop="${rightSlop}" \
    -v stranded="${stranded}" \
    -v fromStart="${fromStart}" \
    -v fromEnd="${fromEnd}" \
    '
    BEGIN {
            # Set input and output field separator.
            FS=OFS="\t";

            # Read chromosome names and their corresponding length in an array.
            while ( (getline < species_chrom_file) > 0 ) {
                chrom_size_array[$1] = $2;
            }
    }
    {
            if ( NF == 0 ) {
                # Skip empty line.
                next;
            } else if ( substr($0,1,1) != "#" ) {
                if ( NF < 3 ) {
                    print "\nERROR: BED file \"" FILENAME "\" does not have 3 or more columns on line " FNR ".\n\n" $0 > "/dev/stderr";
                    exit 1;
                }

                chrom = $1;
                start = $2;
                end = $3;

                # Check if the first 3 columns contain some content.
                if ( (length(chrom) == 0) || (length(start) == 0) || (length(end) == 0) ) {
                    print "\nERROR: line " FNR " of \"" FILENAME "\" does not contain values in one of the first 3 columns.\n\n" $0 > "/dev/stderr";
                    exit 1;
                }

                # Error out if we find a chromosome name that we do not find in
                # the species chromosome file.
                if ( ! ( chrom in chrom_size_array ) ) {
                    print "\nERROR: Chromosome \"" chrom "\" does not appear in species chromosome file \"" species_chrom_file "\".\n" > "/dev/stderr";
                    exit 1;
                }

                # Check if the start and end coordinate are integer values.
                if ( int(start) != start ) {
                    print "\nERROR: start coordinate on line " FNR " of \"" FILENAME "\" is not a number.\n\n" $0 > "/dev/stderr";
                    exit 1;
                } else if ( int(end) != end ) {
                    print "\nERROR: end coordinate on line " FNR " of \"" FILENAME "\" is not a number.\n\n" $0 > "/dev/stderr";
                    exit 1;
                }

                if ( fromStart == 1 ) {
                    # When fromStart = 1 (true), region extensions/truncations
                    # are calculated based on the start coordinate of the
                    # interval for both the start and end coordinates.
                    if ( (stranded == 1) && ($6 == "-") ) {
                        # Take into account the strand information when the
                        # "stranded" parameter is set and we have a interval
                        # located on the negative strand.
                        #
                        # The end coordinate (column 3) in the BED file is the
                        # start coordinate of the region from which the
                        # extension/truncation of the region will be calculated.
                        start = $3 - rightSlop;
                        end = $3 + leftSlop;
                    } else {
                        # The start coordinate (column 2) in the BED file is the
                        # start coordinate of the region from which the
                        # extension/truncation of the region will be calculated.
                        start = $2 - leftSlop;
                        end = $2 + rightSlop;
                    }
                } else if (fromEnd == 1) {
                    # When fromEnd = 1 (true), region extensions/truncations
                    # are calculated based on the end coordinate of the interval
                    # for both the start and end coordinates.
                    if ( (stranded == 1) && ($6 == "-") ) {
                        # Take into account the strand information when the
                        # "stranded" parameter is set and we have a interval
                        # located on the negative strand.
                        #
                        # The start coordinate (column 2) in the BED file is the
                        # end coordinate of the region from which the
                        # extension/truncation of the region will be calculated.
                        start = $2 - rightSlop;
                        end = $2 + leftSlop;
                    } else {
                        # The end coordinate (column 3) in the BED file is the
                        # end coordinate of the region from which the
                        # extension/truncation of the region will be calculated.
                        start = $3 - leftSlop;
                        end = $3 + rightSlop;
                    }
                } else {
                    # Default.
                    if ( (stranded == 1) && ($6 == "-") ) {
                        # Take into account the strand information when the
                        # "stranded" parameter is set and we have a interval
                        # located on the negative strand.
                        start = $2 - rightSlop;
                        end = $3 + leftSlop;
                    } else {
                        start = $2 - leftSlop;
                        end = $3 + rightSlop;
                    }
                }

                # Check if the start coordinate does not go beyond the chromosome
                # boundary.
                if (start < 0) {
                    start = 0;
                } else if ( start >= chrom_size_array[chrom] ) {
                    start = chrom_size_array[chrom] - 1;
                }

                # Check if the end coordinate does not go beyond the chromosome
                # boundary.
                if (end <= 0) {
                    end = 1;
                }
                if (end > chrom_size_array[chrom]) {
                    end = chrom_size_array[chrom];
                }

                # Print modified coordinates.
                printf chrom "\t" start "\t" end;

                # Print columns 4 and higher if they exist.
                for ( i = 4; i <= NF; i++ ) {
                    printf "\t" $i;
                }

                # Print newline to finalize the current line.
                printf "\n";
            } else {
                # Print all commented lines.
                print $0;
            }
    }' "${BED_files[@]}";



# Return the exit code returned by the awk command.
exit $?;
