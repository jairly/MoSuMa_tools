#####################################################################
# TREECLEANER.pl final version by Al Tanner (July 2014). Latest mod: 30 sept 2019 bt Davide Pisani
# AT: It is your responsibility to check that the output of this script is sensible!
# Examines NEWICK trees for long branches
# If you use to remove fast evolving taxa from a phylip alignment
# it is imperative that you make sure the taxon names in the tree
# and in the alignment are identical
# Please report bugs on github/altanner/MoSuMa_tools        Thanks :)
#####################################################################

use strict;
use warnings;
use Bio::TreeIO;
use Text::Balanced 'extract_bracketed';
use List::Util qw(sum);
# use Statistics::Basic qw(:all); # this might cause problems to some people

if (! $ARGV[1]) {
    print "=== treecleaner.pl: USAGE: perl treecleaner.pl [tree file in Newick format] [threshold branch length]\n";
    print "=== EXAMPLE (3 standard deviations of mean length as threshold): perl treecleaner.pl fibro.tree 3\n";
    print "=== The higher the threshold branch length, the fewer branches will be identified as LONG.\n";
    print "=== To automatically modify the phylip file corresponding to the tree, add this after the threshold.\n";
    die "=== EXAMPLE: perl treecleaner.pl fibro.tree 3 fibro.phy\n";
}

if ($ARGV[2]) { # examine matrix file to modify
    if (! -e $ARGV[2]) {
	die "Phylip file \"$ARGV[2]\" doesn't exist here.\n";
    }    
    if (`grep "^>" $ARGV[2]`) {
	die "File \"$ARGV[2]\" looks like a fasta file. I can only modify phylip files.\n";
    }
}

my $threshold = $ARGV[1];

# open file
open (TREEFILE, "<$ARGV[0]") || die "treecleaner.pl: Cannot find $ARGV[0] [$!]\n";  
my $newick = <TREEFILE>; 
if (`grep -o ";" $ARGV[0] | wc -l` != 1) { # checks for tree formatting.
    print "Tree file \"$ARGV[0]\" doesn't seem to have the correct number of semi-colons.\n";
    die "Please check the tree is in Newick format.\n";
}
if (`grep -o "(" $ARGV[0] | wc -l` != `grep -o ")" $ARGV[0] | wc -l`) {
    print "There are an unequal number of close and open brackets in $ARGV[0].\n";
    die "Please check the tree is in Newick format.\n";
}
close (TREEFILE);                          # end format checks

# clean up newick and generate warnings
chomp $newick;
my $space_warning = 0;
my $pipe_warning = 0;
my $plus_warning = 0;
if ($newick =~ m/\s+/) {
    $newick =~ s/\s//g;
    $space_warning = 1; # space warning
}
if ($newick =~ m/\|/) {
    $newick =~ s/\|//g;
    $pipe_warning = 1;  # pipe warning
}
if ($newick =~ m/\+/) {
    $newick =~ s/\+//g;
    $plus_warning = 1;  # plus warning
}

# save a clean version of the newick string (for grepping later)
my $clean_newick_temporary = $ARGV[0] . ".cln";
open (OUT, ">$clean_newick_temporary") || die "Problem making temporary clean newick file...\n";
print OUT "$newick";
close OUT;

# isolate branch lengths and taxa names
my @branch_lengths = $newick =~ /\d+[\.?\d+]*/g;        # match number, with or without decimal point
my @terminal_branches = $newick =~ /\w+:\d+[\.?\d+]*/g; # match [string] ":" [number, with or without decimal point]
for my $index (reverse 0..$#terminal_branches) {        # clean out bootstrap supports that have been
    if ( $terminal_branches[$index] =~ /^\d/ ) {        # mistaken for taxa names.
        splice(@terminal_branches, $index, 1, ());
    }
}

push (my @clade_search_input, $newick);
my $clade_count = () = $newick =~ /\)/g;                # counts occurence of "(" in tree string.
my $total_clade_count = $clade_count + (scalar (@terminal_branches));

print "\ntreecleaner.pl =======================================================\n\n";
print "Terminal clade (taxa) count\t\t" . @terminal_branches . "\n";
print "Multiple-member clade count\t\t$clade_count\n";
print "Total clade count\t\t\t$total_clade_count\n";
# uncomment next line for verbose output
#print "\nTERMINAL CLADES (" . @terminal_branches . ")\t\tBRANCH LENGTHS\n";
my $taxa;
my $length;
my %taxa_length;
foreach (@terminal_branches) {
    ($taxa, $length) = split (/:/,$_);
    $taxa_length{$taxa} = $length;
}    

