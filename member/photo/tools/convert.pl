#!/usr/bin/perl -w
use strict;
use Image::Magick;
use List::Util qw( min );

opendir ORIG, "orig" or die $!;
while( my $file = readdir( ORIG ) )
{
    next if $file =~ /^\./;
    print $file . "\n";

    $file =~ /(.*)\.jpg/i or next;
    my $name = $1;

    my $p = new Image::Magick;
    $p->Read("orig/$file");

    my $x = $p->Get('width');
    my $y = $p->Get('height');

    $p->Write(filename=>"${name}-o.jpg", quality=>60 );

    my $xn = 700;
    my $yn = int( $xn * $y / $x );
    if( $yn > 525 )
    {
	$yn = 525;
	$xn = int( $yn * $x / $y );
    }

    $p->Thumbnail(width=>$xn, height=>$yn);
    $p->Write(filename=>"${name}-n.jpg", quality=>75 );

    my $yt = 150;
    my $xt = int( $yt * $x / $y );

    $p->Thumbnail(width=>$xt, height=>$yt);

    $p->Write(filename=>"${name}-t.jpg", quality=>30 );
    print "  Saving $name\n";
}
