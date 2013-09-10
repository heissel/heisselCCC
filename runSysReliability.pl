#!/usr/bin/perl -I/Users/tdall/copyExecs
# 
# 
($tick, $day1, $day2) = @ARGV;
die "sasasa" unless $day2;
if ($tick =~ /tick/) {
    open IN, "<../$tick" or die "bs481jazpt885";
    chomp(@tick = <IN>);
} else {
    @tick = ($tick);
}
my $btdir = "/Users/tdall/geniustrader/Backtests/";

$| = 1;
# parameters
#
$comment = "testing";
$stem = "VolBC";
$longshort = "Short";  # set to Long or Short to test only that 
#@trfac = (80, 90, 100, 110, 120);
@trfac = (80, 85, 90, 95, 100, 105);
@atrper = (5);
@atrlong = (""); # format as "R50"
@atrlim = (""); # format as "l60"
#$istop = "Vola"; # we're adding $atrper later
$istop = "Vola";
@istop = (1.0); #, 2, 2.2, 2.4, 2.6, 2.8, 3, 3.2);
#$istop = "Local";
#@istop = (0.1, 0.2, 0.3, 0.4, 0.5, 0.7, 0.9, 1.2);
open OUT, ">$btdir/out_${stem}${longshort}_${istop}.txt" || die "239db32laa390";
print OUT "#TICK\tTR\tATR\tIS\n";
if ($comment) {
    $optC = "-C \"$comment\"";
}
$fixed = "./systemReliability.pl -p ${optC}";
#print "# $stem";
# looping...
#
foreach $tick (@tick) {
    foreach $trfac (@trfac) {
        foreach $atrper (@atrper) {
            foreach $atrlong (@atrlong) {
                foreach $atrlim ($atrlim) {
                    #$system = "CandleShort";
                    $system = "${stem}${trfac}A${atrper}${atrlong}${atrlim}${longshort}"; # . "Long";
                    foreach $vistop (@istop) {
                        #$com = "$fixed $tick $day1 $day2 $system ${istop}_${atrper}_${vistop}";
                        $com = "$fixed $tick $day1 $day2 $system ${istop}_${atrper}_${vistop}x";
                        print "$com\n";
                        `$com`;
                        &processUnique();
                    }
                }
            }
        }
    }
}
close OUT;

sub processUnique {
    open UNIQ, "<$btdir/unique.txt" or die "nzt238dHW44";
    chomp($unique = <UNIQ>);
    close UNIQ;
    @g = <$btdir/rel_*_$unique.txt>;
    foreach $sfile (@g) {
        open IN, "<$sfile" or die "zz846dhhns on $sfile\n";
        while ($in = <IN>) {
            if ($in =~ /toread: (.*)/) {
                $list = $1; chomp $list;
            }
        }
        close IN;
        print OUT "$tick\t$trfac\t$atrper\t$vistop\t$list\n";
    }
}