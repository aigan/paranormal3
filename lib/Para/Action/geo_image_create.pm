#  $Id$  -*-perl-*-
package Para::Action::geo_image_create;

use strict;
use Imager;
use Imager::Color;

use Data::Dumper;

## Limits:

#use constant gx_min => 11.1702;
use constant gx_min => 10.78;
#use constant gx_max => 24.1666;
use constant gx_max =>  24.01;
#use constant gy_min => 55.3654;
use constant gy_min => 55.21;
#use constant gy_max => 67.8515;
use constant gy_max => 69.21;
use constant ix_max => 300;
use constant iy_max => 675;

use vars qw( $img $dotc $gref );

#
# 210, 215 => 218, 258 == 1.038, 1,2
#
#

use Para::Widget;
use Para::Member;
use Para::Frame::Utils qw( debug );

sub handler
{
    my( $req ) = @_;

    my $fork = $req->create_fork;
    if( $fork->in_child )
    {
	&do_job($req);
	$fork->return("done");
    }

    debug "Waiting on fork";
    $fork->yield; # Wait for result
    debug "Waiting on fork - done";
    return "Image written to /images/temp/map.png";
}


sub do_job
{
    my( $req ) = @_;

    my $q = $req->q;

    my $precs;

    $dotc = Imager::Color->new("#FF0000");
#    $img = Imager->new(xsize=>ix_max, ysize=>iy_max, channels=>4);
    $img = Imager->new;
    $img->open( file => "/var/www/test.paranormal.se/test/sweden.png")
	or die $img->errstr();

    $gref =
    {
     goteborg   => { geo_x => 11.9660555172414, geo_y => 57.7123652873563 },
     stockholm  => { geo_x => 18.0549164, geo_y => 59.3273950666667 },
     umea       => { geo_x => 20.2470876315789, geo_y => 63.8272068421052 },
     malmo      => { geo_x => 13.0146291525424, geo_y => 55.5891945762712 },
    };


	if( $q->param('fastsearch') )
	{
	    my $st = "select geo_x, geo_y from member where geo_x is not null";
	    my $sth = $Para::dbh->prepare_cached( $st );
	    $sth->execute();
	    while( my $prec = $sth->fetchrow_hashref )
	    {
		my $m = Para::Member->get_by_id( $prec->{'member'} );
		plot_point( $prec );
	    }
	    $sth->finish;
	}
	else
	{
	    $precs = Para::Widget::select_persons();
	    foreach my $prec ( @$precs )
	    {
		my $m = Para::Member->get_by_id( $prec->{'member'} );
		plot_point( $m );
	    }
	}

    my $blue = Imager::Color->new("#0000FF");
    $img->box(color=> $blue, xmin=> 0, ymin=>0,
	      xmax=>ix_max-1, ymax=>iy_max-1, filled=>0);

    my $black = Imager::Color->new("#000000");
    my $green = Imager::Color->new("#009000");
    foreach my $city ( keys %$gref )
    {
	my $gx = $gref->{$city}{geo_x};
	my $gy = $gref->{$city}{geo_y};
	my( $ix, $iy ) = icord( $gx, $gy );
	$img->circle(color=>$black, r=>5, x=>$ix, y=>$iy) # ==)
	    or die $img->errstr;
	$img->circle(color=>$green, r=>3, x=>$ix, y=>$iy) # ==)
	    or die $img->errstr;
	debug "  Plotting $city at X $ix, Y $iy\n";
    }


    $img->write(file=>"/var/www/paranormal.se/images/temp/map.png")
      or die $img->errstr;

    return;
}

sub plot_point
{
    my( $m ) = @_;

    my $gx = $m->geo_x;
    my $gy = $m->geo_y;
    return unless $gx;

    my( $ix, $iy ) = icord( $gx, $gy );
    return unless $ix;

    $img->circle(color=>$dotc, r=>1, x=>$ix, y=>$iy) # ==)
      or die $img->errstr;

#    warn "  Plot dot at X $ix, Y $iy\n";
}

sub icord
{
    my( $gx, $gy ) = @_;

    my $ix = int( ( $gx - gx_min ) * ix_max / ( gx_max - gx_min ) );
    my $iy = iy_max - int( ( $gy - gy_min ) * iy_max / ( gy_max - gy_min ) );
    return undef if $ix < 0 or $iy < 0 or $ix > ix_max or $iy > iy_max;

    return( $ix, $iy );
}

1;
