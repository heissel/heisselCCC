use Carp;
$|=1;


# ($sym, $col) = populatePlottingArrays($rmult);
#
sub populatePlotArrays {
    # for the plotting of R color and size coded as function of two indicator values
    use strict;
    my ($rmult) = @_;
    my ($sym, $col);
    if ($rmult <= 0.0) {
        $col = 2;
    } else {
        $col = 3;
    }
    if ($rmult > 8.0) {
        $sym = 27;
    } elsif ($rmult > 6.0) {
        $sym = 26;
    } elsif ($rmult > 4.0) {
        $sym = 25;
    } elsif ($rmult > 3.0) {
        $sym = 24;
    } elsif ($rmult > 2.0) {
        $sym = 23;
    } elsif ($rmult > 1.0 || $rmult < -1.0) {
        $sym = 22;
    } else {
        $sym = 21;
    }
    return ($sym, $col);
}


1;