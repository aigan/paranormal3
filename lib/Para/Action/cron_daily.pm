#  $Id$  -*-perl-*-
package Para::Action::cron_daily;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw debug );

sub handler
{
    my( $req, $event ) = @_;

    my $u = $req->s->u;
    if( $u->level < 42 )
    {
	throw('denied', "Reserverat för sysadmin");
    }

    debug "Kör cron_daily!";

    return "Klar";
}

1;