my @keys = keys(%taxa_length);
# uncomment this loop for verbose output
#foreach my $key (@keys) {
#    printf ("%-25s\t%-20s\n", $key, $taxa_length{$key});
#}


# multiple clades search regex
my $clade_search_regex = qr/
    (                   # start of bracket 1
    \(                  # match an opening bracket
        (?:
        [^\(\)]++       # one or more brackets, non backtracking
            |
           (?1)         # recurse to bracket 1
        )*
    \)                  # match a closing bracket
    )                   # end of bracket 1
    /x;

$" = "\n\t";

my @multi_clades;
while (@clade_search_input) {
    my $string = shift @clade_search_input;
    my @groups = $string =~ m/$clade_search_regex/g;
    push (@multi_clades, @groups) if @groups;
    unshift @clade_search_input, map { s/^\(//; s/\)$//; $_ } @groups;
}

# uncomment next line for verbose output header
#print "\nMULTIPLE MEMBER CLADES (" . $clade_count . ")\n"; # displays readable clade members

my %multi_clades_and_lengths;
foreach (@multi_clades) {
    my $multi_clade_members = $_;
    $multi_clade_members =~ s/\(+//;
    $multi_clade_members =~ s/:.*?,/ + /g;   # replace stuff between : and , with +
    $multi_clade_members =~ s/\(//g;         # remove other brackets
    $multi_clade_members =~ s/:.*?\)$//;     # remove closing bracket
    s/\(/\\\(/g;                             # replace open bracket with ACTUAL backslash open bracket
    s/\)/\\\)/g;                             # replace close bracked with ACTUAL backslash close bracket
#    my $multi_clade_length = `grep -E -o "$_.*?[,|)]" $clean_newick_temporary`;
#    $multi_clade_length =~ s/^.*://g;        # remove stuff at start
#    $multi_clade_length =~ s/.$//g;          # remove last char, usually ","
#    $multi_clades_and_lengths{$multi_clade_members} = $multi_clade_length;
}

# The four lines above are commented because for some reason grep can run out of
# memory and it wont work... not sure about this. Clearly I'm being stupid.

# uncomment the following line for full multiple member clade commentary output
#print "$_ $multi_clades_and_lengths{$_}\n" for (keys %multi_clades_and_lengths);

my $sum_branch_lengths;
my @lengths_difference;
my %clade_branch_length;

# tree statistics                                           
my $branch_count = scalar @branch_lengths;
print "Branch count\t\t\t\t$branch_count\n";
foreach (@branch_lengths) {
    $sum_branch_lengths += $_;
}
my $mean_branch_length = $sum_branch_lengths / $branch_count;
print "Mean branch length\t\t\t$mean_branch_length\n";

# generate standard deviation
@lengths_difference = @branch_lengths;
foreach (@lengths_difference) {
    $_ = ($_ - $mean_branch_length);
    $_ *= $_;
}
my $differences_summed = sum (@lengths_difference);
my $lengths_standard_deviation = sqrt ($differences_summed / $branch_count);
print "Branch length standard deviation\t$lengths_standard_deviation\n";
print "Threshold length = $threshold standard deviations more than the mean.\n";
my $actual_threshold = ($mean_branch_length + ($threshold * $lengths_standard_deviation));
print "                \(= $actual_threshold\)\n";

# look for long terminal branches
my $terminal_long_branch_count = 0;
foreach my $branch_length (@branch_lengths) {
    if ($branch_length > $actual_threshold) {
	$terminal_long_branch_count++;
    }
}

# initiate hash of taxa to remove
my @taxa_to_remove = "";
# print terminal long branches
if ($terminal_long_branch_count > 0) {
    print "\n----- Long branched taxa or clades in $ARGV[0] -----\n";
    my @keys = sort { $taxa_length{$b} <=> $taxa_length{$a} } keys(%taxa_length);
    my @vals = @taxa_length{@keys};
    my $counter1 = 0;
    for (my $i=0; $i < $terminal_long_branch_count; $i++) {
	print "\t\($keys[$counter1]\)\n";
	push (@taxa_to_remove, $keys[$counter1]); # add to the list of taxa to remove
	$counter1++;
    }
}
# print internal long branches
# if there are more than half the entire tree in a long branch clade,
# the search has picked up the wrong end of the branch, and should ignore
# the content of the multi clade hash.
my $half_taxa_count = (scalar (@terminal_branches) / 2);
my $internal_long_branch_count = 0;
my $majority_clade_bool = 0;
for (keys %multi_clades_and_lengths) {
    chomp;
    if (! $multi_clades_and_lengths{$_}) { # skip empty values (clade of whole tree will 
	next;                              # have an empty length value)
    }
    if ($multi_clades_and_lengths{$_} > $actual_threshold) { 
	print "\t\($_\)\n"; 
	s/[ \+ ]/\+/g;
	my @internal_long_branch_clades_to_add = split ('\+', $_);
	@internal_long_branch_clades_to_add = grep /\S/, @internal_long_branch_clades_to_add;
	foreach my $clade_members_to_add (@internal_long_branch_clades_to_add) {
	    chomp;
	    s/\s//g;
	    s/\+//g;
	    my $array_size = scalar (@internal_long_branch_clades_to_add);
	    if ($half_taxa_count > $array_size) {
		push (@taxa_to_remove, $clade_members_to_add);
	    }
	    else {
		$majority_clade_bool = 1;
	    }
	}
	$internal_long_branch_count++;
    }
}
if ($majority_clade_bool == 1) {
    print "      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n";
    print "----- This clade contains more than half of the taxa representation -----\n";
    print "----- Long branches leading to major clades are ignored - these taxa will not be removed from matrix -----\n";
}

@taxa_to_remove = grep /\S/, @taxa_to_remove; # clean up array of empty lines

my $total_long_branch_count = $terminal_long_branch_count + $internal_long_branch_count;
my $number_of_taxa_to_remove = scalar (@taxa_to_remove);
print "\n----- $number_of_taxa_to_remove taxa associated with long branches -----\n";
print "\t@taxa_to_remove\n";

# report any warnings generated
if ($pipe_warning == 1) {
    print "\nWARNING: $ARGV[0] contained the symbol \"\|\", this symbol was removed before parsing.\n";
}
if ($space_warning == 1) {
    print "\nWARNING: $ARGV[0] contained spaces. Spaces were removed before parsing.\n";
}
if ($plus_warning == 1) {
    print "\nWARNING: $ARGV[0] contained the symbol \"+\". Plusses were removed before parsing.\n";
}

# create new phylip file with taxa removed and metadata updated for correct taxa count.
if ($ARGV[2]) {
    chomp $ARGV[2];
    my $phylip_infile = $ARGV[2];
    my @dimensions_original_file;
    my %alignment;
    my $new_extension = "\.edited";
    my $outfile = $phylip_infile . $new_extension;
    my $number_of_sequences_to_remove = scalar (@taxa_to_remove);
    #DEBUG - test what is in @taxa_to_remove
    #print "\nBEBUG:  name of taxa to remove in \@taxa_to_remove array:\n@taxa_to_remove \n";
    #DEBUG DONE
   
    open (PHYLYP_ALIGNMENT, "<$phylip_infile") || die "cannot open $phylip_infile \n";
    while (<PHYLYP_ALIGNMENT>) # Read phylyp alignment and store alignment in hash named %alinment
    {
	chomp $_;
	if ($_ =~ /^[0-9]+\s+[0-9]+$/) # extract dimensions of alignment - first line phylyp formatted file
	{
	    @dimensions_original_file = split (/ +/, $_);
	}	
	else
	{
       	my @one_species_and_data = split (/\s+/, $_);   # read in all the sequence data and pass them to hash 
	$alignment{$one_species_and_data[0]} = $one_species_and_data[1];
	}
    }
    close PHYLYP_ALIGNMENT;
    

    print "\n";

    foreach my $taxon_to_remove (@taxa_to_remove) 
    {

	print "TAXON & Sequence " . $taxon_to_remove .  "\t" . $alignment{$taxon_to_remove} . "removed from alignment\n"; #DEBUG LINE
	delete($alignment{$taxon_to_remove});
    }
    my @keys_reduced_alignment = keys(%alignment);

    print "\nThe size of the reduced alignment is = " . (scalar(@keys_reduced_alignment)) . "\n";  
    print "The size of the original alignment was = " . $dimensions_original_file[0] . "\n";

    open (OUT_PHYLYP, ">$outfile") || die "cannot opne $outfile \n";
    my $new_number_of_taxa = $dimensions_original_file[0] - $number_of_sequences_to_remove;
    my $number_of_characters = $dimensions_original_file[1];
    print OUT_PHYLYP $new_number_of_taxa . " " . $number_of_characters . "\n";
    foreach my $taxon (@keys_reduced_alignment)
    {
	print OUT_PHYLYP $taxon . "\t\t\t\t" . $alignment{$taxon} . "\n";
    }

print "\n$number_of_sequences_to_remove long branching taxa removed from $phylip_infile, saved to $outfile\n";
}

print "\nDone =================================================================\n\n";

# remove temporary newick file
`rm $clean_newick_temporary`;

