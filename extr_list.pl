#!/usr/bin/perl
# export the list in tab separated text

$file = shift;

open IN, "<$file" or die "dsfaers";
open ALL, ">eur_and_us.tick";
open XTR, ">germany.tick";

while ($in = <IN>) {
	@tick = split /\t/, $in; # print "$tick[9]\n";
	$ticker = $tick[9];
#	$ticker = substr $in, 242, 8; chomp($ticker);
	next if ($ticker =~ /[a-z]/ || $ticker =~/^\s/);
	$ticker =~ s/\s//g;
	if ($ticker =~ /[A-Z]/) {
		print ALL "$ticker\n";
		if ($ticker =~ /.DE$/ || $ticker =~ /.PA$/ || $ticker =~ /.MI$/) {
			print XTR "$ticker\n";
		}	
	}
}

close, ALL;
close, XTR;
close, IN;	
	