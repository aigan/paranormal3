#  $Id$  -*-cperl-*-
package Para::Action::cron_daily_test;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw debug get_from_fork paraframe_dbm_open );
use Para::Constants qw( :all );

use Para::Member;

sub handler
{
    my( $req, $event ) = @_;

    my $u = $req->s->u;
    if( $u->level < 42 )
    {
	throw('denied', "Reserverat för sysadmin");
    }

    debug "Running CRON DAILY TEST";

    my $file = "/etc/mail/mailboxes";
    open( FILE, ">", $file) or die "Could not create file $file: $!\n";

    my $db = paraframe_dbm_open( $C_DB_PASSWD );
    foreach my $key ( keys %$db )
    {
	print FILE $key."\n";
    }
    close FILE;

    return "Klar";
}

1;
